import 'dart:async';
import 'package:flutter/material.dart';
import '../config/typography.dart';
import '../config/theme.dart';

/// Floating hint above CTA that cycles through example voice commands.
/// Shows when user has no tasks to guide first interactions.
class CoachingHint extends StatefulWidget {
  const CoachingHint({super.key});

  @override
  State<CoachingHint> createState() => _CoachingHintState();
}

class _CoachingHintState extends State<CoachingHint> {
  static const _hints = [
    'Add buy groceries to personal',
    'Schedule standup for tomorrow',
    "What's overdue?",
    'Complete the meeting prep',
    'Create a health domain',
  ];

  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
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
      duration: const Duration(milliseconds: 600),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: Text(
        'Try: "${_hints[_currentIndex]}"',
        key: ValueKey(_currentIndex),
        style: AppTypography.metadataText(
          color: AppColors.darkText.withValues(alpha: 0.3),
        ).copyWith(
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
