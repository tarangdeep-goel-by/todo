import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:todo/widgets/voice_recorder.dart';
import 'package:todo/widgets/ai_suggestion.dart';
import 'package:todo/providers/audio_provider.dart';
import 'package:todo/providers/ai_provider.dart';
import 'package:todo/providers/task_provider.dart';
import 'package:todo/data/models/task.dart';
import 'package:todo/data/models/ai_placement.dart';
import 'package:todo/utils/constants.dart';
import 'package:todo/services/gemini_service.dart';

/// Add task screen flow states
enum AddTaskFlowState {
  recording,
  transcribing,
  categorizing,
  reviewing,
  saving,
}

/// Add task screen
class AddTaskScreen extends ConsumerStatefulWidget {
  const AddTaskScreen({super.key});

  @override
  ConsumerState<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends ConsumerState<AddTaskScreen> {
  AddTaskFlowState _flowState = AddTaskFlowState.recording;
  String? _audioPath;
  String? _transcription;
  AICategorizationResponse? _categorization;
  TaskCategory? _selectedCategory;
  String? _selectedParentId;

  @override
  void initState() {
    super.initState();
    // Reset states
    Future.microtask(() {
      ref.read(recordingStateProvider.notifier).setIdle();
      ref.read(transcriptionStateProvider.notifier).reset();
      ref.read(categorizationStateProvider.notifier).reset();
    });
  }

  Future<void> _onRecordingComplete(String audioPath) async {
    setState(() {
      _audioPath = audioPath;
      _flowState = AddTaskFlowState.transcribing;
    });

    await _transcribeAudio(audioPath);
  }

  Future<void> _transcribeAudio(String audioPath) async {
    try {
      ref.read(transcriptionStateProvider.notifier).setLoading();

      final geminiService = ref.read(geminiServiceProvider);
      final transcription = await geminiService.transcribeAudio(audioPath);

      ref.read(transcriptionStateProvider.notifier).setTranscription(transcription);

      setState(() {
        _transcription = transcription;
        _flowState = AddTaskFlowState.categorizing;
      });

      await _categorizeTask(transcription);
    } catch (e) {
      ref.read(transcriptionStateProvider.notifier).setError(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Constants.transcriptionErrorMessage)),
        );
        context.pop();
      }
    }
  }

  Future<void> _categorizeTask(String transcription) async {
    try {
      ref.read(categorizationStateProvider.notifier).setLoading();

      final geminiService = ref.read(geminiServiceProvider);
      final taskRepository = ref.read(taskRepositoryProvider);

      // Build task tree for context
      final workTasks = await taskRepository.getTasksByCategory(TaskCategory.work);
      final personalTasks = await taskRepository.getTasksByCategory(TaskCategory.personal);

      // Group tasks by parent for tree structure
      final taskTree = <String, List<Task>>{};
      taskTree['work'] = workTasks.where((t) => t.parentId == Constants.workRootId).toList();
      taskTree['personal'] = personalTasks.where((t) => t.parentId == Constants.personalRootId).toList();

      // Add children for all tasks
      for (final task in [...workTasks, ...personalTasks]) {
        final children = [...workTasks, ...personalTasks].where((t) => t.parentId == task.id).toList();
        if (children.isNotEmpty) {
          taskTree[task.id] = children;
        }
      }

      final categorization = await geminiService.categorizeTask(
        transcription: transcription,
        taskTree: taskTree,
      );

      ref.read(categorizationStateProvider.notifier).setCategorization(categorization);

      setState(() {
        _categorization = categorization;
        _selectedCategory = TaskCategory.fromString(categorization.category);
        _selectedParentId = categorization.suggestedParent;
        _flowState = AddTaskFlowState.reviewing;
      });
    } catch (e) {
      ref.read(categorizationStateProvider.notifier).setError(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Constants.categorizationErrorMessage)),
        );
      }
      // Allow manual selection
      setState(() {
        _selectedCategory = TaskCategory.work;
        _flowState = AddTaskFlowState.reviewing;
      });
    }
  }

  Future<void> _saveTask() async {
    if (_transcription == null || _selectedCategory == null) return;

    setState(() {
      _flowState = AddTaskFlowState.saving;
    });

    try {
      final taskRepository = ref.read(taskRepositoryProvider);

      // Determine parent ID (use root if not specified)
      final parentId = _selectedParentId ??
          (_selectedCategory == TaskCategory.work
              ? Constants.workRootId
              : Constants.personalRootId);

      final aiPlacement = _categorization != null
          ? AIPlacement(
              suggestedParent: _categorization!.suggestedParent,
              confidence: _categorization!.confidence,
              reasoning: _categorization!.reasoning,
            )
          : const AIPlacement(
              confidence: 0.0,
              reasoning: 'Manual selection',
            );

      await taskRepository.createTask(
        title: _transcription!,
        category: _selectedCategory!,
        transcription: _transcription!,
        aiPlacement: aiPlacement,
        audioFileUri: _audioPath,
        parentId: parentId,
      );

      // Invalidate cache to refresh lists
      ref.invalidate(childTasksProvider);
      ref.invalidate(tasksByCategoryProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(Constants.taskCreatedMessage)),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${Constants.saveTaskErrorMessage}: $e')),
        );
      }
      setState(() {
        _flowState = AddTaskFlowState.reviewing;
      });
    }
  }

  void _showManualCategoryPicker() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose Category',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.work),
                title: const Text('Work'),
                onTap: () {
                  setState(() {
                    _selectedCategory = TaskCategory.work;
                    _selectedParentId = Constants.workRootId;
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Personal'),
                onTap: () {
                  setState(() {
                    _selectedCategory = TaskCategory.personal;
                    _selectedParentId = Constants.personalRootId;
                  });
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFlowContent() {
    switch (_flowState) {
      case AddTaskFlowState.recording:
        return VoiceRecorder(
          onRecordingComplete: () {
            // Recording complete, path is set via onRecordingPath
          },
          onRecordingPath: _onRecordingComplete,
        );

      case AddTaskFlowState.transcribing:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Transcribing audio...'),
            ],
          ),
        );

      case AddTaskFlowState.categorizing:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Analyzing with AI...'),
              const SizedBox(height: 8),
              if (_transcription != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Text(
                    '"$_transcription"',
                    style: const TextStyle(fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        );

      case AddTaskFlowState.reviewing:
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Transcription
              Text(
                'Your Task',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    _transcription ?? '',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // AI Suggestion (if available)
              if (_categorization != null)
                AISuggestion(
                  categorization: _categorization!,
                  onAccept: _saveTask,
                  onReject: _showManualCategoryPicker,
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Choose Category',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _selectedCategory = TaskCategory.work;
                                    _selectedParentId = Constants.workRootId;
                                  });
                                  _saveTask();
                                },
                                icon: const Icon(Icons.work),
                                label: const Text('Work'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _selectedCategory = TaskCategory.personal;
                                    _selectedParentId = Constants.personalRootId;
                                  });
                                  _saveTask();
                                },
                                icon: const Icon(Icons.person),
                                label: const Text('Personal'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );

      case AddTaskFlowState.saving:
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Saving task...'),
            ],
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Task'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _flowState == AddTaskFlowState.recording
              ? () => context.pop()
              : null,
        ),
      ),
      body: _buildFlowContent(),
    );
  }
}
