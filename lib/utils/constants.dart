/// App-wide constants
class Constants {
  // Private constructor
  Constants._();

  /// Task categories
  static const String workCategory = 'work';
  static const String personalCategory = 'personal';

  /// Root task IDs (top-level categories)
  static const String workRootId = 'root-work';
  static const String personalRootId = 'root-personal';

  /// UI Constants
  static const double taskIndentationWidth = 24.0;
  static const double taskCardElevation = 2.0;
  static const double taskCardBorderRadius = 12.0;

  /// Audio recording
  static const int maxRecordingDurationSeconds = 300; // 5 minutes
  static const String audioFormat = 'm4a';

  /// AI Confidence thresholds
  static const double highConfidenceThreshold = 0.8;
  static const double mediumConfidenceThreshold = 0.5;

  /// Error messages
  static const String permissionDeniedMessage =
      'Microphone permission is required to record tasks';
  static const String recordingErrorMessage = 'Failed to record audio';
  static const String transcriptionErrorMessage =
      'Failed to transcribe audio. Please try again.';
  static const String categorizationErrorMessage =
      'Failed to categorize task. Please select manually.';
  static const String saveTaskErrorMessage = 'Failed to save task';

  /// Success messages
  static const String taskCreatedMessage = 'Task created successfully';
  static const String taskCompletedMessage = 'Task completed';
  static const String taskArchivedMessage = 'Task archived';
}
