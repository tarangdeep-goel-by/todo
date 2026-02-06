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
import '../providers/tasks_provider.dart';
import '../providers/task_filter_provider.dart';
import '../services/haptic_service.dart';

/// Show the task detail overlay as a full-screen dialog
void showTaskDetailOverlay(
  BuildContext context, {
  required Task task,
  required List<Task> allTasks,
}) {
  HapticService.medium();
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close task detail',
    barrierColor: Colors.black54,
    transitionDuration: AppAnimations.cardExpand,
    pageBuilder: (context, animation, secondaryAnimation) {
      return TaskDetailOverlay(task: task, allTasks: allTasks);
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
  final Task task;
  final List<Task> allTasks;

  const TaskDetailOverlay({
    super.key,
    required this.task,
    required this.allTasks,
  });

  @override
  ConsumerState<TaskDetailOverlay> createState() => _TaskDetailOverlayState();
}

class _TaskDetailOverlayState extends ConsumerState<TaskDetailOverlay> {
  late Task _currentTask;
  late List<Task> _allTasks;

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

  // Saving flags
  bool _savingTitle = false;
  bool _savingDescription = false;
  bool _savingPriority = false;
  bool _savingDueDate = false;
  bool _savingStatus = false;
  bool _savingSubtask = false;

  @override
  void initState() {
    super.initState();
    _currentTask = widget.task;
    _allTasks = List.from(widget.allTasks);
    _titleController = TextEditingController(text: _currentTask.title);
    _descriptionController =
        TextEditingController(text: _currentTask.description ?? '');
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

  DomainPalette get _domain =>
      DomainColors.getDomain(_currentTask.category, true);

  // --- Ancestor chain ---

  List<Task> _buildAncestorChain() {
    final ancestors = <Task>[];
    final visited = <String>{};
    String? parentId = _currentTask.parentId;

    while (parentId != null) {
      if (visited.contains(parentId)) break;
      visited.add(parentId);

      final parent = _allTasks.where((t) => t.id == parentId).firstOrNull;
      if (parent == null) break;

      ancestors.insert(0, parent); // root-first
      parentId = parent.parentId;
    }

    return ancestors;
  }

  // --- Navigation ---

  void _navigateTo(Task task) {
    HapticService.selection();
    setState(() {
      _currentTask = task;
      _editingTitle = false;
      _editingDescription = false;
      _addingSubtask = false;
      _priorityExpanded = false;
      _titleController.text = task.title;
      _descriptionController.text = task.description ?? '';
    });
  }

  // --- Field updates ---

  Future<void> _updateField({
    String? title,
    String? description,
    String? status,
    String? priority,
    DateTime? completedAt,
    DateTime? dueDate,
  }) async {
    try {
      final apiService = ref.read(apiServiceProvider);
      final updated = await apiService.updateTask(
        _currentTask.id,
        UpdateTaskRequest(
          title: title,
          description: description,
          status: status,
          priority: priority,
          completedAt: completedAt,
          dueDate: dueDate,
        ),
      );

      if (mounted) {
        setState(() {
          _currentTask = updated;
          // Update in allTasks list too
          final idx = _allTasks.indexWhere((t) => t.id == updated.id);
          if (idx != -1) _allTasks[idx] = updated;
        });
        ref.read(taskStatusOverrideProvider.notifier).state = {};
        ref.invalidate(tasksProvider);
        ref.invalidate(paginatedTasksProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
    }
  }

  // --- Title ---

  void _startEditingTitle() {
    setState(() {
      _editingTitle = true;
      _titleController.text = _currentTask.title;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _titleFocus.requestFocus();
    });
  }

  Future<void> _saveTitle() async {
    final newTitle = _titleController.text.trim();
    if (newTitle.isEmpty || newTitle == _currentTask.title) {
      setState(() => _editingTitle = false);
      return;
    }
    setState(() => _savingTitle = true);
    await _updateField(title: newTitle);
    if (mounted) setState(() { _savingTitle = false; _editingTitle = false; });
  }

  // --- Description ---

  void _startEditingDescription() {
    setState(() {
      _editingDescription = true;
      _descriptionController.text = _currentTask.description ?? '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _descriptionFocus.requestFocus();
    });
  }

  Future<void> _saveDescription() async {
    final newDesc = _descriptionController.text.trim();
    // Allow saving empty to clear description
    if (newDesc == (_currentTask.description ?? '')) {
      setState(() => _editingDescription = false);
      return;
    }
    setState(() => _savingDescription = true);
    await _updateField(description: newDesc.isEmpty ? '' : newDesc);
    if (mounted) setState(() { _savingDescription = false; _editingDescription = false; });
  }

  // --- Priority ---

  void _togglePriorityExpanded() {
    if (_savingPriority) return;
    HapticService.light();
    setState(() => _priorityExpanded = !_priorityExpanded);
  }

  Future<void> _selectPriority(String? value) async {
    final apiValue = value ?? 'none';
    if (apiValue == (_currentTask.priority ?? 'none')) {
      setState(() => _priorityExpanded = false);
      return;
    }
    setState(() {
      _savingPriority = true;
      _priorityExpanded = false;
    });
    await _updateField(priority: apiValue);
    if (mounted) setState(() => _savingPriority = false);
  }

  // --- Due date ---

  Future<void> _pickDueDate() async {
    if (_savingDueDate) return;

    final picked = await showDatePicker(
      context: context,
      initialDate: _currentTask.dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: _domain.primary,
              surface: AppColors.darkBg,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _savingDueDate = true);
      await _updateField(dueDate: picked);
      if (mounted) setState(() => _savingDueDate = false);
    }
  }

  // --- Status ---

  Future<void> _toggleStatus(String newStatus) async {
    if (_savingStatus || newStatus == _currentTask.status) return;
    HapticService.light();
    setState(() => _savingStatus = true);
    await _updateField(
      status: newStatus,
      completedAt: newStatus == 'completed' ? DateTime.now() : null,
    );
    if (mounted) setState(() => _savingStatus = false);
  }

  // --- Subtask ---

  List<Task> get _subtasks =>
      _allTasks.where((t) => t.parentId == _currentTask.id).toList();

  void _startAddingSubtask() {
    setState(() {
      _addingSubtask = true;
      _subtaskController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _subtaskFocus.requestFocus();
    });
  }

  Future<void> _saveSubtask() async {
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
        category: _currentTask.category,
        parentId: _currentTask.id,
        transcription: title,
      ));
      if (mounted) {
        setState(() {
          _allTasks.add(newTask);
          _addingSubtask = false;
          _savingSubtask = false;
          _subtaskController.clear();
        });
        ref.invalidate(tasksProvider);
        ref.invalidate(paginatedTasksProvider);
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

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final domain = _domain;
    final ancestors = _buildAncestorChain();
    final subtasks = _subtasks;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Close button row
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

            // Breadcrumb bar (always show — at minimum the category)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Category as first breadcrumb
                    Text(
                      _currentTask.category,
                      style: AppTypography.metadataText(
                        color: domain.primary.withValues(alpha: 0.7),
                      ).copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
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
                        onTap: () => _navigateTo(ancestors[i]),
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
                    _buildTitle(domain),

                    const SizedBox(height: AppSpacing.lg),

                    // Priority + Due date + Complete chips
                    _buildChipRow(domain),

                    const SizedBox(height: AppSpacing.lg),

                    // Description
                    _buildDescription(domain),

                    const SizedBox(height: AppSpacing.lg),

                    // Metadata (read-only)
                    _buildMetadata(domain),

                    const SizedBox(height: AppSpacing.lg),

                    // Subtasks
                    _buildSubtasksSection(domain, subtasks),

                    const SizedBox(height: 120),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Title widget ---

  Widget _buildTitle(DomainPalette domain) {
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
        onSubmitted: (_) => _saveTitle(),
        onTapOutside: (_) => _saveTitle(),
        enabled: !_savingTitle,
      );
    }

    return GestureDetector(
      onTap: _startEditingTitle,
      child: Text(
        _currentTask.title,
        style: AppTypography.domainTitle(context, color: domain.primary)
            .copyWith(fontSize: 28),
      ),
    );
  }

  // --- Chip row ---

  Widget _buildChipRow(DomainPalette domain) {
    final isCompleted = _currentTask.status == 'completed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            // Priority chip (tappable to expand)
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
                      _priorityIcon(_currentTask.priority),
                      size: 16,
                      color: domain.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _savingPriority
                          ? 'Saving...'
                          : _priorityLabel(_currentTask.priority),
                      style: AppTypography.metadataText(color: domain.primary)
                          .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),

            // Due date chip
            GestureDetector(
              onTap: _pickDueDate,
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
                          : _currentTask.dueDate != null
                              ? _formatDate(_currentTask.dueDate!)
                              : 'No due date',
                      style: AppTypography.metadataText(color: domain.primary)
                          .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),

            // Complete checkbox chip
            GestureDetector(
              onTap: () => _toggleStatus(isCompleted ? 'active' : 'completed'),
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

        // Priority expansion panel (inline, below chips)
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: _buildPriorityOptions(domain),
          crossFadeState: _priorityExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
          sizeCurve: AppAnimations.easeOutCubic,
        ),
      ],
    );
  }

  Widget _buildPriorityOptions(DomainPalette domain) {
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
              _buildPriorityOption(domain, value, label, icon),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityOption(
      DomainPalette domain, String? value, String label, IconData icon) {
    final currentPriority = _currentTask.priority ?? 'none';
    final isSelected = (value ?? 'none') == currentPriority;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _selectPriority(value),
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

  Widget _buildDescription(DomainPalette domain) {
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
              onPressed: _savingDescription ? null : _saveDescription,
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
      onTap: _startEditingDescription,
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
            _currentTask.description?.isNotEmpty == true
                ? _currentTask.description!
                : 'Add a description...',
            style: AppTypography.metadataText(
              color: _currentTask.description?.isNotEmpty == true
                  ? domain.primary
                  : domain.primary.withValues(alpha: 0.3),
            ).copyWith(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // --- Metadata ---

  Widget _buildMetadata(DomainPalette domain) {
    final dimColor = AppColors.darkText.withValues(alpha: 0.4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Created ${_formatDateTime(_currentTask.createdAt)}',
          style: AppTypography.metadataText(color: dimColor)
              .copyWith(fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          'Updated ${_formatDateTime(_currentTask.updatedAt)}',
          style: AppTypography.metadataText(color: dimColor)
              .copyWith(fontSize: 11),
        ),
        if (_currentTask.status == 'completed' && _currentTask.completedAt != null) ...[
          const SizedBox(height: 2),
          Text(
            'Completed ${_formatDateTime(_currentTask.completedAt!)}',
            style: AppTypography.metadataText(color: dimColor)
                .copyWith(fontSize: 11),
          ),
        ],
        if (_currentTask.estimatedHours != null) ...[
          const SizedBox(height: 2),
          Text(
            'Estimate ${_currentTask.estimatedHours!.toStringAsFixed(_currentTask.estimatedHours! % 1 == 0 ? 0 : 1)}h',
            style: AppTypography.metadataText(color: dimColor)
                .copyWith(fontSize: 11),
          ),
        ],
      ],
    );
  }

  // --- Subtasks ---

  Widget _buildSubtasksSection(DomainPalette domain, List<Task> subtasks) {
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
                    onSubmitted: (_) => _saveSubtask(),
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
                    onTap: _saveSubtask,
                    child: Icon(Icons.check, size: 20, color: domain.primary),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSubtaskRow(DomainPalette domain, Task sub) {
    final isCompleted = sub.status == 'completed';

    return GestureDetector(
      onTap: () => _navigateTo(sub),
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
