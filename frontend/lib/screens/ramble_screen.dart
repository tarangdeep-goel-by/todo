import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../models/api_response.dart';
import '../providers/api_provider.dart';
import '../providers/task_store_provider.dart';
import '../providers/recording_provider.dart';
import '../services/haptic_service.dart';
import '../widgets/waveform_painter.dart';
import '../widgets/styled_snackbar.dart';

/// Ramble mode phases
enum _RamblePhase { recording, editing, processing, reviewing }

/// Full-screen route for voice brain dump.
/// Streams audio -> Gemini transcribes -> user edits -> brain dump extracts proposals -> user reviews -> submit.
class RambleScreen extends ConsumerStatefulWidget {
  final String? prefilledCategory;

  const RambleScreen({super.key, this.prefilledCategory});

  @override
  ConsumerState<RambleScreen> createState() => _RambleScreenState();
}

class _RambleScreenState extends ConsumerState<RambleScreen> {
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

  // Reviewing state
  List<BrainDumpTaskProposal> _proposals = [];
  final Set<String> _deselectedIds = {};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
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

  // ────────── Close handling ──────────

  Future<bool> _onWillPop() async {
    if (_phase == _RamblePhase.reviewing && _proposals.isNotEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.darkBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          title: Text(
            'You have unsaved tasks',
            style: AppTypography.metadataText(color: AppColors.darkText)
                .copyWith(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          content: Text(
            '${_proposals.length - _deselectedIds.length} task(s) will be lost.',
            style: AppTypography.metadataText(
              color: AppColors.darkText.withValues(alpha: 0.6),
            ).copyWith(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Keep editing',
                style: AppTypography.metadataText(
                  color: AppColors.darkText.withValues(alpha: 0.7),
                ).copyWith(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Discard',
                style: AppTypography.metadataText(
                  color: AppColors.deleteAction,
                ).copyWith(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
      if (discard != true) return false;
    }
    _resetProviders();
    return true;
  }

  void _close() async {
    if (await _onWillPop()) {
      if (mounted) Navigator.pop(context);
    }
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

      debugPrint('[Ramble] Connecting WebSocket...');
      await rambleWs.connect(userId: AppConstants.defaultUserId);

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

      debugPrint('[Ramble] Starting audio stream...');
      final audioStream = await audioService.startStream();

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
      await _audioStreamSub?.cancel();
      _audioStreamSub = null;

      final audioService = ref.read(audioServiceProvider);
      await audioService.stopStream();
      debugPrint('[Ramble] Audio stream stopped');

      final rambleWs = ref.read(rambleWebSocketProvider);
      final finalTranscript = await rambleWs.stop();
      debugPrint('[Ramble] WebSocket stopped, transcript: ${finalTranscript?.length ?? 0} chars');

      _cancelSubscriptions();
      ref.read(recordingStateProvider.notifier).state = RecordingState.idle;

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

      debugPrint('[Ramble] -> editing phase, ${transcript.length} chars');
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

  // ────────── Processing (Brain Dump) ──────────

  Future<void> _processBrainDump() async {
    final text = _transcriptController.text.trim();
    if (text.isEmpty) return;

    HapticService.medium();
    _transcriptFocusNode.unfocus();
    setState(() => _phase = _RamblePhase.processing);

    try {
      final apiService = ref.read(apiServiceProvider);
      final response = await apiService.processBrainDump(
        transcription: text,
        userId: AppConstants.defaultUserId,
        category: widget.prefilledCategory,
      );

      if (mounted) {
        setState(() {
          _proposals = response.tasks;
          _deselectedIds.clear();
          _phase = _RamblePhase.reviewing;
        });
      }
    } catch (e) {
      debugPrint('[Ramble] _processBrainDump FAILED: $e');
      if (mounted) {
        showStyledSnackbar(context,
          message: 'Failed to process: $e',
          style: SnackbarStyle.error,
        );
        setState(() => _phase = _RamblePhase.editing);
      }
    }
  }

  // ────────── Reviewing ──────────

  Future<void> _submitProposals() async {
    final selected = _proposals
        .where((p) => !_deselectedIds.contains(p.id))
        .toList();
    if (selected.isEmpty) return;

    HapticService.medium();
    setState(() => _isSubmitting = true);

    try {
      final apiService = ref.read(apiServiceProvider);
      final response = await apiService.submitBrainDump(
        userId: AppConstants.defaultUserId,
        tasks: selected,
      );

      await ref.read(taskStoreProvider.notifier).fetchAll();

      if (mounted) {
        _resetProviders();
        Navigator.pop(context, (
          success: true,
          message: response.message,
        ));
      }
    } catch (e) {
      debugPrint('[Ramble] _submitProposals FAILED: $e');
      if (mounted) {
        setState(() => _isSubmitting = false);
        showStyledSnackbar(context,
          message: 'Failed to submit: $e',
          style: SnackbarStyle.error,
        );
      }
    }
  }

  void _toggleProposal(String id) {
    setState(() {
      if (_deselectedIds.contains(id)) {
        _deselectedIds.remove(id);
      } else {
        _deselectedIds.add(id);
      }
    });
  }

  void _editProposal(BrainDumpTaskProposal proposal) async {
    HapticService.medium();
    final paletteMap = ref.read(domainPalettesProvider);
    final edited = await showModalBottomSheet<BrainDumpTaskProposal>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProposalEditSheet(
        proposal: proposal,
        paletteMap: paletteMap,
      ),
    );
    if (edited != null) {
      setState(() {
        final idx = _proposals.indexWhere((p) => p.id == edited.id);
        if (idx != -1) _proposals[idx] = edited;
      });
    }
  }

  void _reRecord() {
    HapticService.light();
    _transcriptController.clear();
    _proposals = [];
    _deselectedIds.clear();
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _onWillPop()) {
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.darkBg,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(domain),
              _buildHeader(domain),
              Expanded(child: _buildBody(domain)),
              _buildFooter(domain),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(DomainPalette domain) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm, AppSpacing.sm, AppSpacing.lg, 0,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _close,
            icon: Icon(
              Icons.close_rounded,
              color: AppColors.darkText.withValues(alpha: 0.6),
              size: 24,
            ),
          ),
          Text(
            'Ramble',
            style: AppTypography.metadataText(
              color: domain.primary.withValues(alpha: 0.8),
            ).copyWith(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
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
        subtitle = 'Extracting tasks from your ramble.';
      case _RamblePhase.reviewing:
        title = 'Review tasks';
        subtitle = 'Tap to toggle, long-press to edit.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm,
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
      case _RamblePhase.reviewing:
        return _buildReviewingBody(domain);
    }
  }

  Widget _buildRecordingBody(DomainPalette domain) {
    final transcription = ref.watch(transcriptionTextProvider);
    final audioService = ref.read(audioServiceProvider);

    return Column(
      children: [
        // Waveform strip at top
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm,
          ),
          child: AnimatedWaveform(
            amplitudeSource: () => audioService.waveformData,
            color: domain.primary,
            height: 48,
          ),
        ),
        // Scrollable transcription area fills remaining space
        Expanded(
          child: SingleChildScrollView(
            reverse: true,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                transcription.isNotEmpty ? transcription : 'Start speaking...',
                style: AppTypography.metadataText(
                  color: AppColors.darkText.withValues(
                    alpha: transcription.isNotEmpty ? 0.8 : 0.4,
                  ),
                ).copyWith(fontSize: 16, height: 1.5),
                textAlign: TextAlign.left,
              ),
            ),
          ),
        ),
      ],
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
    return Center(
      child: SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          color: domain.primary,
        ),
      ),
    );
  }

  Widget _buildReviewingBody(DomainPalette domain) {
    if (_proposals.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.mic_off_rounded,
              size: 48,
              color: AppColors.darkText.withValues(alpha: 0.3),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No tasks detected',
              style: AppTypography.metadataText(
                color: AppColors.darkText.withValues(alpha: 0.6),
              ).copyWith(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Try re-recording with more detail',
              style: AppTypography.metadataText(
                color: AppColors.darkText.withValues(alpha: 0.4),
              ).copyWith(fontSize: 13),
            ),
          ],
        ),
      );
    }

    final paletteMap = ref.watch(domainPalettesProvider);

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: _proposals.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, index) {
        final proposal = _proposals[index];
        final isSelected = !_deselectedIds.contains(proposal.id);
        final cardDomain = DomainColors.getDomain(
          proposal.category, true, paletteMap,
        );
        return _buildProposalCard(proposal, isSelected, cardDomain);
      },
    );
  }

  Widget _buildProposalCard(
    BrainDumpTaskProposal proposal,
    bool isSelected,
    DomainPalette domain,
  ) {
    return GestureDetector(
      onTap: () => _toggleProposal(proposal.id),
      onLongPress: () => _editProposal(proposal),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isSelected ? 1.0 : 0.4,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            color: domain.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: domain.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left accent bar
              Container(
                width: 4,
                height: 40,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: proposal.action == 'delete'
                      ? AppColors.deleteAction
                      : domain.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      proposal.content,
                      style: AppTypography.metadataText(color: domain.primary)
                          .copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _buildChip(
                          _actionLabel(proposal.action),
                          _actionColor(proposal.action, domain),
                        ),
                        _buildChip(
                          proposal.category[0].toUpperCase() +
                              proposal.category.substring(1),
                          domain.primary,
                        ),
                        if (proposal.priority != null &&
                            proposal.priority != 'none')
                          _buildChip(
                            proposal.priority![0].toUpperCase() +
                                proposal.priority!.substring(1),
                            _priorityColor(proposal.priority!),
                          ),
                        if (proposal.dueDate != null)
                          _buildChip(
                            DateFormat('MMM d').format(proposal.dueDate!),
                            domain.primary.withValues(alpha: 0.7),
                          ),
                        if (proposal.action == 'move' &&
                            proposal.targetContent != null)
                          _buildChip(
                            '\u2192 ${proposal.targetContent}',
                            AppColors.dueSoon,
                          ),
                        if (proposal.changes != null)
                          for (final entry in proposal.changes!.entries)
                            _buildChip(
                              '${entry.key}: ${entry.value}',
                              AppColors.darkText.withValues(alpha: 0.6),
                            ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Checkbox
              Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? domain.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: domain.primary.withValues(
                      alpha: isSelected ? 1.0 : 0.4,
                    ),
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: domain.textOnPrimary,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTypography.metadataText(color: color)
            .copyWith(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  String _actionLabel(String action) {
    return switch (action) {
      'complete' => 'Complete',
      'edit' => 'Edit',
      'delete' => 'Delete',
      'move' => 'Move',
      _ => 'Add',
    };
  }

  Color _actionColor(String action, DomainPalette domain) {
    return switch (action) {
      'complete' => AppColors.completed,
      'edit' => AppColors.dueSoon,
      'delete' => AppColors.deleteAction,
      'move' => AppColors.dueSoon,
      _ => domain.primary,
    };
  }

  Color _priorityColor(String priority) {
    return switch (priority.toLowerCase()) {
      'high' => AppColors.priorityHigh,
      'medium' => AppColors.priorityMedium,
      'low' => AppColors.priorityLow,
      _ => AppColors.darkText.withValues(alpha: 0.5),
    };
  }

  Widget _buildFooter(DomainPalette domain) {
    if (_phase == _RamblePhase.recording) {
      return _buildRecordingFooter(domain);
    }

    if (_phase == _RamblePhase.processing) {
      return const SizedBox(height: AppSpacing.md);
    }

    if (_phase == _RamblePhase.editing) {
      return _buildEditingFooter(domain);
    }

    // Reviewing phase
    return _buildReviewingFooter(domain);
  }

  Widget _buildRecordingFooter(DomainPalette domain) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + AppSpacing.lg,
        top: AppSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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

  Widget _buildEditingFooter(DomainPalette domain) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg,
        MediaQuery.of(context).padding.bottom + AppSpacing.md,
      ),
      child: Row(
        children: [
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
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: _processBrainDump,
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

  Widget _buildReviewingFooter(DomainPalette domain) {
    final selectedCount = _proposals.length - _deselectedIds.length;
    final canSubmit = selectedCount > 0 && !_isSubmitting;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg,
        MediaQuery.of(context).padding.bottom + AppSpacing.md,
      ),
      child: Row(
        children: [
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
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: canSubmit ? _submitProposals : null,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: canSubmit ? 1.0 : 0.4,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: domain.primary,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    boxShadow: domain.glow != null && canSubmit
                        ? [BoxShadow(
                            color: domain.glow!,
                            blurRadius: 12,
                            spreadRadius: 2,
                          )]
                        : null,
                  ),
                  child: Center(
                    child: _isSubmitting
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: domain.textOnPrimary,
                            ),
                          )
                        : Text(
                            'Confirm $selectedCount Action${selectedCount == 1 ? '' : 's'}',
                            style: AppTypography.metadataText(
                              color: domain.textOnPrimary,
                            ).copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
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

// ────────── Proposal Edit Sheet ──────────

class _ProposalEditSheet extends StatefulWidget {
  final BrainDumpTaskProposal proposal;
  final Map<String, DomainPalette> paletteMap;

  const _ProposalEditSheet({
    required this.proposal,
    required this.paletteMap,
  });

  @override
  State<_ProposalEditSheet> createState() => _ProposalEditSheetState();
}

class _ProposalEditSheetState extends State<_ProposalEditSheet> {
  late final TextEditingController _titleController;
  late String _category;
  late String _priority;
  DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.proposal.content);
    _category = widget.proposal.category;
    _priority = widget.proposal.priority ?? 'none';
    _dueDate = widget.proposal.dueDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final edited = BrainDumpTaskProposal(
      id: widget.proposal.id,
      action: widget.proposal.action,
      content: title,
      description: widget.proposal.description,
      category: _category,
      dueDate: _dueDate,
      priority: _priority == 'none' ? null : _priority,
      parentId: widget.proposal.parentId,
      labels: widget.proposal.labels,
      changes: widget.proposal.changes,
      matchedTaskId: widget.proposal.matchedTaskId,
      targetParentId: widget.proposal.targetParentId,
      targetContent: widget.proposal.targetContent,
    );
    Navigator.pop(context, edited);
  }

  Future<void> _pickDate() async {
    final domain = DomainColors.getDomain(_category, true, widget.paletteMap);
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: domain.primary,
              surface: AppColors.darkBg,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final domain = DomainColors.getDomain(_category, true, widget.paletteMap);
    final categories = widget.paletteMap.keys.toList();
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(bottom: bottomPad),
      decoration: BoxDecoration(
        color: AppColors.darkBg,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusLg),
        ),
        border: Border(
          top: BorderSide(color: domain.primary.withValues(alpha: 0.3)),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.darkText.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm,
              ),
              child: Text(
                'Edit proposal',
                style: AppTypography.metadataText(color: AppColors.darkText)
                    .copyWith(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),

            // Title field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: TextField(
                controller: _titleController,
                style: AppTypography.metadataText(color: AppColors.darkText)
                    .copyWith(fontSize: 15, height: 1.4),
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Title',
                  labelStyle: AppTypography.metadataText(
                    color: AppColors.darkText.withValues(alpha: 0.5),
                  ).copyWith(fontSize: 13),
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
            ),

            const SizedBox(height: AppSpacing.md),

            // Category chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Category',
                    style: AppTypography.metadataText(
                      color: AppColors.darkText.withValues(alpha: 0.5),
                    ).copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: categories.map((cat) {
                      final catDomain = DomainColors.getDomain(
                        cat, true, widget.paletteMap,
                      );
                      final selected = cat == _category;
                      return GestureDetector(
                        onTap: () => setState(() => _category = cat),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? catDomain.primary
                                : catDomain.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: catDomain.primary.withValues(
                                alpha: selected ? 1.0 : 0.3,
                              ),
                            ),
                          ),
                          child: Text(
                            cat[0].toUpperCase() + cat.substring(1),
                            style: AppTypography.metadataText(
                              color: selected
                                  ? catDomain.textOnPrimary
                                  : catDomain.primary,
                            ).copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // Priority chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Priority',
                    style: AppTypography.metadataText(
                      color: AppColors.darkText.withValues(alpha: 0.5),
                    ).copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ['none', 'low', 'medium', 'high'].map((p) {
                      final selected = p == _priority;
                      final color = _priorityChipColor(p);
                      return GestureDetector(
                        onTap: () => setState(() => _priority = p),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? color
                                : color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: color.withValues(
                                alpha: selected ? 1.0 : 0.3,
                              ),
                            ),
                          ),
                          child: Text(
                            p[0].toUpperCase() + p.substring(1),
                            style: AppTypography.metadataText(
                              color: selected ? Colors.white : color,
                            ).copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // Due date
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Due date',
                    style: AppTypography.metadataText(
                      color: AppColors.darkText.withValues(alpha: 0.5),
                    ).copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _pickDate,
                    onLongPress: () => setState(() => _dueDate = null),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: domain.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: domain.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 14,
                            color: domain.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _dueDate != null
                                ? DateFormat('MMM d').format(_dueDate!)
                                : 'No date',
                            style: AppTypography.metadataText(
                              color: domain.primary,
                            ).copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_dueDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Long-press to clear',
                        style: AppTypography.metadataText(
                          color: AppColors.darkText.withValues(alpha: 0.3),
                        ).copyWith(fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // Footer buttons
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg,
                MediaQuery.of(context).padding.bottom + AppSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                          border: Border.all(
                            color: AppColors.darkText.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Cancel',
                            style: AppTypography.metadataText(
                              color: AppColors.darkText.withValues(alpha: 0.7),
                            ).copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: _save,
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: domain.primary,
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Save',
                            style: AppTypography.metadataText(
                              color: domain.textOnPrimary,
                            ).copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _priorityChipColor(String priority) {
    return switch (priority) {
      'high' => AppColors.priorityHigh,
      'medium' => AppColors.priorityMedium,
      'low' => AppColors.priorityLow,
      _ => AppColors.darkText.withValues(alpha: 0.5),
    };
  }
}
