import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:todo/data/models/task.dart';
import 'package:todo/widgets/task_tree.dart';
import 'package:todo/widgets/recording_overlay.dart';
import 'package:todo/widgets/processing_dialog.dart';
import 'package:todo/widgets/agent_confirmation.dart';
import 'package:todo/providers/task_provider.dart';
import 'package:todo/providers/audio_provider.dart';
import 'package:todo/providers/ai_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:todo/config/router.dart';

/// Personal category screen with inline voice recording
class PersonalScreen extends ConsumerStatefulWidget {
  const PersonalScreen({super.key});

  @override
  ConsumerState<PersonalScreen> createState() => _PersonalScreenState();
}

class _PersonalScreenState extends ConsumerState<PersonalScreen> {
  String? _audioPath;
  Duration _recordingDuration = Duration.zero;
  Timer? _durationTimer;
  OverlayEntry? _recordingOverlay;

  @override
  void dispose() {
    _durationTimer?.cancel();
    _recordingOverlay?.remove();
    super.dispose();
  }

  Future<void> _handleLongPressStart(LongPressStartDetails details) async {
    // Check permissions
    final permissionService = ref.read(permissionServiceProvider);
    final hasPermission = await permissionService.isMicrophonePermissionGranted();

    if (!hasPermission) {
      final granted = await permissionService.requestMicrophonePermission();
      if (!granted) {
        _showPermissionError();
        return;
      }
    }

    // Start recording
    try {
      final audioService = ref.read(audioServiceProvider);
      await audioService.startRecording();
      ref.read(homeRecordingStateProvider.notifier).startRecording();
      HapticFeedback.mediumImpact();

      // Show overlay
      _showRecordingOverlay();

      // Start duration timer
      _startDurationTimer();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: $e')),
        );
      }
    }
  }

  Future<void> _handleLongPressEnd(LongPressEndDetails details) async {
    try {
      // Stop recording
      final audioService = ref.read(audioServiceProvider);
      final path = await audioService.stopRecording();

      if (path != null) {
        _audioPath = path;
      }

      ref.read(homeRecordingStateProvider.notifier).setProcessing();
      HapticFeedback.mediumImpact();

      // Hide overlay
      _hideRecordingOverlay();

      // Stop duration timer
      _stopDurationTimer();

      // Process command
      await _processCommand(path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to stop recording: $e')),
        );
      }
      ref.read(homeRecordingStateProvider.notifier).reset();
    }
  }

  void _handleLongPressCancel() {
    try {
      final audioService = ref.read(audioServiceProvider);
      audioService.cancelRecording();
      ref.read(homeRecordingStateProvider.notifier).reset();

      _hideRecordingOverlay();
      _stopDurationTimer();

      HapticFeedback.lightImpact();
    } catch (e) {
      // Silent fail for cancel
    }
  }

  void _showRecordingOverlay() {
    _recordingOverlay = OverlayEntry(
      builder: (context) => RecordingOverlay(
        duration: _recordingDuration,
        onCancel: _handleLongPressCancel,
      ),
    );
    Overlay.of(context).insert(_recordingOverlay!);
  }

  void _hideRecordingOverlay() {
    _recordingOverlay?.remove();
    _recordingOverlay = null;
  }

  void _startDurationTimer() {
    _recordingDuration = Duration.zero;
    _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) {
        setState(() {
          _recordingDuration += const Duration(milliseconds: 100);
        });
        // Update overlay
        _updateRecordingOverlay();
      }
    });
  }

  void _updateRecordingOverlay() {
    if (_recordingOverlay != null) {
      _recordingOverlay!.markNeedsBuild();
    }
  }

  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _recordingDuration = Duration.zero;
  }

  Future<void> _processCommand(String? audioPath) async {
    if (audioPath == null) {
      ref.read(homeRecordingStateProvider.notifier).reset();
      return;
    }

    // Show processing dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const ProcessingDialog(
        message: 'Processing your command...',
      ),
    );

    try {
      final agentService = ref.read(agentServiceProvider);
      final response = await agentService.processVoiceCommand(audioPath);

      // Dismiss processing dialog
      if (!mounted) return;
      Navigator.of(context).pop();

      // Show confirmation dialog
      await _showConfirmationDialog(response);
    } catch (e) {
      // Dismiss processing dialog
      if (!mounted) return;
      Navigator.of(context).pop();

      // Show error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to process command: $e')),
        );
      }
    } finally {
      ref.read(homeRecordingStateProvider.notifier).reset();
    }
  }

  Future<void> _showConfirmationDialog(response) async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: AgentConfirmation(
          response: response,
          onConfirm: () {
            Navigator.of(context).pop();

            // Invalidate cache to refresh UI
            ref.invalidate(childTasksProvider);
            ref.invalidate(tasksByCategoryProvider);

            // Show success message
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(response.message)),
              );
            }
          },
          onCancel: () {
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  void _showPermissionError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Microphone permission is required to record tasks'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Ensure root categories are seeded
    ref.watch(seedRootCategoriesProvider);

    final recordingState = ref.watch(homeRecordingStateProvider);
    final isRecording = recordingState == HomeRecordingState.recording;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Personal'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(childTasksProvider);
        },
        child: TaskTreeList(
          category: TaskCategory.personal,
          onTaskTap: (task) {
            context.push(
              AppRouter.taskDetail.replaceAll(':id', task.id),
            );
          },
          onTaskComplete: (task, completed) async {
            final repository = ref.read(taskRepositoryProvider);
            if (completed) {
              await repository.markTaskDone(task.id);
            } else {
              await repository.updateTask(
                task.id,
                status: TaskStatus.active,
              );
            }
            // Refresh the list
            ref.invalidate(childTasksProvider);
          },
        ),
      ),
      floatingActionButton: GestureDetector(
        onLongPressStart: _handleLongPressStart,
        onLongPressEnd: _handleLongPressEnd,
        onLongPressCancel: _handleLongPressCancel,
        child: FloatingActionButton(
          onPressed: null, // Disable tap
          backgroundColor: isRecording ? Colors.red : null,
          child: Icon(isRecording ? Icons.mic : Icons.mic),
        ),
      ),
    );
  }
}
