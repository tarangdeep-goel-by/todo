import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../config/spacing.dart';
import '../config/theme.dart';
import '../config/typography.dart';
import '../main.dart' show kTestMode;
import '../models/task.dart';
import '../providers/auth_provider.dart';
import '../providers/mutation_provider.dart';
import '../providers/task_store_provider.dart';
import '../services/haptic_service.dart';
import '../services/tracker/tracker.dart';
import '../services/tracker/tracker_keys.dart';
import '../widgets/task_parent_picker.dart';
import 'styled_snackbar.dart';

const _allDomains = [
  'career', 'finance', 'health', 'relationships',
  'growth', 'recreation', 'home', 'community',
];

/// Compact bottom sheet for quick task capture.
class AddTaskSheet extends ConsumerStatefulWidget {
  const AddTaskSheet({super.key});

  @override
  ConsumerState<AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends ConsumerState<AddTaskSheet> {
  final _titleController = TextEditingController();
  final _titleFocus = FocusNode();

  String? _category;
  String _priority = 'none';
  DateTime? _dueDate;
  String? _parentId;
  String? _parentTitle;
  bool _submitting = false;

  String get _activeCat => _category ?? 'home';

  DomainPalette get _domain =>
      DomainColors.getDomain(_activeCat, true, ref.read(domainPalettesProvider));

  @override
  void initState() {
    super.initState();
    Tracker.instance.impression(component: 'add_task_sheet', screen: 'home');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paletteMap = ref.watch(domainPalettesProvider);
    final domain = DomainColors.getDomain(_activeCat, true, paletteMap);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: bottomInset + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 32,
              height: 3.5,
              decoration: BoxDecoration(
                color: AppColors.darkText.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title row: text field + send button
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  key: TK.addTaskTextField,
                  controller: _titleController,
                  focusNode: _titleFocus,
                  autofocus: true,
                  style: AppTypography.ctaLabelText(color: AppColors.darkText)
                      .copyWith(fontSize: 17, fontWeight: FontWeight.w400),
                  decoration: InputDecoration(
                    hintText: 'What needs to be done?',
                    hintStyle: AppTypography.ctaLabelText(
                      color: AppColors.darkText.withValues(alpha: 0.25),
                    ).copyWith(fontSize: 17, fontWeight: FontWeight.w400),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 12),
              _buildSendButton(domain),
            ],
          ),
          const SizedBox(height: 14),

          // Divider
          Container(
            height: 0.5,
            color: AppColors.darkText.withValues(alpha: 0.08),
          ),
          const SizedBox(height: 14),

          // Action chips row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildDomainChip(paletteMap),
                const SizedBox(width: 8),
                _buildPriorityChip(),
                const SizedBox(width: 8),
                _buildDueDateChip(domain),
                const SizedBox(width: 8),
                _buildParentChip(domain),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendButton(DomainPalette domain) {
    return GestureDetector(
      key: TK.sendButton,
      onTap: _submitting ? null : _submit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _submitting
              ? domain.primary.withValues(alpha: 0.4)
              : domain.primary,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: _submitting
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: domain.textOnPrimary,
                  ),
                )
              : Icon(
                  Icons.arrow_upward_rounded,
                  size: 18,
                  color: domain.textOnPrimary,
                ),
        ),
      ),
    );
  }

  Widget _buildDomainChip(Map<String, DomainPalette> paletteMap) {
    final palette = DomainColors.getDomain(_activeCat, true, paletteMap);
    final label = _activeCat[0].toUpperCase() + _activeCat.substring(1);

    return GestureDetector(
      key: TK.domainChip,
      onTap: _showDomainPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: palette.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: palette.primary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.metadataText(color: palette.primary)
                  .copyWith(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            const SizedBox(width: 2),
            Icon(Icons.unfold_more_rounded, size: 14, color: palette.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityChip() {
    final isSet = _priority != 'none';
    Color chipColor;
    switch (_priority) {
      case 'high':
        chipColor = AppColors.priorityHigh;
      case 'medium':
        chipColor = AppColors.priorityMedium;
      case 'low':
        chipColor = AppColors.priorityLow;
      default:
        chipColor = AppColors.darkText.withValues(alpha: 0.3);
    }

    return GestureDetector(
      key: TK.priorityChip,
      onTap: () {
        HapticService.light();
        const p = ['none', 'low', 'medium', 'high'];
        setState(() => _priority = p[(p.indexOf(_priority) + 1) % p.length]);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSet
              ? chipColor.withValues(alpha: 0.12)
              : AppColors.darkText.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flag_rounded, size: 13, color: chipColor),
            if (isSet) ...[
              const SizedBox(width: 4),
              Text(
                _priority[0].toUpperCase() + _priority.substring(1),
                style: AppTypography.metadataText(color: chipColor)
                    .copyWith(fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDueDateChip(DomainPalette domain) {
    final hasDate = _dueDate != null;
    final chipColor = hasDate ? domain.primary : AppColors.darkText.withValues(alpha: 0.3);

    String? label;
    if (hasDate) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final picked = DateTime(_dueDate!.year, _dueDate!.month, _dueDate!.day);
      final diff = picked.difference(today).inDays;
      if (diff == 0) {
        label = 'Today';
      } else if (diff == 1) {
        label = 'Tomorrow';
      } else {
        label = '${_dueDate!.day}/${_dueDate!.month}';
      }
    }

    return GestureDetector(
      key: TK.dueDateChip,
      onTap: _pickDate,
      onLongPress: hasDate ? () {
        HapticService.light();
        setState(() => _dueDate = null);
      } : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: hasDate
              ? chipColor.withValues(alpha: 0.12)
              : AppColors.darkText.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_rounded, size: 13, color: chipColor),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: AppTypography.metadataText(color: chipColor)
                    .copyWith(fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildParentChip(DomainPalette domain) {
    final hasParent = _parentId != null;
    final chipColor = hasParent ? domain.primary : AppColors.darkText.withValues(alpha: 0.3);

    return GestureDetector(
      key: TK.parentChip,
      onTap: _openParentPicker,
      onLongPress: hasParent ? () {
        HapticService.light();
        setState(() { _parentId = null; _parentTitle = null; });
      } : null,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: hasParent
              ? chipColor.withValues(alpha: 0.12)
              : AppColors.darkText.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.subdirectory_arrow_right_rounded, size: 13, color: chipColor),
            if (hasParent) ...[
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  _parentTitle ?? 'Subtask',
                  style: AppTypography.metadataText(color: chipColor)
                      .copyWith(fontWeight: FontWeight.w600, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // === Actions ===

  void _showDomainPicker() {
    HapticService.light();
    final paletteMap = ref.read(domainPalettesProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusMd)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 32, height: 3.5,
                decoration: BoxDecoration(
                  color: AppColors.darkText.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 10,
              children: _allDomains.map((name) {
                final palette = DomainColors.getDomain(name, true, paletteMap);
                final isSelected = name == _activeCat;
                final display = name[0].toUpperCase() + name.substring(1);

                return GestureDetector(
                  onTap: () {
                    HapticService.light();
                    setState(() {
                      _category = name;
                      _parentId = null;
                      _parentTitle = null;
                    });
                    Navigator.pop(ctx);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? palette.primary
                          : palette.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                    ),
                    child: Text(
                      display,
                      style: AppTypography.domainPillText(
                        color: isSelected ? palette.textOnPrimary : palette.primary,
                      ).copyWith(fontSize: 13),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _openParentPicker() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusMd)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.7,
        child: TaskParentPicker(
          currentParentId: _parentId,
          onBack: () => Navigator.pop(ctx),
          onSelect: (result) {
            setState(() {
              _parentId = result.taskId;
              _parentTitle = result.taskTitle;
              if (result.category != _activeCat) {
                _category = result.category;
              }
            });
            Navigator.pop(ctx);
          },
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final domain = _domain;
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
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
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    setState(() => _submitting = true);

    try {
      // Offline-first: create with client-generated task, enqueue for sync
      final now = DateTime.now();
      final userId = kTestMode ? 'test-user-e2e' : (ref.read(currentUserIdProvider) ?? '');
      final optimistic = Task(
        id: const Uuid().v4(),
        userId: userId,
        title: title,
        category: _activeCat,
        parentId: _parentId,
        status: 'active',
        createdAt: now,
        updatedAt: now,
        dueDate: _dueDate,
        priority: _priority == 'none' ? null : _priority,
        transcription: title,
      );
      final payload = <String, dynamic>{
        'title': title,
        'category': _activeCat,
        if (_parentId != null) 'parent_id': _parentId,
        if (_dueDate != null) 'due_date': _dueDate!.toIso8601String(),
        if (_priority != 'none') 'priority': _priority,
        'transcription': title,
      };

      final mutation = ref.read(taskMutationServiceProvider);
      await mutation.createTask(optimistic, payload);
      Tracker.instance.outcome(type: 'task_created', method: 'keyboard', category: _activeCat);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e, st) {
      debugPrint('[AddTaskSheet] _submit error: $e\n$st');
      setState(() => _submitting = false);
      if (mounted) {
        showStyledSnackbar(context,
          message: 'Failed to add task. Try again.',
          style: SnackbarStyle.error,
        );
      }
    }
  }
}
