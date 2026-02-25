import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../providers/recording_provider.dart';
import '../providers/api_provider.dart';
import '../providers/task_store_provider.dart';
import '../services/haptic_service.dart';
import 'waveform_painter.dart';
import 'question_bottom_sheet.dart';
import 'subtask_selection_sheet.dart';
import 'styled_snackbar.dart';

/// Dual-mode input pill: tap-to-talk voice + keyboard text entry
class PushToTalkButton extends ConsumerStatefulWidget {
  const PushToTalkButton({super.key});

  @override
  ConsumerState<PushToTalkButton> createState() => _PushToTalkButtonState();
}

class _PushToTalkButtonState extends ConsumerState<PushToTalkButton> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  bool _canStopListening = false;
  bool _isStoppingListening = false;

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recordingState = ref.watch(recordingStateProvider);
    final waveformData = ref.watch(waveformDataProvider);
    final transcription = ref.watch(transcriptionTextProvider);

    final isListening = recordingState == RecordingState.listening;
    final isProcessing = recordingState == RecordingState.processing;
    final isTyping = recordingState == RecordingState.typing;

    final screenWidth = MediaQuery.of(context).size.width;

    // Dimensions based on state
    double width;
    double height;
    if (isTyping) {
      width = screenWidth - 48;
      height = AppSpacing.ctaIdleHeight;
    } else if (isListening) {
      width = AppSpacing.ctaActiveWidth;
      height = AppSpacing.ctaActiveHeight;
    } else {
      // idle + processing
      width = AppSpacing.ctaIdleWidth;
      height = AppSpacing.ctaIdleHeight;
    }

    // Colors
    final idleBg = AppColors.darkText;
    final idleText = AppColors.darkBg;
    final activeBg = DomainColors.workDark.primary;
    final activeText = DomainColors.workDark.textOnPrimary;
    final bgColor = (isListening || isProcessing) ? activeBg : idleBg;

    return Center(
      child: AnimatedContainer(
        duration: AppAnimations.ctaExpand,
        curve: AppAnimations.easeOutQuint,
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        clipBehavior: Clip.antiAlias,
        child: _buildContent(
          recordingState,
          waveformData,
          transcription,
          idleText,
          activeText,
        ),
      ),
    );
  }

  Widget _buildContent(
    RecordingState state,
    List<double> waveformData,
    String transcription,
    Color idleText,
    Color activeText,
  ) {
    switch (state) {
      case RecordingState.idle:
        return _buildIdleContent(idleText);
      case RecordingState.listening:
        return _buildListeningContent(waveformData, transcription, activeText);
      case RecordingState.processing:
        return _buildProcessingContent(activeText);
      case RecordingState.typing:
        return _buildTypingContent(idleText);
    }
  }

  Widget _buildIdleContent(Color textColor) {
    return Row(
      children: [
        // Keyboard half
        Expanded(
          child: GestureDetector(
            onTap: _activateKeyboard,
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.keyboard_alt_outlined, size: 16, color: textColor),
                  const SizedBox(width: 6),
                  Text('Type', style: AppTypography.ctaLabelText(color: textColor)),
                ],
              ),
            ),
          ),
        ),
        // Divider
        Container(
          width: 1,
          height: 24,
          color: textColor.withValues(alpha: 0.15),
        ),
        // Voice half
        Expanded(
          child: GestureDetector(
            onTap: _startListening,
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mic_none_rounded, size: 16, color: textColor),
                  const SizedBox(width: 6),
                  Text('Speak', style: AppTypography.ctaLabelText(color: textColor)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListeningContent(
    List<double> waveformData,
    String transcription,
    Color activeText,
  ) {
    return GestureDetector(
      onTap: () {
        if (_canStopListening) _stopListening();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(Icons.stop_circle_outlined, size: 24, color: activeText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomPaint(
                    painter: WaveformPainter(
                      amplitudes: waveformData,
                      color: activeText,
                    ),
                    child: const SizedBox(height: 24),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    transcription.isNotEmpty ? transcription : 'Listening...',
                    style: TextStyle(
                      color: activeText.withValues(
                        alpha: transcription.isNotEmpty ? 1.0 : 0.6,
                      ),
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessingContent(Color activeText) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: AnimatedOpacity(
            opacity: 0.5 + (0.5 * ((index + 1) % 3) / 2),
            duration: const Duration(milliseconds: 500),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: activeText,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildTypingContent(Color textColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          // Close button
          GestureDetector(
            onTap: _cancelTyping,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.close_rounded,
                size: 20,
                color: textColor.withValues(alpha: 0.5),
              ),
            ),
          ),
          // Text field
          Expanded(
            child: TextField(
              controller: _textController,
              focusNode: _focusNode,
              autofocus: true,
              style: AppTypography.ctaLabelText(color: textColor),
              decoration: InputDecoration(
                hintText: 'What do you want to do?',
                hintStyle: AppTypography.ctaLabelText(
                  color: textColor.withValues(alpha: 0.4),
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
              onSubmitted: (_) => _submitText(),
              textInputAction: TextInputAction.send,
            ),
          ),
          // Send button
          GestureDetector(
            onTap: _submitText,
            child: Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: textColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_upward_rounded,
                size: 18,
                color: AppColors.darkText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // === Actions ===

  void _activateKeyboard() {
    HapticService.light();
    ref.read(recordingStateProvider.notifier).state = RecordingState.typing;
  }

  Future<void> _startListening() async {
    // Guard: ignore if already listening or processing
    final currentState = ref.read(recordingStateProvider);
    if (currentState == RecordingState.listening ||
        currentState == RecordingState.processing) {
      return;
    }

    HapticService.medium();
    _canStopListening = false;

    // Immediate state change for responsive UI
    ref.read(recordingStateProvider.notifier).state = RecordingState.listening;

    // Allow stopping after minimum duration to prevent accidental double-tap
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _canStopListening = true;
    });

    try {
      final speechService = ref.read(speechServiceProvider);

      // Wire callbacks
      speechService.onResult = (text, isFinal) {
        if (mounted) {
          ref.read(transcriptionTextProvider.notifier).state = text;
        }
      };

      speechService.onSoundLevelChange = (level) {
        if (mounted) {
          final current = List<double>.from(ref.read(waveformDataProvider));
          current.add(level);
          if (current.length > 50) current.removeAt(0);
          ref.read(waveformDataProvider.notifier).state = current;
        }
      };

      speechService.onError = (error) {
        if (mounted) {
          _resetState();
          showStyledSnackbar(context,
            message: 'Speech error: $error',
            style: SnackbarStyle.error,
          );
        }
      };

      // Fast if already initialized via eager init in HomeScreen
      await speechService.initialize();
      await speechService.startListening();
    } catch (e) {
      _resetState();
      if (mounted) {
        showStyledSnackbar(context,
          message: 'Failed to start listening: $e',
          style: SnackbarStyle.error,
        );
      }
    }
  }

  Future<void> _stopListening() async {
    if (_isStoppingListening) return;
    _isStoppingListening = true;

    try {
      HapticService.light();

      final speechService = ref.read(speechServiceProvider);
      await speechService.stopListening();

      final transcription = ref.read(transcriptionTextProvider);

      if (transcription.trim().isEmpty) {
        _resetState();
        if (mounted) {
          showStyledSnackbar(context,
            message: 'Nothing heard. Try again.',
            style: SnackbarStyle.info,
          );
        }
        return;
      }

      await _processCommand(transcription);
    } catch (e) {
      _resetState();
      if (mounted) {
        showStyledSnackbar(context,
          message: 'Failed to process: $e',
          style: SnackbarStyle.error,
        );
      }
    } finally {
      _isStoppingListening = false;
    }
  }

  Future<void> _submitText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _cancelTyping();
      return;
    }

    _focusNode.unfocus();
    _textController.clear();

    await _processCommand(text);
  }

  void _cancelTyping() {
    _focusNode.unfocus();
    _textController.clear();
    _resetState();
  }

  Future<void> _processCommand(String text) async {
    ref.read(recordingStateProvider.notifier).state = RecordingState.processing;

    try {
      final apiService = ref.read(apiServiceProvider);
      final response = await apiService.processVoiceCommand(
        text,
        AppConstants.defaultUserId,
      );

      await ref.read(taskStoreProvider.notifier).fetchAll();

      _resetState();

      if (mounted) {
        if (response.type == 'question' && response.data != null) {
          final action = response.data!['action'] as String?;
          if (action == 'select_subtasks') {
            final parentTask = response.data!['parent_task'] as Map<String, dynamic>;
            final suggestions = (response.data!['suggestions'] as List).cast<String>();
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => SubtaskSelectionSheet(
                parentTask: parentTask,
                suggestions: suggestions,
              ),
            );
          } else {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => QuestionBottomSheet(response: response),
            );
          }
        } else {
          showStyledSnackbar(context,
            message: response.message,
            style: SnackbarStyle.success,
          );
        }
      }
    } catch (e) {
      _resetState();
      if (mounted) {
        showStyledSnackbar(context,
          message: 'Failed to process: $e',
          style: SnackbarStyle.error,
        );
      }
    }
  }

  void _resetState() {
    ref.read(recordingStateProvider.notifier).state = RecordingState.idle;
    ref.read(waveformDataProvider.notifier).state = [];
    ref.read(transcriptionTextProvider.notifier).state = '';
  }
}
