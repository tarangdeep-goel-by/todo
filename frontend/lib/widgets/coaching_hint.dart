import 'dart:async';
import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../config/typography.dart';
import '../config/theme.dart';
import '../services/app_logger.dart';

/// Floating hint above CTA that cycles through example voice commands.
/// Shows when user has no tasks to guide first interactions.
class CoachingHint extends StatefulWidget {
  const CoachingHint({super.key});

  @override
  State<CoachingHint> createState() => _CoachingHintState();
}

class _CoachingHintState extends State<CoachingHint> {
  static const _hints = [
    'Hold the pill and say "buy groceries"',
    'Try "schedule standup for tomorrow"',
    'Say "remind me to call mom"',
    'Or tap the pill to type',
    'Try "add workout to health"',
  ];

  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    AppLogger.instance.debug('coaching.visible', logger: 'CoachingHint', data: {
      'hintCount': _hints.length,
    });
    _timer = Timer.periodic(AppAnimations.coachingCycle, (_) {
      if (mounted) {
        setState(() => _currentIndex = (_currentIndex + 1) % _hints.length);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppAnimations.coachingSwitch,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: Text(
        'Try: "${_hints[_currentIndex]}"',
        key: ValueKey(_currentIndex),
        style: AppTypography.metadataText(
          color: AppColors.tertiaryText,
        ).copyWith(
          fontSize: 14,
          fontStyle: FontStyle.italic,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
