/// Intent types for voice commands
enum IntentType {
  add,
  complete,
  delete,
  edit,
  query,
  unknown;

  /// Convert from string
  static IntentType fromString(String value) {
    return IntentType.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => IntentType.unknown,
    );
  }
}

/// AI-detected intent from voice command
class AgentIntent {
  /// Detected intent type
  final IntentType intent;

  /// Confidence score (0.0 - 1.0)
  final double confidence;

  /// Intent-specific parameters
  final Map<String, dynamic> parameters;

  const AgentIntent({
    required this.intent,
    required this.confidence,
    required this.parameters,
  });

  /// Create from JSON
  factory AgentIntent.fromJson(Map<String, dynamic> json) {
    return AgentIntent(
      intent: IntentType.fromString(json['intent'] as String),
      confidence: (json['confidence'] as num).toDouble(),
      parameters: json['parameters'] as Map<String, dynamic>? ?? {},
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'intent': intent.name.toUpperCase(),
      'confidence': confidence,
      'parameters': parameters,
    };
  }

  @override
  String toString() {
    return 'AgentIntent(intent: $intent, confidence: $confidence, parameters: $parameters)';
  }
}

/// Response from agent action execution
class AgentResponse {
  /// Success/failure status
  final bool success;

  /// Response message for user
  final String message;

  /// Response type
  final AgentResponseType type;

  /// Optional data payload
  final Map<String, dynamic>? data;

  const AgentResponse({
    required this.success,
    required this.message,
    required this.type,
    this.data,
  });

  /// Create success response
  factory AgentResponse.success({
    required String message,
    AgentResponseType type = AgentResponseType.confirmation,
    Map<String, dynamic>? data,
  }) {
    return AgentResponse(
      success: true,
      message: message,
      type: type,
      data: data,
    );
  }

  /// Create error response
  factory AgentResponse.error(String message) {
    return AgentResponse(
      success: false,
      message: message,
      type: AgentResponseType.error,
    );
  }

  /// Create question response (needs user clarification)
  factory AgentResponse.question({
    required String message,
    required Map<String, dynamic> data,
  }) {
    return AgentResponse(
      success: true,
      message: message,
      type: AgentResponseType.question,
      data: data,
    );
  }

  @override
  String toString() {
    return 'AgentResponse(success: $success, message: $message, type: $type, data: $data)';
  }
}

/// Response type for agent actions
enum AgentResponseType {
  confirmation, // Action completed successfully
  question,     // Need user clarification
  error,        // Action failed
}
