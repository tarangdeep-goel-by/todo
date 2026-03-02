class TaskFilter {
  final List<String>? categories;
  final List<String>? priorities;
  final List<String>? statuses;

  final DateTime? createdAtGte;
  final DateTime? createdAtLte;
  final DateTime? dueDateGte;
  final DateTime? dueDateLte;

  final List<SortOption> sortOptions;

  const TaskFilter({
    this.categories,
    this.priorities,
    this.statuses,
    this.createdAtGte,
    this.createdAtLte,
    this.dueDateGte,
    this.dueDateLte,
    this.sortOptions = const [],
  });

  static const _sentinel = Object();

  TaskFilter copyWith({
    Object? categories = _sentinel,
    Object? priorities = _sentinel,
    Object? statuses = _sentinel,
    Object? createdAtGte = _sentinel,
    Object? createdAtLte = _sentinel,
    Object? dueDateGte = _sentinel,
    Object? dueDateLte = _sentinel,
    Object? sortOptions = _sentinel,
  }) {
    return TaskFilter(
      categories: identical(categories, _sentinel) ? this.categories : categories as List<String>?,
      priorities: identical(priorities, _sentinel) ? this.priorities : priorities as List<String>?,
      statuses: identical(statuses, _sentinel) ? this.statuses : statuses as List<String>?,
      createdAtGte: identical(createdAtGte, _sentinel) ? this.createdAtGte : createdAtGte as DateTime?,
      createdAtLte: identical(createdAtLte, _sentinel) ? this.createdAtLte : createdAtLte as DateTime?,
      dueDateGte: identical(dueDateGte, _sentinel) ? this.dueDateGte : dueDateGte as DateTime?,
      dueDateLte: identical(dueDateLte, _sentinel) ? this.dueDateLte : dueDateLte as DateTime?,
      sortOptions: identical(sortOptions, _sentinel) ? this.sortOptions : sortOptions as List<SortOption>,
    );
  }

  bool get isActive =>
      categories != null ||
      priorities != null ||
      statuses != null ||
      createdAtGte != null ||
      createdAtLte != null ||
      dueDateGte != null ||
      dueDateLte != null ||
      sortOptions.isNotEmpty;

  int get activeFilterCount {
    int count = 0;
    if (categories?.isNotEmpty ?? false) count++;
    if (priorities?.isNotEmpty ?? false) count++;
    if (statuses?.isNotEmpty ?? false) count++;
    if (createdAtGte != null || createdAtLte != null) count++;
    if (dueDateGte != null || dueDateLte != null) count++;
    if (sortOptions.isNotEmpty) count++;
    return count;
  }
}

class SortOption {
  final String field;
  final bool ascending;

  const SortOption(this.field, {this.ascending = true});

  String toQueryString() => '$field:${ascending ? 'asc' : 'desc'}';
}
