import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task_filter.dart';

// Current filter state (only provider needed — store handles data)
final taskFilterProvider = StateProvider<TaskFilter>((ref) => const TaskFilter());
