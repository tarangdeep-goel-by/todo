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

/// Push-to-talk CTA button with speech recognition
class PushToTalkButton extends ConsumerStatefulWidget {
  const PushToTalkButton({super.key});

  @override
  ConsumerState<PushToTalkButton> createState() => _PushToTalkButtonState();
}

class _PushToTalkButtonState extends ConsumerState<PushToTalkButton> {
  @override
  Widget build(BuildContext context) {
    final recordingState = ref.watch(recordingStateProvider);
    final waveformData = ref.watch(waveformDataProvider);
    final transcription = ref.watch(transcriptionTextProvider);

    final isListening = recordingState == RecordingState.listening;
    final isProcessing = recordingState == RecordingState.processing;

    // Button colors (dark mode only)
    final idleBg = AppColors.darkText;
    final idleText = AppColors.darkBg;
    final activeBg = DomainColors.workDark.primary; // TODO: Use last focused domain
    final activeText = DomainColors.workDark.textOnPrimary;

    return Center(
      child: GestureDetector(
        onLongPressStart: (_) => _startListening(),
        onLongPressEnd: (_) => _stopListening(),
        child: AnimatedContainer(
          duration: AppAnimations.ctaExpand,
          curve: AppAnimations.easeOutQuint,
          width: isListening ? AppSpacing.ctaActiveWidth : AppSpacing.ctaIdleWidth,
          height: isListening ? AppSpacing.ctaActiveHeight : AppSpacing.ctaIdleHeight,
          decoration: BoxDecoration(
            color: isListening || isProcessing ? activeBg : idleBg,
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          ),
          child: Center(
            child: _buildContent(
              isListening,
              isProcessing,
              waveformData,
              transcription,
              idleText,
              activeText,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    bool isListening,
    bool isProcessing,
    List<double> waveformData,
    String transcription,
    Color idleText,
    Color activeText,
  ) {
    if (isProcessing) {
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

    if (isListening) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CustomPaint(
              size: const Size(200, 24),
              painter: WaveformPainter(
                amplitudes: waveformData,
                color: activeText,
              ),
            ),
            if (transcription.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                transcription,
                style: TextStyle(
                  color: activeText,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: idleText,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Hold to speak',
          style: AppTypography.ctaLabelText(color: idleText),
        ),
      ],
    );
  }

  Future<void> _startListening() async {
    try {
      HapticService.medium();

      final speechService = ref.read(speechServiceProvider);

      // Wire callbacks before starting
      speechService.onResult = (text, isFinal) {
        if (mounted) {
          ref.read(transcriptionTextProvider.notifier).state = text;
        }
      };

      speechService.onSoundLevelChange = (level) {
        if (mounted) {
          final current = List<double>.from(ref.read(waveformDataProvider));
          current.add(level);
          if (current.length > 50) {
            current.removeAt(0);
          }
          ref.read(waveformDataProvider.notifier).state = current;
        }
      };

      speechService.onError = (error) {
        if (mounted) {
          ref.read(recordingStateProvider.notifier).state = RecordingState.idle;
          ref.read(waveformDataProvider.notifier).state = [];
          ref.read(transcriptionTextProvider.notifier).state = '';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Speech error: $error')),
          );
        }
      };

      await speechService.initialize();
      await speechService.startListening();

      ref.read(recordingStateProvider.notifier).state = RecordingState.listening;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start listening: $e')),
        );
      }
    }
  }

  Future<void> _stopListening() async {
    try {
      HapticService.light();

      final speechService = ref.read(speechServiceProvider);
      await speechService.stopListening();

      final transcription = ref.read(transcriptionTextProvider);

      if (transcription.trim().isEmpty) {
        // Nothing heard — reset and show feedback
        ref.read(recordingStateProvider.notifier).state = RecordingState.idle;
        ref.read(waveformDataProvider.notifier).state = [];
        ref.read(transcriptionTextProvider.notifier).state = '';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nothing heard. Try again.')),
          );
        }
        return;
      }

      ref.read(recordingStateProvider.notifier).state = RecordingState.processing;

      // Send transcription to backend
      final apiService = ref.read(apiServiceProvider);
      final response = await apiService.processVoiceCommand(
        transcription,
        AppConstants.defaultUserId,
      );

      // Refresh tasks from backend
      await ref.read(taskStoreProvider.notifier).fetchAll();

      // Reset all state
      ref.read(recordingStateProvider.notifier).state = RecordingState.idle;
      ref.read(waveformDataProvider.notifier).state = [];
      ref.read(transcriptionTextProvider.notifier).state = '';

      if (mounted) {
        if (response.type == 'question' && response.data != null) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => QuestionBottomSheet(response: response),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.message)),
          );
        }
      }
    } catch (e) {
      ref.read(recordingStateProvider.notifier).state = RecordingState.idle;
      ref.read(waveformDataProvider.notifier).state = [];
      ref.read(transcriptionTextProvider.notifier).state = '';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process: $e')),
        );
      }
    }
  }
}
