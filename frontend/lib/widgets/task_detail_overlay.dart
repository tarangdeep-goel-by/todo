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

  // --- More menu ---

  void _showMoreMenu(BuildContext context, Task task, DomainPalette domain) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset(button.size.width, 0), ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      color: AppColors.navBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      items: [
        PopupMenuItem(
          value: 'move',
          child: Row(
            children: [
              Icon(Icons.drive_file_move_outline, size: 18, color: AppColors.darkText),
              const SizedBox(width: 8),
              Text('Move', style: TextStyle(color: AppColors.darkText, fontSize: 14)),
            ],
          ),
        ),
        PopupMenuItem(
          value: task.isArchived ? 'restore' : 'archive',
          child: Row(
            children: [
              Icon(
                task.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
                size: 18,
                color: task.isArchived ? AppColors.completed : AppColors.deleteAction,
              ),
              const SizedBox(width: 8),
              Text(
                task.isArchived ? 'Restore' : 'Archive',
                style: TextStyle(
                  color: task.isArchived ? AppColors.completed : AppColors.deleteAction,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_forever, size: 18, color: AppColors.deleteAction),
              const SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: AppColors.deleteAction, fontSize: 14)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'move') {
        _openMoveSheet(task);
      } else if (value == 'archive') {
        _archiveFromMenu(task, domain);
      } else if (value == 'restore') {
        _restoreFromMenu(task);
      } else if (value == 'delete') {
        _deleteFromMenu(context, task);
      }
    });
  }

  Future<void> _deleteFromMenu(BuildContext context, Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navBg,
        title: Text('Delete permanently?', style: TextStyle(color: AppColors.darkText)),
        content: Text(
          'This cannot be undone.',
          style: TextStyle(color: AppColors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: AppColors.secondaryText)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete', style: TextStyle(color: AppColors.deleteAction)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    HapticService.medium();
    final nav = Navigator.of(context);
    final mutation = ref.read(taskMutationServiceProvider);
    await mutation.deleteTask(task);
    if (mounted) {
      nav.pop();
      showStyledSnackbar(context,
        message: 'Deleted: ${task.sentenceTitle}',
        style: SnackbarStyle.success,
      );
    }
  }

  Future<void> _archiveFromMenu(Task task, DomainPalette domain) async {
    HapticService.medium();
    final mutation = ref.read(taskMutationServiceProvider);
    await mutation.archiveTask(task);
    if (mounted) {
      Navigator.of(context).pop(); // close overlay
      showStyledSnackbar(context,
        message: 'Archived: ${task.sentenceTitle}',
        style: SnackbarStyle.success,
      );
    }
  }

  Future<void> _restoreFromMenu(Task task) async {
    HapticService.light();
    final mutation = ref.read(taskMutationServiceProvider);
    await mutation.restoreTask(task);
    if (mounted) {
      Navigator.of(context).pop(); // close overlay
      showStyledSnackbar(context,
        message: 'Restored: ${task.sentenceTitle}',
        style: SnackbarStyle.success,
      );
    }
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

  String _priorityLabel(String? priority) {
    if (priority == null || priority == 'none') return 'No priority';
    return priority.capitalize;
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

    final domain = DomainColors.getDomain(task.category, true, ref.watch(domainPalettesProvider));

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
              // Header row: back arrow + "Task Detail" + more icon
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.md,
                  left: AppSpacing.md,
                  right: AppSpacing.md,
                  bottom: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        HapticService.light();
                        if (_navHistory.isEmpty) {
                          Navigator.of(context).pop();
                        } else {
                          _navigateBack();
                        }
                      },
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.all(AppSpacing.xs),
                        child: Icon(
                          Icons.arrow_back_ios_new,
                          size: 18,
                          color: Color(0x80F0EBE5),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Task Detail',
                      style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.05 * 16,
                        color: AppColors.darkText,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        HapticService.light();
                        _showMoreMenu(context, task, domain);
                      },
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.all(AppSpacing.xs),
                        child: Icon(
                          Icons.more_horiz,
                          size: 18,
                          color: Color(0x80F0EBE5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Breadcrumb trail: domain > ancestor > ... > parent
              _buildBreadcrumbs(task, domain),

              const SizedBox(height: AppSpacing.md),

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

                      // Divider
                      Container(height: 1, color: const Color(0x0FF0EBE5)),

                      const SizedBox(height: AppSpacing.lg),

                      // Metadata rows (status, priority, due date, estimate)
                      _buildMetadataRows(domain, task),

                      const SizedBox(height: AppSpacing.lg),

                      // Divider
                      Container(height: 1, color: const Color(0x0FF0EBE5)),

                      const SizedBox(height: AppSpacing.lg),

                      // Description
                      _buildDescription(domain, task),

                      const SizedBox(height: AppSpacing.lg),

                      // Divider
                      Container(height: 1, color: const Color(0x0FF0EBE5)),

                      const SizedBox(height: AppSpacing.lg),

                      // Timestamps & AI metadata
                      _buildMetadata(domain, task),

                      const SizedBox(height: AppSpacing.lg),

                      // Divider
                      Container(height: 1, color: const Color(0x0FF0EBE5)),

                      const SizedBox(height: AppSpacing.lg),

                      // Subtasks
                      _buildSubtasksSection(domain, task, subtasks),

                      const SizedBox(height: 120),
                    ],
                  ),
                ),
              ),

              // Action bar (bottom)
              _buildActionBar(domain, task),
            ],
          ),
        ),
      ),
    );
  }

  // --- Breadcrumbs ---

  /// Walk parent chain to build breadcrumb trail: DOMAIN > ancestor > ... > parent
  List<Task> _getAncestorChain(Task task) {
    final ancestors = <Task>[];
    final seen = <String>{task.id};
    var currentId = task.parentId;
    while (currentId != null) {
      if (seen.contains(currentId)) break; // cycle guard
      seen.add(currentId);
      final parent = ref.read(taskByIdProvider(currentId));
      if (parent == null) break;
      ancestors.add(parent);
      currentId = parent.parentId;
    }
    return ancestors.reversed.toList(); // root-first order
  }

  Widget _buildBreadcrumbs(Task task, DomainPalette domain) {
    final ancestors = _getAncestorChain(task);
    final chevronStyle = GoogleFonts.dmSans(
      fontSize: 11,
      color: domain.primary.withValues(alpha: 0.4),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          // Accent bar
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: domain.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          // Scrollable breadcrumb trail
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Domain root
                  GestureDetector(
                    onTap: () => _navigateToDomainRoot(task.category),
                    child: Text(
                      task.category.toUpperCase(),
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.03 * 12,
                        color: domain.primary,
                      ),
                    ),
                  ),
                  // Ancestor crumbs
                  for (final ancestor in ancestors) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text('›', style: chevronStyle),
                    ),
                    GestureDetector(
                      onTap: () => _navigateTo(ancestor.id),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: Text(
                          ancestor.title,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: domain.primary.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
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
      letterSpacing: -0.02 * 28,
      height: 34.0 / 28.0,
      color: AppColors.darkText,
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

  // --- Metadata rows ---

  Widget _buildMetadataRow({
    required String label,
    required Widget value,
    VoidCallback? onTap,
  }) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
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
    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: row,
    );
  }

  Color _statusColor(Task task) {
    if (task.isArchived) return AppColors.secondaryText;
    if (task.isOverdue) return AppColors.overdue;
    if (task.isCompleted) return AppColors.completed;
    return AppColors.priorityMedium; // active = orange
  }

  String _statusLabel(Task task) {
    if (task.isArchived) return 'Archived';
    if (task.isOverdue) return 'Overdue';
    if (task.isCompleted) return 'Completed';
    return 'Active';
  }

  Color _priorityColor(String? priority) {
    switch (priority) {
      case 'high': return AppColors.priorityHigh;
      case 'medium': return AppColors.priorityMedium;
      case 'low': return AppColors.priorityLow;
      default: return const Color(0x66F0EBE5);
    }
  }

  Widget _buildMetadataRows(DomainPalette domain, Task task) {
    final valueStyle = GoogleFonts.dmSans(
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status
        _buildMetadataRow(
          label: 'Status',
          value: Text(
            _savingStatus ? 'Saving...' : _statusLabel(task),
            style: valueStyle.copyWith(color: _statusColor(task)),
          ),
        ),
        const SizedBox(height: 14),

        // Priority (tappable to expand)
        _buildMetadataRow(
          label: 'Priority',
          value: Text(
            _savingPriority ? 'Saving...' : _priorityLabel(task.priority),
            style: valueStyle.copyWith(color: _priorityColor(task.priority)),
          ),
          onTap: _togglePriorityExpanded,
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

        // Due date
        _buildMetadataRow(
          label: 'Due date',
          value: Text(
            _savingDueDate
                ? 'Saving...'
                : (task.dueDate != null ? _formatDate(task.dueDate!) : 'Not set'),
            style: valueStyle.copyWith(
              color: task.dueDate != null
                  ? (task.isOverdue ? AppColors.overdue : domain.primary)
                  : const Color(0x80F0EBE5),
            ),
          ),
          onTap: () => _pickDueDate(task),
        ),
        const SizedBox(height: 14),

        // Estimate
        _buildMetadataRow(
          label: 'Estimate',
          value: Text(
            _savingEstimate
                ? 'Saving...'
                : (task.estimatedHours != null
                    ? '${task.estimatedHours!.toStringAsFixed(task.estimatedHours! % 1 == 0 ? 0 : 1)}h'
                    : 'Not set'),
            style: valueStyle.copyWith(
              color: task.estimatedHours != null
                  ? domain.primary
                  : const Color(0x80F0EBE5),
            ),
          ),
          onTap: () => _pickEstimate(task),
        ),
        const SizedBox(height: 14),

        // Move
        _buildMetadataRow(
          label: 'Parent',
          value: Text(
            _savingMove ? 'Moving...' : 'Change parent',
            style: valueStyle.copyWith(color: domain.primary),
          ),
          onTap: () => _openMoveSheet(task),
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
        color: AppColors.secondaryText,
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
                  : domain.primary.withValues(alpha: 0.5),
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

  // --- Action bar (bottom) ---

  Widget _buildActionBar(DomainPalette domain, Task task) {
    final isCompleted = task.isCompleted;
    return Container(
      color: AppColors.darkBg,
      padding: const EdgeInsets.only(
        left: 24, right: 24, top: 16, bottom: 32,
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _savingStatus
                  ? null
                  : () => _toggleStatus(task, isCompleted ? 'active' : 'completed'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
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
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0x0AF0EBE5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: Color(0x66F0EBE5),
                    ),
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
              color: domain.primary.withValues(alpha: 0.6),
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
                  color: domain.primary.withValues(alpha: 0.5),
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
    final completedCount = subtasks.where((s) => s.isCompleted).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'SUBTASKS',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.05 * 12,
                    color: const Color(0x80F0EBE5),
                  ),
                ),
                if (subtasks.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '$completedCount / ${subtasks.length}',
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: const Color(0x40F0EBE5),
                    ),
                  ),
                ],
              ],
            ),
            if (!_addingSubtask)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    button: true,
                    label: 'Add subtask with voice',
                    child: GestureDetector(
                      onTap: () => _launchRambleSubtasks(task),
                      child: Icon(Icons.mic_none_rounded, size: 20, color: domain.primary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Semantics(
                    button: true,
                    label: 'Add subtask with text',
                    child: GestureDetector(
                      onTap: _startAddingSubtask,
                      child: Icon(Icons.add, size: 20, color: domain.primary),
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        if (subtasks.isEmpty && !_addingSubtask)
          Text(
            'No subtasks',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: const Color(0x40F0EBE5),
            ),
          ),

        // Subtask rows with custom checkboxes
        ...subtasks.map((sub) => _buildSubtaskRow(domain, sub)),

        // Inline add subtask
        if (_addingSubtask)
          _buildSubtaskInputRow(domain, task),
      ],
    );
  }

  Widget _buildSubtaskRow(DomainPalette domain, Task sub) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _navigateTo(sub.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: domain.primary.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              // Accent bar on LEFT
              Container(
                width: 3,
                height: 24,
                decoration: BoxDecoration(
                  color: domain.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              // Title
              Expanded(
                child: Text(
                  sub.sentenceTitle,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: sub.isCompleted
                        ? const Color(0x40F0EBE5)
                        : AppColors.darkText,
                    decoration: sub.isCompleted ? TextDecoration.lineThrough : null,
                    decorationColor: const Color(0x40F0EBE5),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Checkbox on RIGHT — domain accent color
              GestureDetector(
                onTap: () => _toggleStatus(sub, sub.isCompleted ? 'active' : 'completed'),
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: sub.isCompleted
                        ? domain.primary.withValues(alpha: 0.3)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: sub.isCompleted
                        ? null
                        : Border.all(
                            color: domain.primary.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                  ),
                  child: sub.isCompleted
                      ? Icon(Icons.check, size: 13, color: domain.primary)
                      : null,
                ),
              ),
              const SizedBox(width: 4),
              // Chevron after checkbox
              Icon(
                Icons.chevron_right,
                size: 16,
                color: domain.primary.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

}
