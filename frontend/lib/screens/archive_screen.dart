import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/theme.dart';
import '../models/task.dart';
import '../providers/api_provider.dart';
import '../providers/task_store_provider.dart';
import '../services/haptic_service.dart';
import '../widgets/flat_task_row.dart';
import '../widgets/styled_snackbar.dart';

class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  List<Task> _archivedTasks = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadArchivedTasks();
  }

  Future<void> _loadArchivedTasks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final apiService = ref.read(apiServiceProvider);
      final tasks = await apiService.getArchivedTasks();
      if (mounted) {
        setState(() {
          _archivedTasks = tasks;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load archived tasks.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _restoreTask(Task task, int index) async {
    HapticService.light();
    setState(() {
      _archivedTasks.removeAt(index);
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      final restoredTask = await apiService.restoreTask(task.id);
      ref.read(taskStoreProvider.notifier).upsertTask(restoredTask);
      if (mounted) {
        showStyledSnackbar(
          context,
          message: 'Restored: ${task.sentenceTitle}',
          style: SnackbarStyle.success,
        );
      }
    } catch (e) {
      // Rollback
      if (mounted) {
        setState(() {
          _archivedTasks.insert(index, task);
        });
        showStyledSnackbar(
          context,
          message: 'Could not restore task. Check your connection.',
          style: SnackbarStyle.error,
        );
      }
    }
  }

  Future<void> _permanentDeleteTask(Task task, int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navBg,
        title: Text(
          'Delete permanently?',
          style: TextStyle(color: AppColors.darkText),
        ),
        content: Text(
          'This cannot be undone.',
          style: TextStyle(color: AppColors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.secondaryText),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(color: AppColors.snackbarError.primary),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    HapticService.medium();
    setState(() {
      _archivedTasks.removeAt(index);
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.permanentDeleteTask(task.id);
      if (mounted) {
        showStyledSnackbar(
          context,
          message: 'Permanently deleted.',
          style: SnackbarStyle.success,
        );
      }
    } catch (e) {
      // Rollback
      if (mounted) {
        setState(() {
          _archivedTasks.insert(index, task);
        });
        showStyledSnackbar(
          context,
          message: 'Could not delete task. Check your connection.',
          style: SnackbarStyle.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Container(
              height: AppSpacing.topBarHeight,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticService.light();
                      Navigator.of(context).pop();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        color: AppColors.darkText,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Archive',
                    style: AppTypography.ctaLabelText(
                      color: AppColors.darkText,
                    ).copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.secondaryText,
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            _error!,
            style: TextStyle(color: AppColors.secondaryText),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_archivedTasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.archive_outlined,
              size: 48,
              color: AppColors.tertiaryText,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No archived tasks',
              style: AppTypography.ctaLabelText(
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadArchivedTasks,
            color: AppColors.darkText,
            backgroundColor: AppColors.navBg,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              itemCount: _archivedTasks.length,
              itemBuilder: (context, index) {
                final task = _archivedTasks[index];
                final paletteMap = ref.read(domainPalettesProvider);
                final domain = DomainColors.getDomain(
                    task.category, true, paletteMap);
                return Dismissible(
                  key: Key('archive-${task.id}'),
                  background: Container(
                    color: AppColors.completed,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: AppSpacing.lg),
                    child: const Icon(Icons.undo_rounded, color: AppColors.darkBg, size: 28),
                  ),
                  secondaryBackground: Container(
                    color: AppColors.deleteAction,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: AppSpacing.lg),
                    child: const Icon(Icons.delete_forever, color: AppColors.darkBg, size: 28),
                  ),
                  confirmDismiss: (direction) async {
                    if (direction == DismissDirection.startToEnd) {
                      _restoreTask(task, index);
                    } else {
                      _permanentDeleteTask(task, index);
                    }
                    return false;
                  },
                  child: FlatTaskRow(
                    task: task,
                    domain: domain,
                    showSwipeActions: false,
                  ),
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text(
            'Tasks are auto-deleted after 30 days',
            style: AppTypography.metadataText(
              color: AppColors.tertiaryText,
            ).copyWith(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

