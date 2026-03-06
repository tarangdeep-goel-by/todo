import 'package:flutter/widgets.dart';

/// Shared Key registry for interactive elements.
/// Used by both E2E tests (find.byKey) and analytics instrumentation.
class TK {
  TK._();

  // Bottom nav
  static const homeTab = Key('home_tab');
  static const flatTab = Key('flat_tab');
  static const calTab = Key('cal_tab');
  static const profileTab = Key('profile_tab');
  static const pttButton = Key('ptt_button');

  // AddTaskSheet
  static const addTaskTextField = Key('add_task_text_field');
  static const sendButton = Key('send_button');
  static const domainChip = Key('domain_chip');
  static const priorityChip = Key('priority_chip');
  static const dueDateChip = Key('due_date_chip');
  static const parentChip = Key('parent_chip');

  // ViewToggle
  static const nodeToggle = Key('node_toggle');
  static const flatToggle = Key('flat_toggle');
  static const calToggle = Key('cal_toggle');

  // RambleScreen
  static const stopButton = Key('stop_button');
  static const submitButton = Key('submit_button');

  // FilterSheet
  static const applyFiltersButton = Key('apply_filters_button');
  static const clearAllButton = Key('clear_all_button');

  // Login
  static const signInButton = Key('sign_in_button');

  // Profile
  static const signOutButton = Key('sign_out_button');
  static const archiveLink = Key('archive_link');
}
