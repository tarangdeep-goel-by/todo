/// Backend category — first-class domain that persists independently of tasks.
class Category {
  final String id;
  final String name; // lowercase
  final int position; // 0-4 → palette index
  final DateTime createdAt;

  const Category({
    required this.id,
    required this.name,
    required this.position,
    required this.createdAt,
  });

  String get displayName => name[0].toUpperCase() + name.substring(1);

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String,
      name: json['name'] as String,
      position: json['position'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
