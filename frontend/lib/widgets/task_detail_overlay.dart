import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../models/task.dart';
import '../models/api_response.dart';
import '../providers/api_provider.dart';
import '../providers/task_store_provider.dart';
import '../services/haptic_service.dart';

/// Sentinel for "field not provided" in _updateField
const _noChange = Object();

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

  void _navigateTo(String taskId) {
    HapticService.selection();
    setState(() {
      _navHistory.add((taskId: _activeTaskId, domainRoot: _activeDomainRoot));
      _activeTaskId = taskId;
      _activeDomainRoot = null;
      _editingTitle = false;
      _editingDescription = false;
      _addingSubtask = false;
      _priorityExpanded = false;
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
      _editingTitle = false;
      _editingDescription = false;
      _addingSubtask = false;
      _priorityExpanded = false;
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

    try {
      final apiService = ref.read(apiServiceProvider);

      // Build clear fields set for nullable fields being set to null
      final clearFields = <String>{};
      if (!identical(completedAt, _noChange) && completedAt == null) clearFields.add('completed_at');
      if (!identical(dueDate, _noChange) && dueDate == null) clearFields.add('due_date');
      if (!identical(estimatedHours, _noChange) && estimatedHours == null) clearFields.add('estimated_hours');

      final updated = await apiService.updateTask(
        currentTask.id,
        UpdateTaskRequest(
          title: title,
          description: description,
          status: status,
          priority: priority,
          completedAt: (!identical(completedAt, _noChange) && completedAt != null) ? completedAt as DateTime : null,
          dueDate: (!identical(dueDate, _noChange) && dueDate != null) ? dueDate as DateTime : null,
          estimatedHours: (!identical(estimatedHours, _noChange) && estimatedHours != null) ? estimatedHours as double : null,
          clearFields: clearFields,
        ),
      );
      store.upsertTask(updated);
    } catch (e) {
      // Rollback
      store.upsertTask(currentTask);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
    }
  }

  // --- Title ---

  void _startEditingTitle(Task task) {
    setState(() {
      _editingTitle = true;
      _titleController.text = task.title;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _titleFocus.requestFocus();
    });
  }

  Future<void> _saveTitle(Task task) async {
    final newTitle = _titleController.text.trim();
    if (newTitle.isEmpty || newTitle == task.title) {
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
    final picked = await showDatePicker(
      context: context,
      initialDate: task.dueDate ?? DateTime.now(),
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
    final controller = TextEditingController(
      text: task.estimatedHours != null
          ? task.estimatedHours!.toStringAsFixed(task.estimatedHours! % 1 == 0 ? 0 : 1)
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
            if (task.estimatedHours != null)
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

    controller.dispose();

    if (result != null) {
      setState(() => _savingEstimate = true);
      if (result < 0) {
        await _updateField(task, estimatedHours: null);
      } else {
        await _updateField(task, estimatedHours: result);
      }
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
      // Optimistic: complete task + all descendants in store
      store.completeWithDescendants(task.id);
      try {
        final apiService = ref.read(apiServiceProvider);
        await apiService.completeTask(task.id);
        // Refresh store to sync all descendant statuses from backend
        await store.fetchAll();
      } catch (e) {
        // Rollback via full refresh on failure
        await store.fetchAll();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to complete: $e')),
          );
        }
      }
    } else {
      // Undo: use existing PATCH flow + activate ancestor chain
      await _updateField(task, status: newStatus, completedAt: null);
      store.activateAncestorChain(task.id);
    }

    if (mounted) setState(() => _savingStatus = false);
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
    try {
      final apiService = ref.read(apiServiceProvider);
      final newTask = await apiService.createTask(CreateTaskRequest(
        userId: AppConstants.defaultUserId,
        title: title,
        category: parentTask.category,
        parentId: parentTask.id,
        transcription: title,
      ));
      final store = ref.read(taskStoreProvider.notifier);
      store.upsertTask(newTask);
      // Backend activates ancestor chain; mirror optimistically on client
      store.activateAncestorChain(newTask.id);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add subtask: $e')),
        );
      }
    }
  }

  // --- Helpers ---

  String _formatDate(DateTime dt) => DateFormat('MMM d, yyyy').format(dt);
  String _formatDateTime(DateTime dt) =>
      DateFormat('MMM d, yyyy h:mm a').format(dt);

  String _priorityLabel(String? priority) {
    if (priority == null || priority == 'none') return 'No priority';
    return '${priority[0].toUpperCase()}${priority.substring(1)}';
  }

  IconData _priorityIcon(String? priority) {
    switch (priority) {
      case 'high':
        return Icons.keyboard_double_arrow_up;
      case 'medium':
        return Icons.drag_handle;
      case 'low':
        return Icons.keyboard_double_arrow_down;
      default:
        return Icons.remove;
    }
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
      return _buildDomainRootView(context);
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
              style: AppTypography.metadataText(color: AppColors.darkText),
            ),
          ),
        ),
      );
    }

    final domain = DomainColors.getDomain(task.category, true, ref.read(domainPalettesProvider));
    final ancestors = _buildAncestorChain(task, allTasks);

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
              // Close button — always dismisses overlay entirely
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.sm,
                    right: AppSpacing.md,
                  ),
                  child: IconButton(
                    icon: Icon(Icons.close, color: domain.primary, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),

              // Breadcrumb bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Category as first breadcrumb — tappable to navigate to domain root
                      GestureDetector(
                        onTap: () => _navigateToDomainRoot(task.category),
                        child: Text(
                          task.category,
                          style: AppTypography.metadataText(
                            color: domain.primary.withValues(alpha: 0.7),
                          ).copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      // Ancestors
                      for (int i = 0; i < ancestors.length; i++) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Icon(
                            Icons.chevron_right,
                            size: 14,
                            color: domain.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _navigateTo(ancestors[i].id),
                          child: Text(
                            ancestors[i].title,
                            style: AppTypography.metadataText(
                              color: domain.primary.withValues(alpha: 0.7),
                            ).copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.sm),

              // Scrollable content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      _buildTitle(domain, task),

                      const SizedBox(height: AppSpacing.lg),

                      // Priority + Due date + Complete chips
                      _buildChipRow(domain, task),

                      const SizedBox(height: AppSpacing.lg),

                      // Description
                      _buildDescription(domain, task),

                      const SizedBox(height: AppSpacing.lg),

                      // Metadata (read-only)
                      _buildMetadata(domain, task),

                      const SizedBox(height: AppSpacing.lg),

                      // Subtasks
                      _buildSubtasksSection(domain, task, subtasks),

                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build domain root view — lists all L1 tasks (parentId == null) for the domain.
  Widget _buildDomainRootView(BuildContext context) {
    final category = _activeDomainRoot!;
    final domain = DomainColors.getDomain(category, true, ref.read(domainPalettesProvider));
    final allTasks = ref.watch(allTasksProvider);
    final l1Tasks = allTasks
        .where((t) => t.parentId == null && t.category.toLowerCase() == category.toLowerCase())
        .toList()
      ..sort((a, b) {
        // Active before completed
        final aRank = a.isCompleted ? 2 : (a.isOverdue ? 0 : 1);
        final bRank = b.isCompleted ? 2 : (b.isOverdue ? 0 : 1);
        if (aRank != bRank) return aRank.compareTo(bRank);
        return b.createdAt.compareTo(a.createdAt);
      });

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
              // Close button — always dismisses overlay entirely
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.sm,
                    right: AppSpacing.md,
                  ),
                  child: IconButton(
                    icon: Icon(Icons.close, color: domain.primary, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),

              // Domain title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Text(
                  category[0].toUpperCase() + category.substring(1),
                  style: AppTypography.domainTitle(context, color: domain.primary)
                      .copyWith(fontSize: 28),
                ),
              ),

              const SizedBox(height: AppSpacing.sm),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Text(
                  '${l1Tasks.where((t) => t.isActive).length} top-level tasks',
                  style: AppTypography.metadataText(
                    color: domain.primary.withValues(alpha: 0.6),
                  ).copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              // L1 task list
              Expanded(
                child: l1Tasks.isEmpty
                    ? Center(
                        child: Text(
                          'No tasks in this domain',
                          style: AppTypography.metadataText(
                            color: domain.primary.withValues(alpha: 0.3),
                          ).copyWith(fontSize: 14),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        itemCount: l1Tasks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 4),
                        itemBuilder: (_, i) => _buildSubtaskRow(domain, l1Tasks[i]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Title widget ---

  Widget _buildTitle(DomainPalette domain, Task task) {
    if (_editingTitle) {
      return TextField(
        controller: _titleController,
        focusNode: _titleFocus,
        style: AppTypography.domainTitle(context, color: domain.primary)
            .copyWith(fontSize: 28),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: 'Task title',
          hintStyle: AppTypography.domainTitle(context,
                  color: domain.primary.withValues(alpha: 0.3))
              .copyWith(fontSize: 28),
        ),
        onSubmitted: (_) => _saveTitle(task),
        onTapOutside: (_) => _saveTitle(task),
        enabled: !_savingTitle,
      );
    }

    return GestureDetector(
      onTap: () => _startEditingTitle(task),
      child: Text(
        task.title,
        style: AppTypography.domainTitle(context, color: domain.primary)
            .copyWith(fontSize: 28),
      ),
    );
  }

  // --- Chip row ---

  Widget _buildChipRow(DomainPalette domain, Task task) {
    final isCompleted = task.isCompleted;
    final isOverdue = task.isOverdue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            // Priority chip
            GestureDetector(
              onTap: _togglePriorityExpanded,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: domain.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _priorityIcon(task.priority),
                      size: 16,
                      color: domain.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _savingPriority
                          ? 'Saving...'
                          : _priorityLabel(task.priority),
                      style: AppTypography.metadataText(color: domain.primary)
                          .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),

            // Due date chip
            GestureDetector(
              onTap: () => _pickDueDate(task),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: domain.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today, size: 16, color: domain.primary),
                    const SizedBox(width: 6),
                    Text(
                      _savingDueDate
                          ? 'Saving...'
                          : task.dueDate != null
                              ? _formatDate(task.dueDate!)
                              : 'No due date',
                      style: AppTypography.metadataText(color: domain.primary)
                          .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),

            // Estimate chip
            GestureDetector(
              onTap: () => _pickEstimate(task),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: domain.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined, size: 16, color: domain.primary),
                    const SizedBox(width: 6),
                    Text(
                      _savingEstimate
                          ? 'Saving...'
                          : task.estimatedHours != null
                              ? '${task.estimatedHours!.toStringAsFixed(task.estimatedHours! % 1 == 0 ? 0 : 1)}h'
                              : 'No estimate',
                      style: AppTypography.metadataText(color: domain.primary)
                          .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),

            // Overdue chip (read-only indicator)
            if (isOverdue)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B6B),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: Color(0xFF0D0B09),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Overdue',
                      style: AppTypography.metadataText(
                        color: const Color(0xFF0D0B09),
                      ).copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),

            // Complete checkbox chip (toggle sends 'active', never 'overdue')
            GestureDetector(
              onTap: () => _toggleStatus(task, isCompleted ? 'active' : 'completed'),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isCompleted
                      ? domain.primary
                      : domain.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isCompleted
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 16,
                      color: isCompleted
                          ? domain.textOnPrimary
                          : domain.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _savingStatus ? 'Saving...' : 'Complete',
                      style: AppTypography.metadataText(
                        color: isCompleted
                            ? domain.textOnPrimary
                            : domain.primary,
                      ).copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
              style: AppTypography.metadataText(color: domain.primary)
                  .copyWith(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
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
    if (_editingDescription) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DESCRIPTION',
            style: AppTypography.metadataText(
              color: AppColors.darkText.withValues(alpha: 0.4),
            ).copyWith(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _descriptionController,
            focusNode: _descriptionFocus,
            maxLines: null,
            minLines: 3,
            style: AppTypography.metadataText(color: domain.primary)
                .copyWith(fontSize: 14, fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'Add a description...',
              hintStyle: AppTypography.metadataText(
                color: domain.primary.withValues(alpha: 0.3),
              ).copyWith(fontSize: 14),
            ),
            enabled: !_savingDescription,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _savingDescription ? null : () => _saveDescription(task),
              child: Text(
                _savingDescription ? 'Saving...' : 'Done',
                style: AppTypography.metadataText(color: domain.primary)
                    .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
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
          Text(
            'DESCRIPTION',
            style: AppTypography.metadataText(
              color: AppColors.darkText.withValues(alpha: 0.4),
            ).copyWith(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            task.description?.isNotEmpty == true
                ? task.description!
                : 'Add a description...',
            style: AppTypography.metadataText(
              color: task.description?.isNotEmpty == true
                  ? domain.primary
                  : domain.primary.withValues(alpha: 0.3),
            ).copyWith(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // --- Metadata ---

  Widget _buildMetadata(DomainPalette domain, Task task) {
    final dimColor = AppColors.darkText.withValues(alpha: 0.4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Created ${_formatDateTime(task.createdAt)}',
          style: AppTypography.metadataText(color: dimColor)
              .copyWith(fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          'Updated ${_formatDateTime(task.updatedAt)}',
          style: AppTypography.metadataText(color: dimColor)
              .copyWith(fontSize: 11),
        ),
        if (task.isCompleted && task.completedAt != null) ...[
          const SizedBox(height: 2),
          Text(
            'Completed ${_formatDateTime(task.completedAt!)}',
            style: AppTypography.metadataText(color: dimColor)
                .copyWith(fontSize: 11),
          ),
        ],
      ],
    );
  }

  // --- Subtasks ---

  Widget _buildSubtasksSection(DomainPalette domain, Task task, List<Task> subtasks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'SUBTASKS',
              style: AppTypography.metadataText(
                color: AppColors.darkText.withValues(alpha: 0.4),
              ).copyWith(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            if (!_addingSubtask)
              GestureDetector(
                onTap: _startAddingSubtask,
                child: Icon(Icons.add, size: 20, color: domain.primary),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        if (subtasks.isEmpty && !_addingSubtask)
          Text(
            'No subtasks',
            style: AppTypography.metadataText(
              color: domain.primary.withValues(alpha: 0.3),
            ).copyWith(fontSize: 13),
          ),

        // Subtask rows
        ...subtasks.map((sub) => _buildSubtaskRow(domain, sub)),

        // Inline add subtask
        if (_addingSubtask)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Container(
                  width: AppSpacing.leftAccentBar,
                  height: 28,
                  decoration: BoxDecoration(
                    color: domain.primary.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _subtaskController,
                    focusNode: _subtaskFocus,
                    style: AppTypography.metadataText(color: domain.primary)
                        .copyWith(fontSize: 14, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'New subtask...',
                      hintStyle: AppTypography.metadataText(
                        color: domain.primary.withValues(alpha: 0.3),
                      ).copyWith(fontSize: 14),
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (_) => _saveSubtask(task),
                    enabled: !_savingSubtask,
                  ),
                ),
                if (_savingSubtask)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: domain.primary,
                    ),
                  )
                else
                  GestureDetector(
                    onTap: () => _saveSubtask(task),
                    child: Icon(Icons.check, size: 20, color: domain.primary),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSubtaskRow(DomainPalette domain, Task sub) {
    final isCompleted = sub.isCompleted;

    return GestureDetector(
      onTap: () => _navigateTo(sub.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Opacity(
          opacity: isCompleted ? 0.5 : 1.0,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: domain.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 6,
            ),
            child: Row(
              children: [
                Container(
                  width: AppSpacing.leftAccentBar,
                  height: 20,
                  decoration: BoxDecoration(
                    color: domain.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    sub.title,
                    style: AppTypography.metadataText(color: domain.primary)
                        .copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      decoration:
                          isCompleted ? TextDecoration.lineThrough : null,
                      decorationColor: domain.primary.withValues(alpha: 0.5),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Metadata hints
                if (sub.priority != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    sub.priority!.substring(0, 1).toUpperCase(),
                    style: AppTypography.metadataText(
                      color: domain.primary.withValues(alpha: 0.6),
                    ).copyWith(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
                if (sub.dueDate != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(sub.dueDate!),
                    style: AppTypography.metadataText(
                      color: domain.primary.withValues(alpha: 0.6),
                    ).copyWith(fontSize: 11),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: domain.primary.withValues(alpha: 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
