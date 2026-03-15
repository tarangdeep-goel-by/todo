import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/constants.dart';
import '../config/theme.dart';
import '../providers/recording_provider.dart';
import '../providers/tutorial_provider.dart';
import '../services/app_logger.dart';
import '../services/haptic_service.dart';
import '../services/onboarding_service.dart';
import '../screens/ramble_screen.dart';
import 'add_task_sheet.dart';
import 'styled_snackbar.dart';

/// Dual-mode input pill: tap to add task (bottom sheet), long-press for ramble voice
class PushToTalkButton extends ConsumerStatefulWidget {
  const PushToTalkButton({super.key});

  @override
  ConsumerState<PushToTalkButton> createState() => _PushToTalkButtonState();
}

class _PushToTalkButtonState extends ConsumerState<PushToTalkButton> {
  final _log = AppLogger.instance;
  @override
  Widget build(BuildContext context) {
    final recordingState = ref.watch(recordingStateProvider);
    final isProcessing = recordingState == RecordingState.processing;

    // Dimensions based on state
    final double width;
    final double height;
    if (isProcessing) {
      width = AppSpacing.ctaActiveWidth;
      height = AppSpacing.ctaActiveHeight;
    } else {
      width = AppSpacing.ctaIdleWidth;
      height = AppSpacing.ctaIdleHeight;
    }

    // Colors
    final idleBg = AppColors.darkText;
    final idleText = AppColors.darkBg;
    final activeBg = DomainColors.careerDark.primary;
    final activeText = DomainColors.careerDark.textOnPrimary;
    final bgColor = isProcessing ? activeBg : idleBg;

    return Center(
      child: AnimatedContainer(
        duration: AppAnimations.ctaExpand,
        curve: AppAnimations.easeOutQuint,
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        clipBehavior: Clip.antiAlias,
        child: isProcessing
            ? _buildProcessingContent(activeText)
            : _buildIdleContent(idleText),
      ),
    );
  }

  Widget _buildIdleContent(Color textColor) {
    return Semantics(
      button: true,
      label: 'Input. Tap to add task, hold to talk',
      child: GestureDetector(
        onTap: _openAddSheet,
        onLongPress: _launchRamble,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 18, color: textColor),
              const SizedBox(width: 6),
              Text('Add or hold to talk',
                  style: AppTypography.ctaLabelText(color: textColor)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProcessingContent(Color activeText) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: AnimatedOpacity(
            opacity: 0.5 + (0.5 * ((index + 1) % 3) / 2),
            duration: const Duration(milliseconds: 500),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: activeText,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }),
    );
  }

  // === Actions ===

  Future<void> _openAddSheet() async {
    _log.debug('ptt.openAddSheet', logger: 'PushToTalkButton');
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

    _log.debug('ptt.addSheet_result', logger: 'PushToTalkButton', data: {'added': added});
    if (added == true && mounted) {
      showStyledSnackbar(context,
        message: 'Task added',
        style: SnackbarStyle.success,
      );
      _maybeActivateTutorial();
    }
  }

  Future<void> _launchRamble() async {
    _log.debug('ptt.launchRamble', logger: 'PushToTalkButton');
    HapticService.medium();
    final result = await Navigator.push<({bool success, String message})>(
      context,
      MaterialPageRoute(builder: (_) => const RambleScreen()),
    );

    _log.debug('ptt.ramble_result', logger: 'PushToTalkButton', data: {
      'success': result?.success, 'message': result?.message,
    });
    if (result != null && mounted) {
      showStyledSnackbar(context,
        message: result.message,
        style: result.success ? SnackbarStyle.success : SnackbarStyle.error,
      );
      if (result.success) _maybeActivateTutorial();
    }
  }

  Future<void> _maybeActivateTutorial() async {
    final alreadyCreated = await OnboardingService.hasCreatedFirstTask();
    _log.debug('ptt.maybeActivateTutorial', logger: 'PushToTalkButton', data: {
      'alreadyCreated': alreadyCreated,
    });
    if (!alreadyCreated) {
      await OnboardingService.markFirstTaskCreated();
      // Advance from step -1 (add task) to step 0 (swipe to complete)
      ref.read(tutorialStepProvider.notifier).state = 0;
      OnboardingService.setSwipeTutorialStep(0);
      _log.debug('ptt.tutorial_triggered', logger: 'PushToTalkButton');
    }
  }
}
