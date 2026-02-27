import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../models/api_response.dart';
import '../providers/api_provider.dart';
import '../providers/task_store_provider.dart';
import '../providers/recording_provider.dart';
import '../services/haptic_service.dart';
import 'waveform_painter.dart';
import 'styled_snackbar.dart';

/// Ramble mode states
enum _RamblePhase { recording, editing, processing }

/// Full-screen bottom sheet for voice brain dump.
/// Streams audio → Gemini transcribes → user edits transcript → sends via unified pipeline.
class RambleSheet extends ConsumerStatefulWidget {
  final String? prefilledCategory;

  const RambleSheet({super.key, this.prefilledCategory});

  @override
  ConsumerState<RambleSheet> createState() => _RambleSheetState();
}

class _RambleSheetState extends ConsumerState<RambleSheet> {
  _RamblePhase _phase = _RamblePhase.recording;
  bool _canStopListening = false;
  bool _isStoppingListening = false;

  final _transcriptController = TextEditingController();
  final _transcriptFocusNode = FocusNode();

  // Streaming subscriptions
  StreamSubscription<String>? _transcriptionSub;
  StreamSubscription<String>? _finalTranscriptSub;
  StreamSubscription<String>? _statusSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<List<int>>? _audioStreamSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Clear any stale state from previous sessions
      ref.read(transcriptionTextProvider.notifier).state = '';
      ref.read(waveformDataProvider.notifier).state = [];
      _startRecording();
    });
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    _transcriptController.dispose();
    _transcriptFocusNode.dispose();
    super.dispose();
  }

  /// Reset shared provider state before closing the sheet.
  /// Must be called while the widget is still mounted (before Navigator.pop).
  void _resetProviders() {
    ref.read(recordingStateProvider.notifier).state = RecordingState.idle;
    ref.read(waveformDataProvider.notifier).state = [];
    ref.read(transcriptionTextProvider.notifier).state = '';
  }

  void _cancelSubscriptions() {
    _transcriptionSub?.cancel();
    _finalTranscriptSub?.cancel();
    _statusSub?.cancel();
    _errorSub?.cancel();
    _audioStreamSub?.cancel();
    _transcriptionSub = null;
    _finalTranscriptSub = null;
    _statusSub = null;
    _errorSub = null;
    _audioStreamSub = null;
  }

  // ────────── Recording (WebSocket streaming) ──────────

  Future<void> _startRecording() async {
    debugPrint('[Ramble] _startRecording called');
    _canStopListening = false;
    setState(() => _phase = _RamblePhase.recording);

    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) _canStopListening = true;
    });

    try {
      final audioService = ref.read(audioServiceProvider);
      final rambleWs = ref.read(rambleWebSocketProvider);

      // 1. Connect WebSocket to backend
      debugPrint('[Ramble] Connecting WebSocket...');
      await rambleWs.connect(
        userId: AppConstants.defaultUserId,
      );

      // 2. Subscribe to server events
      _transcriptionSub = rambleWs.transcriptionStream.listen((text) {
        if (mounted && _phase == _RamblePhase.recording) {
          ref.read(transcriptionTextProvider.notifier).state = text;
        }
      });

      _finalTranscriptSub = rambleWs.finalTranscriptStream.listen((text) {
        if (mounted) {
          debugPrint('[Ramble] Final transcript received: ${text.length} chars');
          _transcriptController.text = text;
        }
      });

      _errorSub = rambleWs.errorStream.listen((error) {
        debugPrint('[Ramble] Server error: $error');
        if (mounted && _phase == _RamblePhase.recording) {
          showStyledSnackbar(context,
            message: 'Stream error: $error',
            style: SnackbarStyle.error,
          );
        }
      });

      _statusSub = rambleWs.statusStream.listen((status) {
        debugPrint('[Ramble] Status: $status');
      });

      // 3. Start audio streaming (PCM 16kHz mono)
      debugPrint('[Ramble] Starting audio stream...');
      final audioStream = await audioService.startStream();

      // 4. Pipe audio chunks to WebSocket as base64
      _audioStreamSub = audioStream.listen((pcmChunk) {
        final base64Data = base64Encode(Uint8List.fromList(pcmChunk));
        rambleWs.sendAudioChunk(base64Data);
      });

      ref.read(recordingStateProvider.notifier).state = RecordingState.listening;
      debugPrint('[Ramble] Recording started');
    } catch (e) {
      debugPrint('[Ramble] _startRecording FAILED: $e');
      if (mounted) {
        _resetProviders();
        Navigator.pop(context);
        showStyledSnackbar(context,
          message: 'Failed to start: $e',
          style: SnackbarStyle.error,
        );
      }
    }
  }

  Future<void> _stopAndEdit() async {
    debugPrint('[Ramble] _stopAndEdit called');
    if (_isStoppingListening || !_canStopListening) return;
    if (_phase != _RamblePhase.recording) return;
    _isStoppingListening = true;
    HapticService.light();

    try {
      // Stop audio stream
      await _audioStreamSub?.cancel();
      _audioStreamSub = null;

      final audioService = ref.read(audioServiceProvider);
      await audioService.stopStream();
      debugPrint('[Ramble] Audio stream stopped');

      // Stop WebSocket session — waits for final_transcript
      final rambleWs = ref.read(rambleWebSocketProvider);
      final finalTranscript = await rambleWs.stop();
      debugPrint('[Ramble] WebSocket stopped, transcript: ${finalTranscript?.length ?? 0} chars');

      // Cancel event subscriptions
      _cancelSubscriptions();

      ref.read(recordingStateProvider.notifier).state = RecordingState.idle;

      // Use returned transcript, fall back to controller text (from streaming chunks)
      final transcript = (finalTranscript ?? _transcriptController.text).trim();
      if (transcript.isEmpty) {
        if (mounted) {
          _resetProviders();
          Navigator.pop(context);
          showStyledSnackbar(context,
            message: 'Nothing heard. Try again.',
            style: SnackbarStyle.info,
          );
        }
        return;
      }

      debugPrint('[Ramble] → editing phase, ${transcript.length} chars');
      setState(() => _phase = _RamblePhase.editing);
    } catch (e) {
      debugPrint('[Ramble] _stopAndEdit FAILED: $e');
      if (mounted) {
        _resetProviders();
        Navigator.pop(context);
        showStyledSnackbar(context,
          message: 'Failed to stop: $e',
          style: SnackbarStyle.error,
        );
      }
    } finally {
      _isStoppingListening = false;
    }
  }

  // ────────── Processing ──────────

  Future<void> _sendTranscript() async {
    final text = _transcriptController.text.trim();
    if (text.isEmpty) return;

    HapticService.medium();
    _transcriptFocusNode.unfocus();
    setState(() => _phase = _RamblePhase.processing);

    try {
      final apiService = ref.read(apiServiceProvider);
      final response = await apiService.processVoiceCommand(
        text,
        AppConstants.defaultUserId,
      );
      await ref.read(taskStoreProvider.notifier).fetchAll();

      if (mounted) {
        _resetProviders();
        Navigator.pop(context, response); // Return response to caller
      }
    } catch (e) {
      if (mounted) {
        _resetProviders();
        // Pop with error response so caller can show snackbar
        Navigator.pop(context, AgentResponse(
          success: false,
          message: 'Failed to process: $e',
          type: 'error',
        ));
      }
    }
  }

  void _reRecord() {
    HapticService.light();
    _transcriptController.clear();
    ref.read(transcriptionTextProvider.notifier).state = '';
    ref.read(waveformDataProvider.notifier).state = [];
    _startRecording();
  }

  // ────────── Build ──────────

  @override
  Widget build(BuildContext context) {
    final paletteMap = ref.watch(domainPalettesProvider);
    final domain = DomainColors.getDomain(
      widget.prefilledCategory ?? 'work', true, paletteMap,
    );

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: AppColors.darkBg,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppSpacing.radiusLg),
          topRight: Radius.circular(AppSpacing.radiusLg),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDragHandle(),
          _buildHeader(domain),
          Flexible(child: _buildBody(domain)),
          _buildFooter(domain),
        ],
      ),
    );
  }

  Widget _buildDragHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.darkText.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(DomainPalette domain) {
    final String title;
    final String subtitle;

    switch (_phase) {
      case _RamblePhase.recording:
        title = 'Listening...';
        subtitle = 'Say everything you need to get done.';
      case _RamblePhase.editing:
        title = 'Edit transcript';
        subtitle = 'Review and correct before sending.';
      case _RamblePhase.processing:
        title = 'Processing...';
        subtitle = 'Detecting intents and executing.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: domain.primary.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ramble',
            style: AppTypography.metadataText(
              color: domain.primary.withValues(alpha: 0.8),
            ).copyWith(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: AppTypography.metadataText(color: domain.primary)
                .copyWith(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppTypography.metadataText(
              color: AppColors.darkText.withValues(alpha: 0.5),
            ).copyWith(fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(DomainPalette domain) {
    switch (_phase) {
      case _RamblePhase.recording:
        return _buildRecordingBody(domain);
      case _RamblePhase.editing:
        return _buildEditingBody(domain);
      case _RamblePhase.processing:
        return _buildLoadingBody(domain);
    }
  }

  Widget _buildRecordingBody(DomainPalette domain) {
    final transcription = ref.watch(transcriptionTextProvider);
    final audioService = ref.read(audioServiceProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.xl),
          // Waveform — self-contained 60fps, no provider rebuilds
          AnimatedWaveform(
            amplitudeSource: () => audioService.waveformData,
            color: domain.primary,
            height: 48,
          ),
          const SizedBox(height: AppSpacing.md),
          // Live transcription
          Text(
            transcription.isNotEmpty ? transcription : 'Start speaking...',
            style: AppTypography.metadataText(
              color: AppColors.darkText.withValues(
                alpha: transcription.isNotEmpty ? 0.8 : 0.4,
              ),
            ).copyWith(fontSize: 15),
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xl),
          // Stop button
          GestureDetector(
            onTap: _canStopListening ? _stopAndEdit : null,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: domain.primary,
                shape: BoxShape.circle,
                boxShadow: domain.glow != null
                    ? [BoxShadow(color: domain.glow!, blurRadius: 16, spreadRadius: 4)]
                    : null,
              ),
              child: Icon(
                Icons.stop_rounded,
                size: 32,
                color: domain.textOnPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Tap to stop',
            style: AppTypography.metadataText(
              color: AppColors.darkText.withValues(alpha: 0.4),
            ).copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildEditingBody(DomainPalette domain) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: TextField(
        controller: _transcriptController,
        focusNode: _transcriptFocusNode,
        maxLines: null,
        minLines: 4,
        style: AppTypography.metadataText(color: AppColors.darkText)
            .copyWith(fontSize: 15, height: 1.5),
        decoration: InputDecoration(
          hintText: 'Your transcript will appear here...',
          hintStyle: AppTypography.metadataText(
            color: AppColors.darkText.withValues(alpha: 0.3),
          ).copyWith(fontSize: 15),
          filled: true,
          fillColor: AppColors.darkText.withValues(alpha: 0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            borderSide: BorderSide(
              color: domain.primary.withValues(alpha: 0.3),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            borderSide: BorderSide(
              color: domain.primary.withValues(alpha: 0.2),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            borderSide: BorderSide(
              color: domain.primary.withValues(alpha: 0.6),
            ),
          ),
          contentPadding: const EdgeInsets.all(AppSpacing.md),
        ),
      ),
    );
  }

  Widget _buildLoadingBody(DomainPalette domain) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: domain.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(DomainPalette domain) {
    if (_phase == _RamblePhase.recording ||
        _phase == _RamblePhase.processing) {
      return const SizedBox(height: AppSpacing.md);
    }

    // Editing phase footer
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg,
        MediaQuery.of(context).padding.bottom + AppSpacing.md,
      ),
      child: Row(
        children: [
          // Re-record button
          Expanded(
            child: GestureDetector(
              onTap: _reRecord,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                    color: domain.primary.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.mic_none_rounded, size: 18, color: domain.primary),
                    const SizedBox(width: 6),
                    Text(
                      'Re-record',
                      style: AppTypography.metadataText(color: domain.primary)
                          .copyWith(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Send button
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: _sendTranscript,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: domain.primary,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  boxShadow: domain.glow != null
                      ? [BoxShadow(
                          color: domain.glow!,
                          blurRadius: 12,
                          spreadRadius: 2,
                        )]
                      : null,
                ),
                child: Center(
                  child: Text(
                    'Send',
                    style: AppTypography.metadataText(
                      color: domain.textOnPrimary,
                    ).copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
