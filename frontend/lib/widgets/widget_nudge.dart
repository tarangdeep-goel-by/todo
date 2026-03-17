import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/theme.dart';
import '../config/typography.dart';
import '../config/spacing.dart';
import '../models/task.dart';
import '../providers/task_store_provider.dart';
import '../services/onboarding_service.dart';
import '../services/haptic_service.dart';
import '../services/tracker/tracker.dart';

const _channel = MethodChannel('com.amble.app/widget');

/// Nudge card prompting engaged users to add the Ramble widget.
/// Shows at every 10-task milestone (10, 20, 30...) if not yet dismissed
/// for that milestone.
class WidgetNudge extends ConsumerStatefulWidget {
  const WidgetNudge({super.key});

  @override
  ConsumerState<WidgetNudge> createState() => _WidgetNudgeState();
}

class _WidgetNudgeState extends ConsumerState<WidgetNudge> {
  bool _visible = false;
  bool _dismissed = false;
  int _lastDismissedMilestone = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) _loadMilestone();
  }

  Future<void> _loadMilestone() async {
    final prefs = await SharedPreferences.getInstance();
    _lastDismissedMilestone = prefs.getInt(
      OnboardingService.widgetNudgeMilestoneKey,
    ) ?? 0;
    if (mounted) setState(() => _loaded = true);
  }

  void _checkEligibility(List<Task> tasks) {
    if (!_loaded || _visible) return;
    final totalCount = tasks.length;
    // Current milestone: floor to nearest 10
    final currentMilestone = (totalCount ~/ 10) * 10;
    if (currentMilestone >= 10 && currentMilestone > _lastDismissedMilestone) {
      setState(() => _visible = true);
      Tracker.instance.impression(
        component: 'widget_nudge',
        screen: 'home',
        content: 'milestone_$currentMilestone',
      );
    }
  }

  Future<void> _addWidget() async {
    HapticService.light();
    try {
      final result = await _channel.invokeMethod<bool>('requestPinWidget');
      if (result == true) {
        Tracker.instance.tap(element: 'widget_nudge_add', screen: 'home');
        _dismiss();
      }
    } on PlatformException {
      // Silently fail — user can still add manually
    }
  }

  Future<void> _dismiss() async {
    final tasks = ref.read(allTasksProvider);
    final currentMilestone = (tasks.length ~/ 10) * 10;
    setState(() => _dismissed = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      OnboardingService.widgetNudgeMilestoneKey,
      currentMilestone,
    );
    Tracker.instance.tap(element: 'widget_nudge_dismiss', screen: 'home');
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(allTasksProvider);
    if (!_visible) _checkEligibility(tasks);
    if (!_visible || _dismissed) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.navBg,
        border: Border(
          bottom: BorderSide(
            color: AppColors.darkText.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.darkText.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: const Icon(
              Icons.mic_rounded,
              color: AppColors.darkText,
              size: 18,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ramble from your home screen',
                  style: AppTypography.metadataText(
                    color: AppColors.darkText,
                  ).copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Add a widget for one-tap voice capture',
                  style: AppTypography.metadataText(
                    color: AppColors.secondaryText,
                  ).copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          GestureDetector(
            onTap: _addWidget,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: AppColors.darkText.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Text(
                'Add',
                style: AppTypography.metadataText(
                  color: AppColors.darkText,
                ).copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          GestureDetector(
            onTap: _dismiss,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close,
                color: AppColors.secondaryText,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
