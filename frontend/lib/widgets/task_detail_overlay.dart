import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../models/task.dart';
import '../providers/mutation_provider.dart';
import '../providers/task_store_provider.dart';
import '../services/haptic_service.dart';
import 'domain_root_view.dart';
import 'task_parent_picker.dart';
import 'styled_snackbar.dart';
import 'undo_snackbar.dart';
import '../screens/ramble_screen.dart';
import '../utils/string_extensions.dart';

/// Sentinel for "field not provided" in _updateField
const _noChange = Object();

/// Shows estimate picker dialog. Returns:
/// - a positive double (new estimate)
/// - -1.0 (clear estimate)
/// - null (cancelled)
Future<double?> showEstimateDialog(
  BuildContext context, {
  required DomainPalette domain,
  required double? currentEstimate,
}) async {
  final controller = TextEditingController(
    text: currentEstimate != null
        ? currentEstimate.toStringAsFixed(currentEstimate % 1 == 0 ? 0 : 1)
        : '',
  );

  final result = await showDialog<double?>(
    context: context,
    builder: (ctx) => Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.dark(
          primary: domain.primary,
          surface: AppColors.darkBg,
        ),
      ),
      child: AlertDialog(
        backgroundColor: AppColors.darkBg,
        title: Text(
          'Estimate (hours)',
          style: AppTypography.metadataText(color: domain.primary)
              .copyWith(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          style: AppTypography.metadataText(color: domain.primary)
              .copyWith(fontSize: 16),
          decoration: InputDecoration(
            hintText: 'e.g. 2.5',
            hintStyle: AppTypography.metadataText(
              color: domain.primary.withValues(alpha: 0.3),
            ).copyWith(fontSize: 16),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: domain.primary.withValues(alpha: 0.3)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: domain.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: AppTypography.metadataText(color: AppColors.darkText)
                    .copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          if (currentEstimate != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, -1.0),
              child: Text('Clear',
                  style: AppTypography.metadataText(color: domain.primary)
                      .copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          TextButton(
            onPressed: () {
              final value = double.tryParse(controller.text);
              if (value != null && value > 0) Navigator.pop(ctx, value);
            },
            child: Text('Save',
                style: AppTypography.metadataText(color: domain.primary)
                    .copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    ),
  );

  // Don't dispose controller here — dialog dismiss animation may still
  // reference it. Let GC handle cleanup of this local controller.
  return result;
}

/// Show the task detail overlay as a full-screen dialog
void showTaskDetailOverlay(
  BuildContext context, {
  required String taskId,
  String? domainRoot,
}) {
  HapticService.medium();
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close task detail',
    barrierColor: Colors.black54,
    transitionDuration: AppAnimations.cardExpand,
    pageBuilder: (context, animation, secondaryAnimation) {
      return TaskDetailOverlay(taskId: taskId, domainRoot: domainRoot);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.15),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: AppAnimations.easeOutCubic,
      ));
      return SlideTransition(
        position: slide,
        child: FadeTransition(opacity: animation, child: child),
      );
    },
  );
}

/// Full-screen overlay for task detail with inline editing
class TaskDetailOverlay extends ConsumerStatefulWidget {
  final String taskId;
  final String? domainRoot;

  const TaskDetailOverlay({
    super.key,
    required this.taskId,
    this.domainRoot,
  });

  @override
  ConsumerState<TaskDetailOverlay> createState() => _TaskDetailOverlayState();
}

class _TaskDetailOverlayState extends ConsumerState<TaskDetailOverlay> {
  late String _activeTaskId;
  String? _activeDomainRoot;

  // Editing flags
  bool _editingTitle = false;
  bool _editingDescription = false;
  bool _addingSubtask = false;

  // Controllers
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _subtaskController;

  // Focus nodes
  final _titleFocus = FocusNode();
  final _descriptionFocus = FocusNode();
  final _subtaskFocus = FocusNode();

  // Priority expansion
  bool _priorityExpanded = false;

  // AI placement expansion
  bool _aiPlacementExpanded = false;

  // Navigation history stack
  final List<({String? taskId, String? domainRoot})> _navHistory = [];

  // Saving flags
  bool _savingTitle = false;
  bool _savingDescription = false;
  bool _savingPriority = false;
  bool _savingDueDate = false;
  bool _savingStatus = false;
  bool _savingEstimate = false;
  bool _savingSubtask = false;
  bool _savingMove = false;

  @override
  void initState() {
    super.initState();
    _activeTaskId = widget.taskId;
    _activeDomainRoot = widget.domainRoot;
    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
    _subtaskController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _subtaskController.dispose();
    _titleFocus.dispose();
    _descriptionFocus.dispose();
    _subtaskFocus.dispose();
    super.dispose();
  }

  // --- Navigation ---

  void _resetEditingFlags() {
    _editingTitle = false;
    _editingDescription = false;
    _addingSubtask = false;
    _priorityExpanded = false;
    _aiPlacementExpanded = false;
  }

  void _navigateTo(String taskId) {
    HapticService.selection();
    setState(() {
      _navHistory.add((taskId: _activeTaskId, domainRoot: _activeDomainRoot));
      _activeTaskId = taskId;
      _activeDomainRoot = null;
      _resetEditingFlags();
    });
  }

  void _navigateToDomainRoot(String category) {
    HapticService.selection();
    setState(() {
      _navHistory.add((taskId: _activeTaskId, domainRoot: _activeDomainRoot));
      _activeDomainRoot = category;
    });
  }

  void _navigateBack() {
    if (_navHistory.isEmpty) return;
    HapticService.selection();
    final prev = _navHistory.removeLast();
    setState(() {
      _activeTaskId = prev.taskId ?? '';
      _activeDomainRoot = prev.domainRoot;
      _resetEditingFlags();
    });
  }

  // --- Field updates (optimistic through store) ---

  /// Update a task field. For completedAt/dueDate/estimatedHours, pass null to
  /// clear the value, or omit the parameter to keep the old value.
  Future<void> _updateField(Task currentTask, {
    String? title,
    String? description,
    String? status,
    String? priority,
    Object? completedAt = _noChange,
    Object? dueDate = _noChange,
    Object? estimatedHours = _noChange,
  }) async {
    final store = ref.read(taskStoreProvider.notifier);

    // Build optimistic task
    final optimistic = currentTask.copyWith(
      title: title ?? currentTask.title,
      description: description ?? currentTask.description,
      status: status ?? currentTask.status,
      priority: priority ?? currentTask.priority,
      completedAt: identical(completedAt, _noChange) ? currentTask.completedAt : completedAt as DateTime?,
      dueDate: identical(dueDate, _noChange) ? currentTask.dueDate : dueDate as DateTime?,
      estimatedHours: identical(estimatedHours, _noChange) ? currentTask.estimatedHours : estimatedHours as double?,
    );
    store.upsertTask(optimistic);

    // Offline-first: enqueue update for sync
    final payload = <String, dynamic>{};
    if (title != null) payload['title'] = title;
    if (description != null) payload['description'] = description;
    if (status != null) payload['status'] = status;
    if (priority != null) payload['priority'] = priority;
    if (!identical(completedAt, _noChange)) {
      payload['completed_at'] = completedAt != null ? (completedAt as DateTime).toIso8601String() : null;
    }
    if (!identical(dueDate, _noChange)) {
      payload['due_date'] = dueDate != null ? (dueDate as DateTime).toIso8601String() : null;
    }
    if (!identical(estimatedHours, _noChange)) {
      payload['estimated_hours'] = estimatedHours;
    }

    final mutation = ref.read(taskMutationServiceProvider);
    try {
      await mutation.updateTask(optimistic, payload);
      // Show undo snackbar for field edits (skip status changes — those have their own undo)
      if (mounted && status == null) {
        final domain = DomainColors.getDomain(
          currentTask.category, true, ref.read(domainPalettesProvider),
        );
        final reversePayload = <String, dynamic>{};
        if (title != null) reversePayload['title'] = currentTask.title;
        if (description != null) reversePayload['description'] = currentTask.description ?? '';
        if (priority != null) reversePayload['priority'] = currentTask.priority ?? 'none';
        if (!identical(dueDate, _noChange)) {
          reversePayload['due_date'] = currentTask.dueDate?.toIso8601String();
        }
        if (!identical(estimatedHours, _noChange)) {
          reversePayload['estimated_hours'] = currentTask.estimatedHours;
        }
        showUndoSnackbar(
          context,
          message: 'Updated',
          domain: domain,
          onUndo: () {
            store.upsertTask(currentTask);
            mutation.updateTask(currentTask, reversePayload);
          },
        );
      }
    } catch (e) {
      store.upsertTask(currentTask);
      if (mounted) {
        showStyledSnackbar(context,
          message: 'Couldn\'t save changes. Try again.',
          style: SnackbarStyle.error,
        );
      }
    }
  }

  // --- Title ---

  void _startEditingTitle(Task task) {
    setState(() {
      _editingTitle = true;
      _titleController.text = task.sentenceTitle;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _titleFocus.requestFocus();
    });
  }

  Future<void> _saveTitle(Task task) async {
    final newTitle = _titleController.text.trim();
    if (newTitle.isEmpty || newTitle.toLowerCase() == task.title) {
      setState(() => _editingTitle = false);
      return;
    }
    setState(() => _savingTitle = true);
    await _updateField(task, title: newTitle);
    if (mounted) setState(() { _savingTitle = false; _editingTitle = false; });
  }

  // --- Description ---

  void _startEditingDescription(Task task) {
    setState(() {
      _editingDescription = true;
      _descriptionController.text = task.description ?? '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _descriptionFocus.requestFocus();
    });
  }

  Future<void> _saveDescription(Task task) async {
    final newDesc = _descriptionController.text.trim();
    if (newDesc == (task.description ?? '')) {
      setState(() => _editingDescription = false);
      return;
    }
    setState(() => _savingDescription = true);
    await _updateField(task, description: newDesc.isEmpty ? '' : newDesc);
    if (mounted) setState(() { _savingDescription = false; _editingDescription = false; });
  }

  // --- Priority ---

  void _togglePriorityExpanded() {
    if (_savingPriority) return;
    HapticService.light();
    setState(() => _priorityExpanded = !_priorityExpanded);
  }

  Future<void> _selectPriority(Task task, String? value) async {
    final apiValue = value ?? 'none';
    if (apiValue == (task.priority ?? 'none')) {
      setState(() => _priorityExpanded = false);
      return;
    }
    setState(() {
      _savingPriority = true;
      _priorityExpanded = false;
    });
    await _updateField(task, priority: apiValue);
    if (mounted) setState(() => _savingPriority = false);
  }

  // --- Due date ---

  Future<void> _pickDueDate(Task task) async {
    if (_savingDueDate) return;

    final domain = DomainColors.getDomain(task.category, true, ref.read(domainPalettesProvider));
    final now = DateTime.now();
    final firstDate = now.subtract(const Duration(days: 365));
    final lastDate = now.add(const Duration(days: 365 * 3));
    final initialDate = task.dueDate != null && task.dueDate!.isBefore(firstDate)
        ? firstDate
        : (task.dueDate ?? now);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
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

    if (picked != null) {
      setState(() => _savingDueDate = true);
      await _updateField(task, dueDate: picked);
      if (mounted) setState(() => _savingDueDate = false);
    }
  }

  // --- Estimate ---

  Future<void> _pickEstimate(Task task) async {
    if (_savingEstimate) return;
    final domain = DomainColors.getDomain(task.category, true, ref.read(domainPalettesProvider));
    final result = await showEstimateDialog(context, domain: domain, currentEstimate: task.estimatedHours);
    if (result != null) {
      setState(() => _savingEstimate = true);
      await _updateField(task, estimatedHours: result < 0 ? null : result);
      if (mounted) setState(() => _savingEstimate = false);
    }
  }

  // --- Status ---

  Future<void> _toggleStatus(Task task, String newStatus) async {
    if (_savingStatus || newStatus == task.status) return;
    HapticService.light();
    setState(() => _savingStatus = true);

    final store = ref.read(taskStoreProvider.notifier);

    if (newStatus == 'completed') {
      // Offline-first: complete task + descendants in store, enqueue for sync
      final mutation = ref.read(taskMutationServiceProvider);
      await mutation.completeTask(task);
    } else {
      // Undo: use existing PATCH flow + activate ancestor chain
      await _updateField(task, status: newStatus, completedAt: null);
      store.activateAncestorChain(task.id);
    }

    if (mounted) setState(() => _savingStatus = false);
  }

  // --- Ramble subtasks ---

  void _launchRambleSubtasks(Task task) {
    HapticService.medium();
    Navigator.of(context).pop(); // close overlay
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RambleScreen(
          prefilledParentId: task.id,
          prefilledParentTitle: task.sentenceTitle,
          prefilledCategory: task.category,
        ),
      ),
    );
  }

  // --- Move ---

  void _openMoveSheet(Task task) {
    if (_savingMove) return;
    HapticService.medium();
    showModalBottomSheet<ParentPickerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: AppColors.darkBg,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusLg),
          ),
        ),
        child: TaskParentPicker(
          currentParentId: task.parentId,
          excludeTaskId: task.id,
          onBack: () => Navigator.of(context).pop(),
          onSelect: (result) {
            Navigator.of(context).pop(result);
          },
        ),
      ),
    ).then((result) {
      if (result != null) _moveTask(task, result);
    });
  }

  Future<void> _moveTask(Task task, ParentPickerResult result) async {
    // Skip if target is same as current parent
    if (result.taskId == task.parentId && result.category == task.category) return;

    setState(() => _savingMove = true);
    final store = ref.read(taskStoreProvider.notifier);

    // Optimistic update
    final optimistic = task.copyWith(
      parentId: result.taskId ?? '',
      category: result.category,
    );
    store.upsertTask(optimistic);

    // Offline-first: enqueue move for sync
    final payload = <String, dynamic>{};
    if (result.taskId != null) {
      payload['parent_id'] = result.taskId;
    } else {
      payload['parent_id'] = null;
    }
    if (result.category != task.category) {
      payload['category'] = result.category;
    }

    final mutation = ref.read(taskMutationServiceProvider);
    try {
      await mutation.updateTask(optimistic, payload);
      if (mounted) {
        final target = result.taskTitle?.capitalize ?? 'top level';
        showStyledSnackbar(context,
          message: 'Moved to $target',
          style: SnackbarStyle.success,
        );
      }
    } catch (e) {
      store.upsertTask(task);
      if (mounted) {
        showStyledSnackbar(context,
          message: 'Couldn\'t move task. Try again.',
          style: SnackbarStyle.error,
        );
      }
    }
    if (mounted) setState(() => _savingMove = false);
  }

  // --- Subtask ---

  void _startAddingSubtask() {
    setState(() {
      _addingSubtask = true;
      _subtaskController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _subtaskFocus.requestFocus();
    });
  }

  Future<void> _saveSubtask(Task parentTask) async {
    final title = _subtaskController.text.trim();
    if (title.isEmpty) {
      setState(() => _addingSubtask = false);
      return;
    }
    setState(() => _savingSubtask = true);
    // Offline-first: create with client UUID, enqueue for sync
    final now = DateTime.now();
    final optimistic = Task(
      id: const Uuid().v4(),
      userId: parentTask.userId,
      title: title,
      category: parentTask.category,
      parentId: parentTask.id,
      status: 'active',
      createdAt: now,
      updatedAt: now,
      transcription: title,
    );
    final payload = {
      'title': title,
      'category': parentTask.category,
      'parent_id': parentTask.id,
      'transcription': title,
    };

    try {
      final mutation = ref.read(taskMutationServiceProvider);
      await mutation.createTask(optimistic, payload);
      final store = ref.read(taskStoreProvider.notifier);
      store.activateAncestorChain(optimistic.id);
      if (mounted) {
        setState(() {
          _addingSubtask = false;
          _savingSubtask = false;
          _subtaskController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _savingSubtask = false);
        showStyledSnackbar(context,
          message: 'Couldn\'t add subtask. Try again.',
          style: SnackbarStyle.error,
        );
      }
    }
  }

  // --- Helpers ---

  String _formatDate(DateTime dt) => DateFormat('MMM d, yyyy').format(dt);
  String _formatDateTime(DateTime dt) =>
      DateFormat('MMM d, yyyy h:mm a').format(dt);

  // --- AI placement helpers ---

  bool _hasAiPlacement(Task task) {
    final json = task.aiPlacementJson;
    if (json == null) return false;
    final reasoning = json['reasoning'] as String? ?? '';
    return reasoning.isNotEmpty && reasoning != 'Manual creation';
  }

  double _getAiConfidence(Task task) {
    final json = task.aiPlacementJson;
    if (json == null) return 1.0;
    final raw = json['confidence'];
    if (raw is num) return raw.toDouble();
    return 1.0;
  }

  Color _confidenceColor(double confidence) {
    if (confidence >= 0.8) return AppColors.completed;
    if (confidence >= 0.6) return AppColors.dueSoon;
    return AppColors.deleteAction;
  }

  String _getAiReasoning(Task task) {
    final json = task.aiPlacementJson;
    if (json == null) return '';
    return json['reasoning'] as String? ?? '';
  }

  bool _hasVoiceTranscription(Task task) {
    final transcription = task.transcription.trim();
    if (transcription.isEmpty) return false;
    return transcription.toLowerCase() != task.title.toLowerCase();
  }

  // --- Ancestor chain ---

  List<Task> _buildAncestorChain(Task currentTask, List<Task> allTasks) {
    final ancestors = <Task>[];
    final visited = <String>{};
    String? parentId = currentTask.parentId;

    while (parentId != null) {
      if (visited.contains(parentId)) break;
      visited.add(parentId);

      final parent = allTasks.where((t) => t.id == parentId).firstOrNull;
      if (parent == null) break;

      ancestors.insert(0, parent); // root-first
      parentId = parent.parentId;
    }

    return ancestors;
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    // Domain root mode — show L1 tasks for the domain
    if (_activeDomainRoot != null) {
      return DomainRootView(
        category: _activeDomainRoot!,
        canPop: _navHistory.isEmpty,
        onNavigateBack: _navigateBack,
        onTaskTap: _navigateTo,
        onClose: () => Navigator.of(context).pop(),
      );
    }

    final task = ref.watch(taskByIdProvider(_activeTaskId));
    final subtasks = ref.watch(childTasksProvider(_activeTaskId));
    final allTasks = ref.watch(allTasksProvider);

    if (task == null) {
      return Scaffold(
        backgroundColor: AppColors.darkBg,
        body: SafeArea(
          child: Center(
            child: Text(
              'Task not found',
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: AppColors.darkText,
              ),
            ),
          ),
        ),
      );
    }

    final domain = DomainColors.getDomain(task.category, true, ref.watch(domainPalettesProvider));
    final isCompleted = task.isCompleted;

    return PopScope(
      canPop: _navHistory.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _navigateBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.darkBg,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header bar: back arrow + "Task Detail" + more icon
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, color: Color(0x80F0EBE5), size: 20),
                      tooltip: _navHistory.isEmpty ? 'Close' : 'Back',
                      onPressed: _navHistory.isEmpty
                          ? () => Navigator.of(context).pop()
                          : _navigateBack,
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          'Task Detail',
                          style: GoogleFonts.dmSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: AppColors.darkText,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_horiz, color: Color(0x80F0EBE5), size: 20),
                      tooltip: 'More',
                      onPressed: () => _showMoreMenu(context, task, domain),
                    ),
                  ],
                ),
              ),

              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),

                      // Domain section: accent bar + uppercase name
                      GestureDetector(
                        onTap: () => _navigateToDomainRoot(task.category),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 18,
                              decoration: BoxDecoration(
                                color: domain.primary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              task.category.toUpperCase(),
                              style: GoogleFonts.dmSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: domain.primary,
                                letterSpacing: 0.36,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Title
                      _buildTitle(domain, task),

                      const SizedBox(height: 24),

                      // Metadata rows
                      _buildMetadataRows(domain, task, allTasks),

                      const SizedBox(height: 24),

                      // Description
                      _buildDescription(domain, task),

                      const SizedBox(height: 24),

                      // Divider
                      Container(height: 1, color: const Color(0x0FF0EBE5)),

                      const SizedBox(height: 24),

                      // Subtasks
                      _buildSubtasksSection(domain, task, subtasks),

                      const SizedBox(height: 24),

                      // Secondary metadata (timestamps, AI, transcription)
                      _buildSecondaryMetadata(domain, task),

                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),

              // Action bar
              _buildActionBar(domain, task, isCompleted),
            ],
          ),
        ),
      ),
    );
  }

  // --- More menu (move, delete, etc.) ---

  void _showMoreMenu(BuildContext context, Task task, DomainPalette domain) {
    HapticService.light();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.drive_file_move_outline, color: const Color(0x66F0EBE5)),
              title: Text(
                _savingMove ? 'Moving...' : 'Move',
                style: GoogleFonts.dmSans(fontSize: 14, color: const Color(0x99F0EBE5)),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _openMoveSheet(task);
              },
            ),
            ListTile(
              leading: Icon(Icons.mic_none_rounded, color: const Color(0x66F0EBE5)),
              title: Text(
                'Add subtasks with voice',
                style: GoogleFonts.dmSans(fontSize: 14, color: const Color(0x99F0EBE5)),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _launchRambleSubtasks(task);
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- Action bar ---

  Widget _buildActionBar(DomainPalette domain, Task task, bool isCompleted) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _savingStatus
                  ? null
                  : () => _toggleStatus(task, isCompleted ? 'active' : 'completed'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0x1550E890),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isCompleted ? Icons.undo : Icons.check,
                      size: 18,
                      color: const Color(0xFF50E890),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _savingStatus
                          ? 'Saving...'
                          : (isCompleted ? 'Reactivate' : 'Complete'),
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF50E890),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => _startEditingTitle(task),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0x0AF0EBE5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.edit_outlined, size: 18, color: Color(0x66F0EBE5)),
                    const SizedBox(width: 8),
                    Text(
                      'Edit',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0x66F0EBE5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Title widget ---

  Widget _buildTitle(DomainPalette domain, Task task) {
    final titleStyle = GoogleFonts.bricolageGrotesque(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      color: AppColors.darkText,
      letterSpacing: -0.56,
      height: 1.21,
    );

    if (_editingTitle) {
      return TextField(
        controller: _titleController,
        focusNode: _titleFocus,
        style: titleStyle,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: 'Task title',
          hintStyle: titleStyle.copyWith(
            color: AppColors.darkText.withValues(alpha: 0.3),
          ),
        ),
        onSubmitted: (_) => _saveTitle(task),
        onTapOutside: (_) => _saveTitle(task),
        enabled: !_savingTitle,
      );
    }

    return Semantics(
      button: true,
      label: 'Edit title',
      child: GestureDetector(
        onTap: () => _startEditingTitle(task),
        child: Text(
          task.sentenceTitle,
          style: titleStyle,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  // --- Metadata rows (status, priority, due, parent, estimate) ---

  Widget _buildMetadataRow(String label, Widget value) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: const Color(0x40F0EBE5),
            ),
          ),
        ),
        Expanded(child: value),
      ],
    );
  }

  Widget _buildMetadataRows(DomainPalette domain, Task task, List<Task> allTasks) {
    final valueStyle = GoogleFonts.dmSans(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: const Color(0x66F0EBE5),
    );
    final ancestors = _buildAncestorChain(task, allTasks);

    // Status
    final displayStatus = task.isOverdue ? 'overdue' : task.status;
    Color statusColor;
    String statusLabel;
    switch (displayStatus) {
      case 'completed':
        statusColor = const Color(0xFF50E890);
        statusLabel = 'Completed';
      case 'overdue':
        statusColor = const Color(0xFFFF6B6B);
        statusLabel = 'Overdue';
      default:
        statusColor = const Color(0xFFFF9A50);
        statusLabel = 'Active';
    }

    // Priority
    Widget priorityWidget;
    final p = task.priority ?? 'none';
    switch (p) {
      case 'high':
        priorityWidget = Text('High', style: GoogleFonts.dmSans(
          fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.priorityHigh,
        ));
      case 'medium':
        priorityWidget = Text('Medium', style: GoogleFonts.dmSans(
          fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.priorityMedium,
        ));
      case 'low':
        priorityWidget = Text('Low', style: GoogleFonts.dmSans(
          fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.priorityLow,
        ));
      default:
        priorityWidget = Text('None', style: GoogleFonts.dmSans(
          fontSize: 13, fontWeight: FontWeight.w500, color: const Color(0x40F0EBE5),
        ));
    }

    return Column(
      children: [
        // Status row — bold colored text, no pill
        _buildMetadataRow('Status', Text(
          statusLabel,
          style: GoogleFonts.dmSans(
            fontSize: 13, fontWeight: FontWeight.w700, color: statusColor,
          ),
        )),
        const SizedBox(height: 14),

        // Priority row (tappable to expand) — bold colored text, no pill
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _togglePriorityExpanded,
          child: _buildMetadataRow('Priority', Row(
            children: [
              _savingPriority
                  ? Text('Saving...', style: valueStyle)
                  : priorityWidget,
            ],
          )),
        ),
        // Priority expansion panel
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: _buildPriorityOptions(domain, task),
          crossFadeState: _priorityExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
          sizeCurve: AppAnimations.easeOutCubic,
        ),
        const SizedBox(height: 14),

        // Due date row (tappable) — accent color, red if overdue
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _pickDueDate(task),
          child: _buildMetadataRow('Due', Text(
            _savingDueDate
                ? 'Saving...'
                : (task.dueDate != null ? _formatDate(task.dueDate!) : 'Not set'),
            style: valueStyle.copyWith(
              fontWeight: FontWeight.w600,
              color: task.isOverdue
                  ? AppColors.overdue
                  : task.dueDate != null
                      ? domain.primary
                      : const Color(0x40F0EBE5),
            ),
          )),
        ),

        // Parent row (if has parent)
        if (ancestors.isNotEmpty) ...[
          const SizedBox(height: 14),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _navigateTo(ancestors.last.id),
            child: _buildMetadataRow('Parent', Text(
              ancestors.last.sentenceTitle,
              style: valueStyle.copyWith(
                color: domain.primary.withValues(alpha: 0.5),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )),
          ),
        ],

        // Estimate row (if has estimate)
        if (task.estimatedHours != null) ...[
          const SizedBox(height: 14),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _pickEstimate(task),
            child: _buildMetadataRow('Estimate', Text(
              _savingEstimate
                  ? 'Saving...'
                  : '${task.estimatedHours!.toStringAsFixed(task.estimatedHours! % 1 == 0 ? 0 : 1)}h',
              style: valueStyle,
            )),
          ),
        ],
      ],
    );
  }

  Widget _buildPriorityOptions(DomainPalette domain, Task task) {
    const options = [
      ('high', 'High', Icons.keyboard_double_arrow_up),
      ('medium', 'Medium', Icons.drag_handle),
      ('low', 'Low', Icons.keyboard_double_arrow_down),
      (null, 'None', Icons.remove),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Container(
        decoration: BoxDecoration(
          color: domain.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (value, label, icon) in options)
              _buildPriorityOption(domain, task, value, label, icon),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityOption(
      DomainPalette domain, Task task, String? value, String label, IconData icon) {
    final currentPriority = task.priority ?? 'none';
    final isSelected = (value ?? 'none') == currentPriority;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _selectPriority(task, value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: domain.primary),
            const SizedBox(width: 10),
            Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: domain.primary,
              ),
            ),
            if (isSelected) ...[
              const Spacer(),
              Icon(Icons.check, size: 16, color: domain.primary),
            ],
          ],
        ),
      ),
    );
  }

  // --- Description ---

  Widget _buildDescription(DomainPalette domain, Task task) {
    final labelStyle = GoogleFonts.dmSans(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: const Color(0x40F0EBE5),
    );

    if (_editingDescription) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DESCRIPTION', style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: const Color(0x80F0EBE5),
            letterSpacing: 0.6,
          )),
          const SizedBox(height: 4),
          TextField(
            controller: _descriptionController,
            focusNode: _descriptionFocus,
            maxLines: null,
            minLines: 3,
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: const Color(0x99F0EBE5),
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'Add a description...',
              hintStyle: GoogleFonts.dmSans(
                fontSize: 14,
                color: const Color(0x30F0EBE5),
              ),
            ),
            enabled: !_savingDescription,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _savingDescription ? null : () => _saveDescription(task),
              child: Text(
                _savingDescription ? 'Saving...' : 'Done',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: domain.primary,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: () => _startEditingDescription(task),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Description', style: labelStyle),
          const SizedBox(height: 4),
          Text(
            task.description?.isNotEmpty == true
                ? task.description!
                : 'Add a description...',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: task.description?.isNotEmpty == true
                  ? const Color(0x80F0EBE5)
                  : const Color(0x30F0EBE5),
            ),
          ),
        ],
      ),
    );
  }

  // --- Secondary metadata (timestamps, AI, transcription) ---

  Widget _buildSecondaryMetadata(DomainPalette domain, Task task) {
    final dimColor = const Color(0x40F0EBE5);
    final dimStyle = GoogleFonts.dmSans(
      fontSize: 11,
      color: dimColor,
    );
    final showAi = _hasAiPlacement(task);
    final showTranscription = _hasVoiceTranscription(task);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Created ${_formatDateTime(task.createdAt)}', style: dimStyle),
        const SizedBox(height: 2),
        Text('Updated ${_formatDateTime(task.updatedAt)}', style: dimStyle),
        if (task.isCompleted && task.completedAt != null) ...[
          const SizedBox(height: 2),
          Text('Completed ${_formatDateTime(task.completedAt!)}', style: dimStyle),
        ],

        // AI placement
        if (showAi) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() => _aiPlacementExpanded = !_aiPlacementExpanded),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 13, color: dimColor),
                const SizedBox(width: 4),
                Text('AI placed', style: dimStyle),
                const SizedBox(width: 4),
                Text(
                  '${(_getAiConfidence(task) * 100).round()}%',
                  style: dimStyle.copyWith(
                    color: _confidenceColor(_getAiConfidence(task)),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_getAiConfidence(task) < 0.8) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.warning_amber_rounded, size: 13, color: AppColors.overdue),
                ],
                const SizedBox(width: 4),
                Icon(
                  _aiPlacementExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 14, color: dimColor,
                ),
              ],
            ),
          ),
          if (_aiPlacementExpanded) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 17),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_getAiReasoning(task), style: dimStyle),
                  const SizedBox(height: 2),
                  Text(
                    'Confidence: ${(_getAiConfidence(task) * 100).round()}%',
                    style: dimStyle.copyWith(
                      color: _confidenceColor(_getAiConfidence(task)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],

        // Voice transcription
        if (showTranscription) ...[
          const SizedBox(height: 6),
          Text(
            'Voice: "${task.transcription}"',
            style: dimStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  // --- Subtask input row ---

  Widget _buildSubtaskInputRow(DomainPalette domain, Task task) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          // Empty checkbox placeholder
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0x30F0EBE5), width: 1.5),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _subtaskController,
              focusNode: _subtaskFocus,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: const Color(0x99F0EBE5),
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'New subtask...',
                hintStyle: GoogleFonts.dmSans(
                  fontSize: 14,
                  color: const Color(0x30F0EBE5),
                ),
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (_) => _saveSubtask(task),
              enabled: !_savingSubtask,
            ),
          ),
          if (_savingSubtask)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF50E890),
              ),
            )
          else
            GestureDetector(
              onTap: () => _saveSubtask(task),
              child: const Icon(Icons.check, size: 20, color: Color(0xFF50E890)),
            ),
        ],
      ),
    );
  }

  // --- Subtasks ---

  Widget _buildSubtaskItem(DomainPalette domain, Task sub) {
    final isComplete = sub.isCompleted;

    final checkboxWidget = Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: isComplete ? const Color(0x3050E890) : Colors.transparent,
        border: isComplete
            ? null
            : Border.all(color: const Color(0x30F0EBE5), width: 1.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: isComplete
          ? const Icon(Icons.check, size: 12, color: Color(0xFF50E890))
          : null,
    );

    final textWidget = Text(
      sub.sentenceTitle,
      style: GoogleFonts.dmSans(
        fontSize: 14,
        color: isComplete ? const Color(0x80F0EBE5) : const Color(0x99F0EBE5),
        decoration: isComplete ? TextDecoration.lineThrough : null,
        decorationColor: const Color(0x40F0EBE5),
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );

    Widget row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _toggleStatus(sub, isComplete ? 'active' : 'completed'),
            child: checkboxWidget,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => _navigateTo(sub.id),
              child: textWidget,
            ),
          ),
        ],
      ),
    );

    if (isComplete) {
      row = Opacity(opacity: 0.5, child: row);
    }

    return row;
  }

  Widget _buildSubtasksSection(DomainPalette domain, Task task, List<Task> subtasks) {
    final completedCount = subtasks.where((s) => s.isCompleted).length;
    final totalCount = subtasks.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'SUBTASKS',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0x80F0EBE5),
                letterSpacing: 0.6,
              ),
            ),
            if (totalCount > 0) ...[
              const SizedBox(width: 8),
              Text(
                '$completedCount / $totalCount',
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  color: const Color(0x40F0EBE5),
                ),
              ),
            ],
            const Spacer(),
            if (!_addingSubtask) ...[
              Semantics(
                button: true,
                label: 'Add subtask with voice',
                child: GestureDetector(
                  onTap: () => _launchRambleSubtasks(task),
                  child: const Icon(Icons.mic_none_rounded, size: 20, color: Color(0x66F0EBE5)),
                ),
              ),
              const SizedBox(width: 12),
              Semantics(
                button: true,
                label: 'Add subtask with text',
                child: GestureDetector(
                  onTap: _startAddingSubtask,
                  child: const Icon(Icons.add, size: 20, color: Color(0x66F0EBE5)),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        if (subtasks.isEmpty && !_addingSubtask)
          Text(
            'No subtasks',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color: const Color(0x30F0EBE5),
            ),
          ),

        // Subtask rows
        ...subtasks.map((sub) => _buildSubtaskItem(domain, sub)),

        // Inline add subtask
        if (_addingSubtask)
          _buildSubtaskInputRow(domain, task),
      ],
    );
  }

}
