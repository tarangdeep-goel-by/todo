import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:todo/data/models/task.dart';
import 'package:todo/config/theme.dart';
import 'package:todo/utils/constants.dart';

/// Task card widget with animations
class TaskCard extends StatefulWidget {
  final Task task;
  final int depth;
  final bool hasChildren;
  final bool isExpanded;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onExpand;
  final ValueChanged<bool>? onComplete;

  const TaskCard({
    super.key,
    required this.task,
    this.depth = 0,
    this.hasChildren = false,
    this.isExpanded = false,
    this.onTap,
    this.onExpand,
    this.onComplete,
  });

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppTheme.shortAnimation,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: AppTheme.defaultCurve),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _controller.forward().then((_) => _controller.reverse());
    HapticFeedback.lightImpact();
    widget.onTap?.call();
  }

  void _handleComplete(bool? value) {
    if (value != null) {
      HapticFeedback.mediumImpact();
      widget.onComplete?.call(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompleted = widget.task.status == TaskStatus.completed;

    return Padding(
      padding: EdgeInsets.only(
        left: widget.depth * Constants.taskIndentationWidth,
        bottom: 8.0,
      ),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Card(
          elevation: Constants.taskCardElevation,
          child: InkWell(
            onTap: _handleTap,
            borderRadius: BorderRadius.circular(Constants.taskCardBorderRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Row(
                children: [
                  // Completion checkbox
                  Checkbox(
                    value: isCompleted,
                    onChanged: widget.task.status == TaskStatus.archived
                        ? null
                        : _handleComplete,
                  ),
                  const SizedBox(width: 8),

                  // Task content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title
                        AnimatedDefaultTextStyle(
                          duration: AppTheme.mediumAnimation,
                          curve: AppTheme.defaultCurve,
                          style: theme.textTheme.bodyLarge!.copyWith(
                            decoration: isCompleted
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                            color: isCompleted
                                ? theme.textTheme.bodyLarge!.color
                                    ?.withValues(alpha: 0.5)
                                : theme.textTheme.bodyLarge!.color,
                          ),
                          child: Text(
                            widget.task.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        // Description (if exists)
                        if (widget.task.description != null &&
                            widget.task.description!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              widget.task.description!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.textTheme.bodySmall!.color
                                    ?.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Expand/collapse icon (if has children)
                  if (widget.hasChildren)
                    AnimatedRotation(
                      duration: AppTheme.mediumAnimation,
                      curve: AppTheme.defaultCurve,
                      turns: widget.isExpanded ? 0.25 : 0,
                      child: IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          widget.onExpand?.call(!widget.isExpanded);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
