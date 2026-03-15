import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tutorial step shared across screens.
///
/// Steps:
///   -1 = not started (no tasks yet, show "add task" nudge)
///    0 = swipe right to complete
///    1 = swipe left to mark active (undo)
///    2 = swipe left to archive
///    3 = go to profile → archive
///    4 = swipe right to restore (archive screen)
///    5 = swipe left to delete (archive screen)
///    6+ = done
///
/// Step -1 is persistent (stays until first task created).
/// Steps 0-5 are non-blocking (dismissed if user navigates away).
final tutorialStepProvider = StateProvider<int>((ref) => -1);

/// Whether the tutorial is actively showing nudges (steps 0-5).
final tutorialActiveProvider = Provider<bool>((ref) {
  final step = ref.watch(tutorialStepProvider);
  return step >= 0 && step < 6;
});
