import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../models/task.dart';
import '../providers/task_store_provider.dart';
import '../utils/string_extensions.dart';

/// Result from picking a parent task.
class ParentPickerResult {
  final String? taskId; // null = move to domain root
  final String? taskTitle; // null when moving to root
  final String category;

  const ParentPickerResult({
    this.taskId,
    this.taskTitle,
    required this.category,
  });
}

/// A task entry with computed depth for display indentation.
class _TreeEntry {
  final Task task;
  final int depth;

  const _TreeEntry(this.task, this.depth);
}

/// Search-first flat picker for selecting a parent task.
/// Groups tasks by domain with indentation to show hierarchy depth.
class TaskParentPicker extends ConsumerStatefulWidget {
  final String? currentParentId;
  final String? excludeTaskId;
  final VoidCallback onBack;
  final ValueChanged<ParentPickerResult> onSelect;

  const TaskParentPicker({
    super.key,
    this.currentParentId,
    this.excludeTaskId,
    required this.onBack,
    required this.onSelect,
  });

  @override
  ConsumerState<TaskParentPicker> createState() => _TaskParentPickerState();
}

class _TaskParentPickerState extends ConsumerState<TaskParentPicker> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// BFS to collect all descendant IDs of [rootId] (inclusive).
  Set<String> _getExcludedIds(List<Task> allTasks) {
    if (widget.excludeTaskId == null) return {};
    final excluded = <String>{widget.excludeTaskId!};
    final queue = Queue<String>()..add(widget.excludeTaskId!);
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      for (final t in allTasks) {
        if (t.parentId == current && !excluded.contains(t.id)) {
          excluded.add(t.id);
          queue.add(t.id);
        }
      }
    }
    return excluded;
  }

  /// Compute depth of a task via ancestor walk.
  int _computeDepth(Task task, Map<String, Task> taskMap) {
    int depth = 0;
    final visited = <String>{};
    String? parentId = task.parentId;
    while (parentId != null) {
      if (visited.contains(parentId)) break;
      visited.add(parentId);
      final parent = taskMap[parentId];
      if (parent == null) break;
      depth++;
      parentId = parent.parentId;
    }
    return depth;
  }

  /// Build tree-ordered list: parents before children, sorted by title within siblings.
  List<_TreeEntry> _buildTreeOrder(List<Task> tasks, Map<String, Task> taskMap) {
    // Group by parentId
    final childrenMap = <String?, List<Task>>{};
    for (final t in tasks) {
      (childrenMap[t.parentId] ??= []).add(t);
    }
    // Sort siblings by title
    for (final list in childrenMap.values) {
      list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }

    final result = <_TreeEntry>[];

    void walk(String? parentId, int depth) {
      final children = childrenMap[parentId];
      if (children == null) return;
      for (final child in children) {
        result.add(_TreeEntry(child, depth));
        walk(child.id, depth + 1);
      }
    }

    // Start from root tasks (parentId == null or parentId not in our task set)
    final taskIds = tasks.map((t) => t.id).toSet();
    final roots = tasks.where((t) => t.parentId == null || !taskIds.contains(t.parentId)).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    for (final root in roots) {
      final depth = _computeDepth(root, taskMap);
      result.add(_TreeEntry(root, depth));
      walk(root.id, depth + 1);
    }

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final allTasks = ref.watch(allTasksProvider);
    final paletteMap = ref.watch(domainPalettesProvider);
    final taskMap = {for (final t in allTasks) t.id: t};
    final excludedIds = _getExcludedIds(allTasks);

    // Filter out excluded + completed tasks, then apply search
    var eligible = allTasks.where((t) =>
        !excludedIds.contains(t.id) && t.status != 'completed').toList();

    if (_query.isNotEmpty) {
      eligible = eligible.where((t) =>
          t.title.toLowerCase().contains(_query.toLowerCase())).toList();
    }

    // All 8 domains — always show, even if no tasks exist yet
    const allDomains = [
      'career', 'finance', 'health', 'relationships',
      'growth', 'recreation', 'home', 'community',
    ];
    final categories = allDomains;
    final grouped = <String, List<_TreeEntry>>{};

    if (_query.isEmpty) {
      // Tree order when not searching
      for (final cat in categories) {
        final catTasks = eligible.where((t) =>
            t.category.toLowerCase() == cat.toLowerCase()).toList();
        if (catTasks.isNotEmpty) {
          grouped[cat] = _buildTreeOrder(catTasks, taskMap);
        } else {
          grouped[cat] = [];
        }
      }
    } else {
      // Flat list when searching — compute depth for display
      for (final cat in categories) {
        final catTasks = eligible.where((t) =>
            t.category.toLowerCase() == cat.toLowerCase()).toList();
        if (catTasks.isNotEmpty) {
          grouped[cat] = catTasks.map((t) =>
              _TreeEntry(t, _computeDepth(t, taskMap))).toList();
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm, AppSpacing.md, AppSpacing.lg, AppSpacing.sm,
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                color: AppColors.darkText,
                onPressed: widget.onBack,
              ),
              Text(
                'Pick a parent',
                style: AppTypography.metadataText(color: AppColors.darkText)
                    .copyWith(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),

        // Search field
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            style: AppTypography.metadataText(color: AppColors.darkText)
                .copyWith(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search tasks...',
              hintStyle: AppTypography.metadataText(
                color: AppColors.tertiaryText,
              ).copyWith(fontSize: 14),
              prefixIcon: Icon(
                Icons.search,
                size: 18,
                color: AppColors.tertiaryText,
              ),
              filled: true,
              fillColor: AppColors.darkText.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10,
              ),
              isDense: true,
            ),
          ),
        ),

        const SizedBox(height: AppSpacing.sm),

        // Task list
        Expanded(
          child: _buildList(grouped, categories, paletteMap),
        ),
      ],
    );
  }

  Widget _buildList(
    Map<String, List<_TreeEntry>> grouped,
    List<String> categories,
    Map<String, DomainPalette> paletteMap,
  ) {
    // Check if search returned nothing
    if (_query.isNotEmpty && grouped.values.every((v) => v.isEmpty)) {
      return Center(
        child: Text(
          'No matching tasks',
          style: AppTypography.metadataText(
            color: AppColors.tertiaryText,
          ).copyWith(fontSize: 14),
        ),
      );
    }

    // Pre-compute flat item list for ListView.builder
    final items = <Widget>[];
    for (final cat in categories) {
      if (grouped.containsKey(cat)) {
        items.add(_buildDomainHeader(cat, paletteMap));
        items.add(_buildTopLevelRow(cat, paletteMap));
        if (grouped[cat] != null) {
          for (final entry in grouped[cat]!) {
            items.add(_buildTaskRow(entry, cat, paletteMap));
          }
        }
        items.add(const SizedBox(height: AppSpacing.md));
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      itemCount: items.length,
      itemBuilder: (_, i) => items[i],
    );
  }

  Widget _buildDomainHeader(String category, Map<String, DomainPalette> paletteMap) {
    final domain = DomainColors.getDomain(category, true, paletteMap);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 6),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 2,
            color: domain.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 8),
          Text(
            category.capitalize,
            style: AppTypography.metadataText(color: domain.primary)
                .copyWith(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(height: 1, color: domain.primary.withValues(alpha: 0.15)),
          ),
        ],
      ),
    );
  }

  Widget _buildTopLevelRow(String category, Map<String, DomainPalette> paletteMap) {
    final domain = DomainColors.getDomain(category, true, paletteMap);
    final isSelected = widget.currentParentId == null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onSelect(ParentPickerResult(
        taskId: null,
        taskTitle: null,
        category: category,
      )),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.folder_outlined,
              size: 16,
              color: domain.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 8),
            Text(
              'Top level',
              style: AppTypography.metadataText(
                color: domain.primary.withValues(alpha: 0.6),
              ).copyWith(fontSize: 13, fontStyle: FontStyle.italic),
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

  Widget _buildTaskRow(
    _TreeEntry entry,
    String category,
    Map<String, DomainPalette> paletteMap,
  ) {
    final domain = DomainColors.getDomain(category, true, paletteMap);
    final isSelected = entry.task.id == widget.currentParentId;
    final indent = entry.depth * 16.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onSelect(ParentPickerResult(
        taskId: entry.task.id,
        taskTitle: entry.task.title,
        category: entry.task.category,
      )),
      child: Padding(
        padding: EdgeInsets.only(left: indent, top: 4, bottom: 4),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 24,
              decoration: BoxDecoration(
                color: domain.primary.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                entry.task.sentenceTitle,
                style: AppTypography.metadataText(color: domain.primary)
                    .copyWith(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected)
              Icon(Icons.check, size: 16, color: domain.primary),
          ],
        ),
      ),
    );
  }
}
