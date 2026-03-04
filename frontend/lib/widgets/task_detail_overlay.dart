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
import 'domain_root_view.dart';
import 'task_parent_picker.dart';
import 'task_row_tile.dart';
import 'styled_snackbar.dart';
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

  controller.dispose();
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
          showStyledSnackbar(context,
            message: 'Couldn\'t complete task. Try again.',
            style: SnackbarStyle.error,
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

    try {
      final apiService = ref.read(apiServiceProvider);
      final clearFields = <String>{};
      if (result.taskId == null) clearFields.add('parent_id');

      final updated = await apiService.updateTask(
        task.id,
        UpdateTaskRequest(
          parentId: result.taskId,
          category: result.category != task.category ? result.category : null,
          clearFields: clearFields,
        ),
      );
      store.upsertTask(updated);
      if (mounted) {
        final target = result.taskTitle?.capitalize ?? 'top level';
        showStyledSnackbar(context,
          message: 'Moved to $target',
          style: SnackbarStyle.success,
        );
      }
    } catch (e) {
      // Rollback
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

  String _priorityLabel(String? priority) {
    if (priority == null || priority == 'none') return 'No priority';
    return priority.capitalize;
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
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 120),
                            child: Text(
                              ancestors[i].title,
                              style: AppTypography.metadataText(
                                color: domain.primary.withValues(alpha: 0.7),
                              ).copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
        task.sentenceTitle,
        style: AppTypography.domainTitle(context, color: domain.primary)
            .copyWith(fontSize: 28),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  // --- Chip row ---

  Widget _buildActionChip({
    required VoidCallback? onTap,
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foregroundColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTypography.metadataText(color: foregroundColor)
                .copyWith(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return GestureDetector(onTap: onTap, child: child);
  }

  Widget _buildChipRow(DomainPalette domain, Task task) {
    final isCompleted = task.isCompleted;
    final isOverdue = task.isOverdue;
    final defaultBg = domain.primary.withValues(alpha: 0.15);
    final defaultFg = domain.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _buildActionChip(
              onTap: _togglePriorityExpanded,
              icon: _priorityIcon(task.priority),
              label: _savingPriority ? 'Saving...' : _priorityLabel(task.priority),
              backgroundColor: defaultBg,
              foregroundColor: defaultFg,
            ),
            _buildActionChip(
              onTap: () => _pickDueDate(task),
              icon: Icons.calendar_today,
              label: _savingDueDate ? 'Saving...' : (task.dueDate != null ? _formatDate(task.dueDate!) : 'No due date'),
              backgroundColor: defaultBg,
              foregroundColor: defaultFg,
            ),
            _buildActionChip(
              onTap: () => _pickEstimate(task),
              icon: Icons.timer_outlined,
              label: _savingEstimate ? 'Saving...' : (task.estimatedHours != null
                  ? '${task.estimatedHours!.toStringAsFixed(task.estimatedHours! % 1 == 0 ? 0 : 1)}h'
                  : 'No estimate'),
              backgroundColor: defaultBg,
              foregroundColor: defaultFg,
            ),
            if (isOverdue)
              _buildActionChip(
                onTap: null,
                icon: Icons.warning_amber_rounded,
                label: 'Overdue',
                backgroundColor: AppColors.overdue,
                foregroundColor: AppColors.darkBg,
              ),
            _buildActionChip(
              onTap: () => _openMoveSheet(task),
              icon: Icons.drive_file_move_outline,
              label: _savingMove ? 'Moving...' : 'Move',
              backgroundColor: defaultBg,
              foregroundColor: defaultFg,
            ),
            _buildActionChip(
              onTap: () => _toggleStatus(task, isCompleted ? 'active' : 'completed'),
              icon: isCompleted ? Icons.check_box : Icons.check_box_outline_blank,
              label: _savingStatus ? 'Saving...' : 'Complete',
              backgroundColor: isCompleted ? domain.primary : defaultBg,
              foregroundColor: isCompleted ? domain.textOnPrimary : defaultFg,
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

  // --- Section header ---

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: AppTypography.metadataText(
        color: AppColors.darkText.withValues(alpha: 0.4),
      ).copyWith(fontSize: 11, fontWeight: FontWeight.w700),
    );
  }

  // --- Description ---

  Widget _buildDescription(DomainPalette domain, Task task) {
    if (_editingDescription) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('DESCRIPTION'),
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
          _buildSectionHeader('DESCRIPTION'),
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
    final dimStyle = AppTypography.metadataText(color: dimColor)
        .copyWith(fontSize: 11);
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
                  if (_getAiConfidence(task) < 0.8) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Confidence: ${(_getAiConfidence(task) * 100).round()}%',
                      style: dimStyle,
                    ),
                  ],
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
            _buildSectionHeader('SUBTASKS'),
            if (!_addingSubtask)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => _launchRambleSubtasks(task),
                    child: Icon(Icons.mic_none_rounded, size: 20, color: domain.primary),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _startAddingSubtask,
                    child: Icon(Icons.add, size: 20, color: domain.primary),
                  ),
                ],
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
        ...subtasks.map((sub) => TaskRowTile(
          domain: domain,
          task: sub,
          onTap: () => _navigateTo(sub.id),
        )),

        // Inline add subtask
        if (_addingSubtask)
          _buildSubtaskInputRow(domain, task),
      ],
    );
  }

}
