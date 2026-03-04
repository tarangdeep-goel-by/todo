import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../models/task.dart';
import '../models/api_response.dart';
import '../providers/api_provider.dart';
import '../providers/task_store_provider.dart';
import '../services/haptic_service.dart';
import '../widgets/undo_snackbar.dart';
import '../widgets/styled_snackbar.dart';
import '../widgets/glass_card_painter.dart';
import 'task_detail_overlay.dart';
import '../utils/string_extensions.dart';

/// Domain card widget with focus/compressed states
class DomainCard extends ConsumerStatefulWidget {
  final DomainPalette domain;
  final List<Task> tasks;
  final bool isDark;
  final double focusProgress; // 0.0 = compressed, 1.0 = focused
  final double height;

  const DomainCard({
    super.key,
    required this.domain,
    required this.tasks,
    required this.isDark,
    required this.focusProgress,
    required this.height,
  });

  @override
  ConsumerState<DomainCard> createState() => _DomainCardState();
}

class _DomainCardState extends ConsumerState<DomainCard>
    with SingleTickerProviderStateMixin {
  DomainPalette get domain => widget.domain;
  List<Task> get tasks => widget.tasks;
  double get height => widget.height;

  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnimation;
  late Animation<double> _glowAnimation;
  bool _wasFocused = false;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      duration: AppAnimations.shimmerSweep,
      vsync: this,
    );
    _shimmerAnimation = CurvedAnimation(
      parent: _shimmerController,
      curve: AppAnimations.easeOutQuint,
    );
    _glowAnimation = CurvedAnimation(
      parent: _shimmerController,
      curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
    );
    _wasFocused = widget.focusProgress > 0.9;
  }

  @override
  void didUpdateWidget(DomainCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isFocused = widget.focusProgress > 0.9;
    if (isFocused && !_wasFocused) {
      _shimmerController.forward(from: 0.0);
    }
    _wasFocused = isFocused;
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: ClipRect(
        child: widget.height > 120
            ? _buildFocusedCard(context)
            : _buildCompressedCard(context),
      ),
    );
  }

  Future<void> _toggleTask(Task task) async {
    // Always send 'active' (never 'overdue') — overdue is computed
    final newStatus = task.isCompleted ? 'active' : 'completed';
    final store = ref.read(taskStoreProvider.notifier);

    HapticService.light();

    // Optimistic upsert
    final optimistic = task.copyWith(
      status: newStatus,
      completedAt: newStatus == 'completed' ? DateTime.now() : null,
    );
    store.upsertTask(optimistic);

    try {
      final apiService = ref.read(apiServiceProvider);
      final updated = await apiService.updateTask(
        task.id,
        UpdateTaskRequest(
          status: newStatus,
          completedAt: newStatus == 'completed' ? DateTime.now() : null,
          clearFields: newStatus == 'active' ? const {'completed_at'} : const {},
        ),
      );
      store.upsertTask(updated);

      if (mounted) {
        final message = newStatus == 'completed'
            ? 'Completed: ${task.sentenceTitle}'
            : 'Restored: ${task.sentenceTitle}';
        showUndoSnackbar(
          context,
          message: message,
          domain: domain,
          onUndo: () => _undoToggle(task),
        );
      }
    } catch (e) {
      // Rollback
      store.upsertTask(task);
      if (mounted) {
        showStyledSnackbar(context,
          message: 'Couldn\'t update task. Check your connection.',
          style: SnackbarStyle.error,
        );
      }
    }
  }

  Future<void> _undoToggle(Task original) async {
    final store = ref.read(taskStoreProvider.notifier);
    store.upsertTask(original);

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.updateTask(
        original.id,
        UpdateTaskRequest(
          status: original.status,
          completedAt: original.isCompleted ? original.completedAt ?? DateTime.now() : null,
        ),
      );
    } catch (e) {
      if (mounted) {
        showStyledSnackbar(context,
          message: 'Couldn\'t undo. Check your connection.',
          style: SnackbarStyle.error,
        );
      }
    }
  }

  String _formatDueDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(date.year, date.month, date.day);
    final diff = due.difference(today).inDays;
    if (diff < 0) return 'Overdue';
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (date.isBefore(now.add(const Duration(hours: 48)))) return 'Due Soon';
    if (diff < 7) return '${diff}d';
    return '${date.day}/${date.month}';
  }

  Widget _buildTaskRow(Task task) {
    final isCompleted = task.isCompleted;
    final hasMeta = task.priority != null || task.dueDate != null;

    // Build metadata chips
    final metaParts = <Widget>[];
    if (task.priority != null) {
      metaParts.add(Text(
        task.priority!.capitalize,
        style: AppTypography.metadataText(
          color: domain.primary.withValues(alpha: 0.7),
        ).copyWith(fontSize: 11, fontWeight: FontWeight.w500),
      ));
    }
    if (task.priority != null && task.dueDate != null) {
      metaParts.add(Text(
        '  ·  ',
        style: AppTypography.metadataText(
          color: domain.primary.withValues(alpha: 0.4),
        ).copyWith(fontSize: 11),
      ));
    }
    if (task.dueDate != null) {
      metaParts.add(Text(
        _formatDueDate(task.dueDate!),
        style: AppTypography.metadataText(
          color: domain.primary.withValues(alpha: 0.7),
        ).copyWith(fontSize: 11, fontWeight: FontWeight.w500),
      ));
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleTask(task),
      onLongPress: () => showTaskDetailOverlay(context, taskId: task.id),
      child: Opacity(
        opacity: isCompleted ? 0.5 : 1.0,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                domain.surface.withValues(alpha: 0.85),
                domain.surface.withValues(alpha: 0.55),
              ],
            ),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(
              color: domain.primary.withValues(alpha: 0.05),
              width: 0.5,
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 6,
          ),
          child: Row(
            children: [
              // Left accent bar
              Container(
                width: AppSpacing.leftAccentBar,
                height: hasMeta ? 32 : 20,
                decoration: BoxDecoration(
                  color: domain.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      task.sentenceTitle,
                      style: AppTypography.metadataText(
                        color: domain.primary,
                      ).copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        decoration: isCompleted ? TextDecoration.lineThrough : null,
                        decorationColor: domain.primary.withValues(alpha: 0.5),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (hasMeta) ...[
                      const SizedBox(height: 2),
                      Row(children: metaParts),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTaskCount(int count) =>
      '$count ${count == 1 ? 'task' : 'tasks'}';

  /// Focused card: glass gradient bg with shimmer + glow
  Widget _buildFocusedCard(BuildContext context) {
    final taskCount = tasks.where((t) => t.isActive).length;

    // Show overdue tasks, then high priority (due soonest first)
    final now = DateTime.now();
    final weekFromNow = now.add(const Duration(days: 7));
    final displayTasks = tasks
        .where((t) =>
            t.isActive &&
            (t.isOverdue ||
                t.isDueSoon ||
                t.priority == 'high' ||
                (t.dueDate != null && !t.dueDate!.isAfter(weekFromNow))))
        .toList()
      ..sort((a, b) {
        // Overdue first, then due_soon
        if (a.isOverdue && !b.isOverdue) return -1;
        if (!a.isOverdue && b.isOverdue) return 1;
        if (a.isDueSoon && !b.isDueSoon) return -1;
        if (!a.isDueSoon && b.isDueSoon) return 1;
        // High priority before others
        final aHigh = a.priority == 'high' ? 0 : 1;
        final bHigh = b.priority == 'high' ? 0 : 1;
        if (aHigh != bHigh) return aHigh.compareTo(bHigh);
        // Then by due date (tasks with dates before those without)
        if (a.dueDate != null && b.dueDate != null) return a.dueDate!.compareTo(b.dueDate!);
        if (a.dueDate != null) return -1;
        if (b.dueDate != null) return 1;
        return 0;
      });
    final topTasks = displayTasks.take(5).toList();

    final glowColor = domain.glow ?? domain.primary.withValues(alpha: 0.2);

    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        final shimmerVal = _shimmerAnimation.value;
        final glowVal = _glowAnimation.value;

        // Glow swells during shimmer, then settles
        final glowAlpha = 0.20 + (0.15 * glowVal * (1.0 - shimmerVal));
        final glowBlur = 28.0 + (20.0 * glowVal * (1.0 - shimmerVal));

        return RepaintBoundary(
          child: Container(
            width: double.infinity,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              boxShadow: [
                // Warm color glow (playful, not metallic)
                BoxShadow(
                  color: glowColor.withValues(alpha: glowAlpha),
                  blurRadius: glowBlur,
                  spreadRadius: 2,
                ),
                // Soft depth
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.30),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRect(
              child: Stack(
                children: [
                  // Glass gradient background
                  Positioned.fill(
                    child: CustomPaint(
                      painter: GlassCardPainter(
                        primaryColor: domain.primary,
                        darkShade: domain.darkShade,
                        focusProgress: widget.focusProgress,
                      ),
                    ),
                  ),

                  // Warm color shimmer on focus change (not white/metallic)
                  if (_shimmerController.isAnimating || shimmerVal > 0)
                    Positioned.fill(
                      child: _buildShimmerOverlay(shimmerVal),
                    ),

                  // Content
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Domain name and task count row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => showTaskDetailOverlay(
                                  context,
                                  taskId: '',
                                  domainRoot: domain.name.toLowerCase(),
                                ),
                                child: Text(
                                  domain.name,
                                  style: AppTypography.domainTitle(
                                    context,
                                    color: domain.textOnPrimary,
                                  ),
                                ),
                              ),
                            ),
                            Text(
                              _formatTaskCount(taskCount),
                              style: AppTypography.metadataText(
                                color: domain.textOnPrimary.withValues(alpha: 0.8),
                              ).copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: AppSpacing.md),

                        // Dark inset task preview or empty state
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            clipBehavior: Clip.hardEdge,
                            decoration: BoxDecoration(
                              color: AppColors.cardInset,
                              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                              border: Border.all(
                                color: domain.primary.withValues(alpha: 0.08),
                                width: 0.5,
                              ),
                            ),
                            child: topTasks.isEmpty
                                ? _buildEmptyState()
                                : ListView.separated(
                                    padding: const EdgeInsets.all(AppSpacing.sm),
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: topTasks.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 4),
                                    itemBuilder: (_, i) =>
                                        _buildTaskRow(topTasks[i]),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Warm color sweep on focus change — uses domain primary, not white
  Widget _buildShimmerOverlay(double progress) {
    final translateX = -1.0 + (2.0 * progress);
    return Transform.translate(
      offset: Offset(translateX * 200, 0),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              domain.primary.withValues(alpha: 0.0),
              domain.primary.withValues(alpha: 0.10),
              domain.primary.withValues(alpha: 0.20),
              domain.primary.withValues(alpha: 0.10),
              domain.primary.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
          ),
        ),
      ),
    );
  }

  /// Zen empty state with ambient bloom orbs, constellation dots,
  /// horizon arcs, and "All clear" text
  Widget _buildEmptyState() {
    final rng = math.Random(domain.name.hashCode);

    // OLED-inspired: tiny vivid color particles against deep black
    // Like 4K OLED demo reels — pure saturated specks in darkness
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // Micro bloom spots — small, vivid, scattered
        ...List.generate(6, (i) {
          final x = rng.nextDouble() * 0.8 + 0.1;
          final y = rng.nextDouble() * 0.7 + 0.1;
          final useDark = i % 3 == 0;
          final color = useDark ? domain.darkShade : domain.primary;
          final alpha = 0.25 + rng.nextDouble() * 0.20;
          final blur = 8.0 + rng.nextDouble() * 12.0;
          final spread = 2.0 + rng.nextDouble() * 4.0;
          final size = 6.0 + rng.nextDouble() * 10.0;
          return Align(
            alignment: Alignment(x * 2 - 1, y * 2 - 1),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: alpha),
                    blurRadius: blur,
                    spreadRadius: spread,
                  ),
                ],
              ),
            ),
          );
        }),

        // Vivid pinpoint particles — bright against black
        ...List.generate(18, (i) {
          final x = rng.nextDouble() * 0.92 + 0.04;
          final y = rng.nextDouble() * 0.85 + 0.05;
          final useDark = i % 4 == 0;
          final color = useDark ? domain.darkShade : domain.primary;
          final alpha = 0.40 + rng.nextDouble() * 0.50;
          final size = 1.0 + rng.nextDouble() * 2.5;
          return Align(
            alignment: Alignment(x * 2 - 1, y * 2 - 1),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: alpha),
                boxShadow: size > 2.0
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: alpha * 0.5),
                          blurRadius: 3,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            ),
          );
        }),

        // "All clear" text — crisp against black
        Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'All clear',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: domain.primary.withValues(alpha: 0.60),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 20,
                  height: 0.5,
                  color: domain.primary.withValues(alpha: 0.30),
                ),
                const SizedBox(height: 4),
                Text(
                  'AT PEACE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: domain.primary.withValues(alpha: 0.30),
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Compressed card: gradient bg, subtle glow, hairline edge
  Widget _buildCompressedCard(BuildContext context) {
    final taskCount = tasks.where((t) => t.isActive).length;
    // Strong primary tint for colorful, playful compressed strips
    final tintedSurface = Color.lerp(domain.surface, domain.primary, 0.40)!;
    final blendedMid = Color.lerp(tintedSurface, domain.darkShade, 0.25)!;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: const Alignment(-1.0, -0.1), // ~95°
          end: const Alignment(1.0, 0.1),
          colors: [
            tintedSurface,
            blendedMid,
            tintedSurface.withValues(alpha: 0.85),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
        border: Border(
          left: BorderSide(
            color: domain.primary,
            width: AppSpacing.leftAccentBar,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: domain.primary.withValues(alpha: 0.15),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top hairline
          Container(
            height: 0.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  domain.primary.withValues(alpha: 0.0),
                  domain.primary.withValues(alpha: 0.10),
                  domain.primary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Domain name (smaller)
                  Flexible(
                    child: Text(
                      domain.name,
                      style: AppTypography.ctaLabelText(color: domain.primary).copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),

                  // Task count (right aligned, bolder)
                  Text(
                    _formatTaskCount(taskCount),
                    style: AppTypography.metadataText(
                      color: domain.primary.withValues(alpha: 0.8),
                    ).copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
