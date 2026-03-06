import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/theme.dart';
import '../providers/view_mode_provider.dart';
import '../services/haptic_service.dart';
import '../services/tracker/tracker.dart';
import '../services/tracker/tracker_keys.dart';

/// View toggle button (Node/Flat/Calendar)
class ViewToggle extends ConsumerWidget {
  const ViewToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(viewModeProvider);

    final bgColor = AppColors.darkBg;
    final textColor = AppColors.darkText;
    final activeColor = AppColors.darkText;
    final inactiveColor = textColor.withValues(alpha: 0.5);

    const buttonCount = 3;
    const totalWidth = 210.0;
    const buttonWidth = totalWidth / buttonCount;

    final indicatorLeft = switch (viewMode) {
      ViewMode.node => 0.0,
      ViewMode.flat => buttonWidth,
      ViewMode.calendar => buttonWidth * 2,
    };

    return Container(
      width: totalWidth,
      height: 36,
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: textColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          // Sliding indicator
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            left: indicatorLeft,
            top: 0,
            bottom: 0,
            width: buttonWidth,
            child: Container(
              decoration: BoxDecoration(
                color: activeColor,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
            ),
          ),

          // Buttons
          Row(
            children: [
              _buildButton(
                ref: ref,
                label: 'Node',
                icon: null,
                mode: ViewMode.node,
                current: viewMode,
                bgColor: bgColor,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                buttonKey: TK.nodeToggle,
              ),
              _buildButton(
                ref: ref,
                label: 'Flat',
                icon: null,
                mode: ViewMode.flat,
                current: viewMode,
                bgColor: bgColor,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                buttonKey: TK.flatToggle,
              ),
              _buildButton(
                ref: ref,
                label: null,
                icon: Icons.calendar_today,
                mode: ViewMode.calendar,
                current: viewMode,
                bgColor: bgColor,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                buttonKey: TK.calToggle,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required WidgetRef ref,
    required String? label,
    required IconData? icon,
    required ViewMode mode,
    required ViewMode current,
    required Color bgColor,
    required Color activeColor,
    required Color inactiveColor,
    Key? buttonKey,
  }) {
    final isActive = current == mode;
    final color = isActive ? bgColor : inactiveColor;

    return Expanded(
      child: GestureDetector(
        key: buttonKey,
        onTap: () {
          HapticService.selection();
          Tracker.instance.tap(element: '${mode.name}_toggle', screen: 'home', target: mode.name);
          ref.read(viewModeProvider.notifier).state = mode;
        },
        child: Container(
          color: Colors.transparent,
          child: Center(
            child: label != null
                ? Text(
                    label,
                    style: AppTypography.metadataText(
                      color: color,
                    ).copyWith(fontWeight: FontWeight.w600),
                  )
                : Icon(icon, size: 16, color: color),
          ),
        ),
      ),
    );
  }
}
