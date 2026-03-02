import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../providers/api_provider.dart';
import '../providers/task_store_provider.dart';
import '../services/haptic_service.dart';
import 'styled_snackbar.dart';
import '../utils/string_extensions.dart';

/// Bottom sheet for selecting subtasks from AI suggestions + adding custom ones.
class SubtaskSelectionSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> parentTask;
  final List<String> suggestions;

  const SubtaskSelectionSheet({
    super.key,
    required this.parentTask,
    required this.suggestions,
  });

  @override
  ConsumerState<SubtaskSelectionSheet> createState() =>
      _SubtaskSelectionSheetState();
}

class _SubtaskSelectionSheetState extends ConsumerState<SubtaskSelectionSheet> {
  late final Set<int> _selectedIndices; // indices into _allTitles
  late final List<String> _allTitles;
  final _customController = TextEditingController();
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _allTitles = List<String>.from(widget.suggestions);
    _selectedIndices = {}; // All unchecked by default
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _toggleIndex(int index) {
    HapticService.light();
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  void _addCustom() {
    final text = _customController.text.trim();
    if (text.isEmpty) return;
    HapticService.light();
    setState(() {
      _allTitles.add(text);
      _selectedIndices.add(_allTitles.length - 1); // Pre-check custom
      _customController.clear();
    });
  }

  Future<void> _createSubtasks() async {
    if (_selectedIndices.isEmpty || _isCreating) return;
    HapticService.medium();
    setState(() => _isCreating = true);

    final selectedTitles = _selectedIndices.map((i) => _allTitles[i]).toList();

    try {
      final apiService = ref.read(apiServiceProvider);
      final result = await apiService.resolveQuestion(
        userId: AppConstants.defaultUserId,
        action: 'create_subtasks',
        data: {
          'parent_task_id': widget.parentTask['id'],
          'selected_titles': selectedTitles,
        },
      );

      await ref.read(taskStoreProvider.notifier).fetchAll();

      if (!mounted) return;
      Navigator.pop(context);

      showStyledSnackbar(context,
        message: result.message,
        style: SnackbarStyle.success,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        showStyledSnackbar(context,
          message: 'Failed: $e',
          style: SnackbarStyle.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.parentTask['category'] as String? ?? 'work';
    final paletteMap = ref.watch(domainPalettesProvider);
    final domain = DomainColors.getDomain(category, true, paletteMap);
    final selectedCount = _selectedIndices.length;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: AppColors.darkBg,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppSpacing.radiusLg),
          topRight: Radius.circular(AppSpacing.radiusLg),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.darkText.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: domain.primary.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Break down',
                  style: AppTypography.metadataText(
                    color: AppColors.darkText.withValues(alpha: 0.6),
                  ).copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  (widget.parentTask['title'] as String? ?? '').capitalize,
                  style: AppTypography.metadataText(color: domain.primary)
                      .copyWith(fontSize: 18, fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Subtask list
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              itemCount: _allTitles.length,
              itemBuilder: (context, index) {
                final isSelected = _selectedIndices.contains(index);
                final isCustom = index >= widget.suggestions.length;

                return GestureDetector(
                  onTap: () => _toggleIndex(index),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? domain.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected
                                  ? domain.primary
                                  : AppColors.darkText.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                          child: isSelected
                              ? Icon(
                                  Icons.check,
                                  size: 14,
                                  color: domain.textOnPrimary,
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _allTitles[index],
                            style: AppTypography.metadataText(
                              color: AppColors.darkText,
                            ).copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              fontStyle: isCustom
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Add custom subtask
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.darkBg,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(
                        color: AppColors.darkText.withValues(alpha: 0.2),
                      ),
                    ),
                    child: TextField(
                      controller: _customController,
                      style: AppTypography.metadataText(color: AppColors.darkText)
                          .copyWith(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Add custom subtask',
                        hintStyle: AppTypography.metadataText(
                          color: AppColors.darkText.withValues(alpha: 0.3),
                        ).copyWith(fontSize: 14),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        isDense: true,
                      ),
                      onSubmitted: (_) => _addCustom(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _addCustom,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: domain.primary,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: Icon(
                      Icons.add,
                      size: 20,
                      color: domain.textOnPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // Create button
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              MediaQuery.of(context).padding.bottom + AppSpacing.md,
            ),
            child: GestureDetector(
              onTap: selectedCount > 0 ? _createSubtasks : null,
              child: Container(
                width: double.infinity,
                height: 48,
                decoration: BoxDecoration(
                  color: selectedCount > 0
                      ? domain.primary
                      : domain.primary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  boxShadow: selectedCount > 0 && domain.glow != null
                      ? [
                          BoxShadow(
                            color: domain.glow!,
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: _isCreating
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: domain.textOnPrimary,
                          ),
                        )
                      : Text(
                          'Create $selectedCount Subtask${selectedCount == 1 ? '' : 's'}',
                          style: AppTypography.metadataText(
                            color: selectedCount > 0
                                ? domain.textOnPrimary
                                : domain.textOnPrimary.withValues(alpha: 0.5),
                          ).copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
