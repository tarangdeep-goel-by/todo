import 'dart:convert';

/// AI placement suggestion for task categorization
class AIPlacement {
  /// Suggested parent task ID (null for root)
  final String? suggestedParent;

  /// Confidence score (0.0 - 1.0)
  final double confidence;

  /// AI reasoning for the suggestion
  final String reasoning;

  const AIPlacement({
    this.suggestedParent,
    required this.confidence,
    required this.reasoning,
  });

  /// Create from JSON
  factory AIPlacement.fromJson(Map<String, dynamic> json) {
    return AIPlacement(
      suggestedParent: json['suggestedParent'] as String?,
      confidence: (json['confidence'] as num).toDouble(),
      reasoning: json['reasoning'] as String,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'suggestedParent': suggestedParent,
      'confidence': confidence,
      'reasoning': reasoning,
    };
  }

  /// Convert to JSON string
  String toJsonString() => jsonEncode(toJson());

  /// Create from JSON string
  factory AIPlacement.fromJsonString(String jsonString) {
    return AIPlacement.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  @override
  String toString() {
    return 'AIPlacement(suggestedParent: $suggestedParent, '
        'confidence: $confidence, reasoning: $reasoning)';
  }
}
