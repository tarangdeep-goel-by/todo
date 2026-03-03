import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/theme.dart';
import '../providers/view_mode_provider.dart';
import '../providers/recording_provider.dart';
import '../services/haptic_service.dart';
import '../screens/ramble_screen.dart';
import 'styled_snackbar.dart';

/// Zomato-style 5-item bottom nav: Home | Flat | PTT (center FAB) | Calendar | Profile
class BottomNavBar extends ConsumerWidget {
  const BottomNavBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(viewModeProvider);
    final recordingState = ref.watch(recordingStateProvider);
    final activeColor = AppColors.darkText;
    final inactiveColor = AppColors.darkText.withValues(alpha: 0.5);

    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.bottomNavMarginH,
        right: AppSpacing.bottomNavMarginH,
        bottom: AppSpacing.bottomNavMarginBottom,
      ),
      child: Container(
        height: AppSpacing.bottomNavHeight,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1816),
          borderRadius: BorderRadius.circular(AppSpacing.bottomNavRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
          // Home
          _NavItem(
            icon: Icons.home_rounded,
            label: 'Home',
            isActive: viewMode == ViewMode.node,
            activeColor: activeColor,
            inactiveColor: inactiveColor,
            onTap: () {
              HapticService.selection();
              ref.read(viewModeProvider.notifier).state = ViewMode.node;
            },
          ),
          // Flat
          _NavItem(
            icon: Icons.list_rounded,
            label: 'Flat',
            isActive: viewMode == ViewMode.flat,
            activeColor: activeColor,
            inactiveColor: inactiveColor,
            onTap: () {
              HapticService.selection();
              ref.read(viewModeProvider.notifier).state = ViewMode.flat;
            },
          ),
          // Center PTT
          Expanded(
            flex: 2,
            child: _CenterPttButton(
              isProcessing: recordingState == RecordingState.processing,
              onTap: () {
                HapticService.light();
                ref.read(recordingStateProvider.notifier).state =
                    RecordingState.typing;
              },
              onLongPress: () async {
                HapticService.medium();
                final result =
                    await Navigator.push<({bool success, String message})>(
                  context,
                  MaterialPageRoute(builder: (_) => const RambleScreen()),
                );
                if (result != null && context.mounted) {
                  showStyledSnackbar(
                    context,
                    message: result.message,
                    style: result.success
                        ? SnackbarStyle.success
                        : SnackbarStyle.error,
                  );
                }
              },
            ),
          ),
          // Calendar
          _NavItem(
            icon: Icons.calendar_today_rounded,
            label: 'Cal',
            isActive: viewMode == ViewMode.calendar,
            activeColor: activeColor,
            inactiveColor: inactiveColor,
            onTap: () {
              HapticService.selection();
              ref.read(viewModeProvider.notifier).state = ViewMode.calendar;
            },
          ),
          // Profile
          _NavItem(
            icon: Icons.person_outline_rounded,
            label: 'Profile',
            isActive: false,
            activeColor: activeColor,
            inactiveColor: inactiveColor,
            onTap: () {
              HapticService.light();
              showStyledSnackbar(context,
                  message: 'Coming soon', style: SnackbarStyle.info);
            },
          ),
        ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? activeColor : inactiveColor;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 4),
            Text(label, style: AppTypography.navLabel(color: color)),
          ],
        ),
      ),
    );
  }
}

class _CenterPttButton extends StatelessWidget {
  final bool isProcessing;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _CenterPttButton({
    required this.isProcessing,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor =
        isProcessing ? DomainColors.careerDark.primary : AppColors.darkText;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(23),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.mic_rounded,
              size: 20,
              color: isProcessing ? AppColors.darkText : AppColors.darkBg,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Type or talk',
                overflow: TextOverflow.ellipsis,
                style: AppTypography.navLabel(
                  color: isProcessing ? AppColors.darkText : AppColors.darkBg,
                ).copyWith(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
