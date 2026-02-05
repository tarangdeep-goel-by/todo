import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../providers/recording_provider.dart';
import '../providers/api_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/task_filter_provider.dart';
import '../services/haptic_service.dart';
import 'waveform_painter.dart';

/// Push-to-talk CTA button with recording functionality
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

    final isRecording = recordingState == RecordingState.recording;
    final isProcessing = recordingState == RecordingState.processing;

    // Button colors (dark mode only)
    final idleBg = AppColors.darkText;
    final idleText = AppColors.darkBg;
    final activeBg = DomainColors.workDark.primary; // TODO: Use last focused domain
    final activeText = DomainColors.workDark.textOnPrimary;

    return Center(
      child: GestureDetector(
        onLongPressStart: (_) => _startRecording(),
        onLongPressEnd: (_) => _stopRecording(),
        child: AnimatedContainer(
          duration: AppAnimations.ctaExpand,
          curve: AppAnimations.easeOutQuint,
          width: isRecording ? AppSpacing.ctaActiveWidth : AppSpacing.ctaIdleWidth,
          height: isRecording ? AppSpacing.ctaActiveHeight : AppSpacing.ctaIdleHeight,
          decoration: BoxDecoration(
            color: isRecording || isProcessing ? activeBg : idleBg,
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          ),
          child: Center(
            child: _buildContent(
              isRecording,
              isProcessing,
              waveformData,
              idleText,
              activeText,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    bool isRecording,
    bool isProcessing,
    List<double> waveformData,
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

    if (isRecording) {
      return CustomPaint(
        size: const Size(200, 40),
        painter: WaveformPainter(
          amplitudes: waveformData,
          color: activeText,
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

  Future<void> _startRecording() async {
    try {
      HapticService.medium();

      final audioService = ref.read(audioServiceProvider);
      final path = await audioService.startRecording();

      ref.read(recordingStateProvider.notifier).state = RecordingState.recording;
      ref.read(recordingPathProvider.notifier).state = path;

      // Poll waveform data while recording
      _pollWaveformData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      HapticService.light();

      final audioService = ref.read(audioServiceProvider);
      final path = await audioService.stopRecording();

      if (path == null) {
        throw Exception('Recording failed');
      }

      ref.read(recordingStateProvider.notifier).state = RecordingState.processing;

      // Upload to backend
      final apiService = ref.read(apiServiceProvider);
      final response = await apiService.processVoiceCommand(
        path,
        AppConstants.defaultUserId,
      );

      // Refresh tasks — clear overrides so fresh data is authoritative
      ref.read(taskStatusOverrideProvider.notifier).state = {};
      ref.invalidate(tasksProvider);

      // Reset state
      ref.read(recordingStateProvider.notifier).state = RecordingState.idle;
      ref.read(recordingPathProvider.notifier).state = null;
      ref.read(waveformDataProvider.notifier).state = [];

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response.message)),
        );
      }
    } catch (e) {
      ref.read(recordingStateProvider.notifier).state = RecordingState.idle;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process recording: $e')),
        );
      }
    }
  }

  void _pollWaveformData() {
    if (ref.read(recordingStateProvider) != RecordingState.recording) {
      return;
    }

    final audioService = ref.read(audioServiceProvider);
    final data = audioService.waveformData;

    ref.read(waveformDataProvider.notifier).state = data;

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _pollWaveformData();
      }
    });
  }
}
