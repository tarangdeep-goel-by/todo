import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/theme.dart';
import '../providers/view_mode_provider.dart';
import '../providers/recording_provider.dart';
import '../services/haptic_service.dart';
import '../services/onboarding_service.dart';
import '../screens/ramble_screen.dart';
import '../screens/profile_screen.dart';
import 'add_task_sheet.dart';
import 'styled_snackbar.dart';
import 'voice_hint_pulse.dart';

/// Zomato-style 5-item bottom nav: Home | Flat | PTT (center FAB) | Calendar | Profile
class BottomNavBar extends ConsumerStatefulWidget {
  const BottomNavBar({super.key});

  @override
  ConsumerState<BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends ConsumerState<BottomNavBar> {
  bool _voiceHintSeen = true; // default true = no hint

  @override
  void initState() {
    super.initState();
    _loadVoiceHint();
  }

  Future<void> _loadVoiceHint() async {
    final seen =
        await OnboardingService.hasSeenHint(OnboardingService.voiceHintKey);
    if (mounted) {
      setState(() => _voiceHintSeen = seen);
    }
  }

  Future<void> _openAddSheet(BuildContext context) async {
    HapticService.light();
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusMd)),
      ),
      builder: (_) => const AddTaskSheet(),
    );

    if (added == true && context.mounted) {
      showStyledSnackbar(context,
        message: 'Task added',
        style: SnackbarStyle.success,
      );
    }
  }

  Future<void> _onLongPress(BuildContext context) async {
    HapticService.medium();
    final result = await Navigator.push<({bool success, String message})>(
      context,
      MaterialPageRoute(builder: (_) => const RambleScreen()),
    );

    // Mark voice hint seen after first voice session
    if (!_voiceHintSeen) {
      await OnboardingService.markHintSeen(OnboardingService.voiceHintKey);
      if (mounted) setState(() => _voiceHintSeen = true);
    }

    if (result != null && context.mounted) {
      showStyledSnackbar(
        context,
        message: result.message,
        style: result.success ? SnackbarStyle.success : SnackbarStyle.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
          color: AppColors.navBg,
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
            // Center PTT with optional voice hint
            Expanded(
              flex: 2,
              child: VoiceHintPulse(
                isActive: !_voiceHintSeen,
                child: _CenterPttButton(
                  isProcessing:
                      recordingState == RecordingState.processing,
                  showVoiceHint: !_voiceHintSeen,
                  onTap: () => _openAddSheet(context),
                  onLongPress: () => _onLongPress(context),
                ),
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
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
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
      child: Semantics(
        button: true,
        selected: isActive,
        label: '$label tab',
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
      ),
    );
  }
}

class _CenterPttButton extends StatelessWidget {
  final bool isProcessing;
  final bool showVoiceHint;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _CenterPttButton({
    required this.isProcessing,
    required this.onTap,
    required this.onLongPress,
    this.showVoiceHint = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor =
        isProcessing ? DomainColors.careerDark.primary : AppColors.darkText;

    return Semantics(
      button: true,
      label: 'Input. Tap to add task, hold to talk',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          height: AppSpacing.pttButtonHeight,
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
                  showVoiceHint ? 'Hold to talk' : 'Add or talk',
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.navLabel(
                    color: isProcessing ? AppColors.darkText : AppColors.darkBg,
                  ).copyWith(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
