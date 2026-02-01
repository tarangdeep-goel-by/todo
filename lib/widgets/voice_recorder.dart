import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo/providers/audio_provider.dart';
import 'package:todo/config/theme.dart';

/// Voice recorder widget
class VoiceRecorder extends ConsumerStatefulWidget {
  final VoidCallback? onRecordingComplete;
  final ValueChanged<String>? onRecordingPath;

  const VoiceRecorder({
    super.key,
    this.onRecordingComplete,
    this.onRecordingPath,
  });

  @override
  ConsumerState<VoiceRecorder> createState() => _VoiceRecorderState();
}

class _VoiceRecorderState extends ConsumerState<VoiceRecorder>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Duration _recordingDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      final audioService = ref.read(audioServiceProvider);
      final permissionService = ref.read(permissionServiceProvider);

      // Check permission
      final hasPermission = await permissionService.isMicrophonePermissionGranted();
      if (!hasPermission) {
        final granted = await permissionService.requestMicrophonePermission();
        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Microphone permission is required to record tasks'),
              ),
            );
          }
          return;
        }
      }

      // Start recording
      await audioService.startRecording();
      ref.read(recordingStateProvider.notifier).setRecording();
      HapticFeedback.mediumImpact();

      // Update duration
      _updateDuration();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: $e')),
        );
      }
    }
  }

  void _updateDuration() async {
    while (mounted) {
      final state = ref.read(recordingStateProvider);
      if (state != RecordingState.recording) break;

      setState(() {
        _recordingDuration = _recordingDuration + const Duration(milliseconds: 100);
      });

      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _stopRecording() async {
    try {
      final audioService = ref.read(audioServiceProvider);
      final path = await audioService.stopRecording();

      if (path != null) {
        ref.read(currentRecordingPathProvider.notifier).state = path;
        widget.onRecordingPath?.call(path);
      }

      ref.read(recordingStateProvider.notifier).setIdle();
      HapticFeedback.mediumImpact();
      widget.onRecordingComplete?.call();

      setState(() {
        _recordingDuration = Duration.zero;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to stop recording: $e')),
        );
      }
    }
  }

  Future<void> _cancelRecording() async {
    try {
      final audioService = ref.read(audioServiceProvider);
      await audioService.cancelRecording();
      ref.read(recordingStateProvider.notifier).setIdle();
      HapticFeedback.lightImpact();

      setState(() {
        _recordingDuration = Duration.zero;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel recording: $e')),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recordingState = ref.watch(recordingStateProvider);
    final isRecording = recordingState == RecordingState.recording;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Recording indicator
        if (isRecording)
          Padding(
            padding: const EdgeInsets.only(bottom: 32.0),
            child: Column(
              children: [
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _formatDuration(_recordingDuration),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontFeatures: [const FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),

        // Record button (push-to-talk)
        GestureDetector(
          onLongPressStart: (_) => _startRecording(),
          onLongPressEnd: (_) => _stopRecording(),
          child: AnimatedContainer(
            duration: AppTheme.mediumAnimation,
            curve: AppTheme.defaultCurve,
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isRecording
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
              boxShadow: [
                BoxShadow(
                  color: (isRecording
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary)
                      .withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Icon(
              Icons.mic,
              size: 60,
              color: theme.colorScheme.onPrimary,
            ),
          ),
        ),

        const SizedBox(height: 32),

        // Instructions or cancel button
        if (isRecording)
          Column(
            children: [
              Text(
                'Release to stop',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _cancelRecording,
                child: const Text('Cancel'),
              ),
            ],
          )
        else
          Text(
            'Press and hold to record',
            style: theme.textTheme.bodyLarge,
          ),
      ],
    );
  }
}
