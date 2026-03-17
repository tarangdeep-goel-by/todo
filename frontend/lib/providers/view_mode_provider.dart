import 'package:flutter_riverpod/flutter_riverpod.dart';

/// View mode enum
enum ViewMode {
  node, // Parent node view with domain cards
  flat, // Flat all-tasks view
  calendar, // Calendar timeline view grouped by due date
  profile, // Profile and settings
}

/// Provider for current view mode
final viewModeProvider = StateProvider<ViewMode>((ref) => ViewMode.node);
