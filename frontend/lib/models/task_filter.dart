class TaskFilter {
  final List<String>? categories;
  final List<String>? priorities;
  final List<String>? statuses;
  final String? parentId;
  final List<String>? tags;

  final DateTime? createdAtGte;
  final DateTime? createdAtLte;
  final DateTime? dueDateGte;
  final DateTime? dueDateLte;

  final List<SortOption> sortOptions;

  const TaskFilter({
    this.categories,
    this.priorities,
    this.statuses,
    this.parentId,
    this.tags,
    this.createdAtGte,
    this.createdAtLte,
    this.dueDateGte,
    this.dueDateLte,
    this.sortOptions = const [],
  });

  TaskFilter copyWith({
    List<String>? categories,
    List<String>? priorities,
    List<String>? statuses,
    String? parentId,
    List<String>? tags,
    DateTime? createdAtGte,
    DateTime? createdAtLte,
    DateTime? dueDateGte,
    DateTime? dueDateLte,
    List<SortOption>? sortOptions,
  }) {
    return TaskFilter(
      categories: categories ?? this.categories,
      priorities: priorities ?? this.priorities,
      statuses: statuses ?? this.statuses,
      parentId: parentId ?? this.parentId,
      tags: tags ?? this.tags,
      createdAtGte: createdAtGte ?? this.createdAtGte,
      createdAtLte: createdAtLte ?? this.createdAtLte,
      dueDateGte: dueDateGte ?? this.dueDateGte,
      dueDateLte: dueDateLte ?? this.dueDateLte,
      sortOptions: sortOptions ?? this.sortOptions,
    );
  }

  bool get isActive =>
      categories != null ||
      priorities != null ||
      statuses != null ||
      tags != null ||
      createdAtGte != null ||
      dueDateGte != null ||
      sortOptions.isNotEmpty;

  int get activeFilterCount {
    int count = 0;
    if (categories?.isNotEmpty ?? false) count++;
    if (priorities?.isNotEmpty ?? false) count++;
    if (statuses?.isNotEmpty ?? false) count++;
    if (tags?.isNotEmpty ?? false) count++;
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
