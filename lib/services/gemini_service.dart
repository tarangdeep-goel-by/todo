import 'dart:convert';
import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:todo/config/env.dart';
import 'package:todo/data/models/task.dart';

/// Response from AI categorization
class AICategorizationResponse {
  final String category;
  final String? suggestedParent;
  final double confidence;
  final String reasoning;

  AICategorizationResponse({
    required this.category,
    this.suggestedParent,
    required this.confidence,
    required this.reasoning,
  });

  factory AICategorizationResponse.fromJson(Map<String, dynamic> json) {
    return AICategorizationResponse(
      category: json['category'] as String,
      suggestedParent: json['suggestedParent'] as String?,
      confidence: (json['confidence'] as num).toDouble(),
      reasoning: json['reasoning'] as String,
    );
  }
}

/// Service for Gemini API integration
class GeminiService {
  late final GenerativeModel _model;

  GeminiService() {
    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: Env.geminiApiKey,
    );
  }

  /// Transcribe audio file
  Future<String> transcribeAudio(String audioFilePath) async {
    try {
      final audioFile = File(audioFilePath);
      if (!await audioFile.exists()) {
        throw Exception('Audio file not found: $audioFilePath');
      }

      final audioBytes = await audioFile.readAsBytes();

      // Use audio/mp4 MIME type for m4a files
      final prompt = [
        Content.multi([
          TextPart('Transcribe this audio recording. '
              'Return only the transcribed text without any additional formatting or comments.'),
          DataPart('audio/mp4', audioBytes),
        ])
      ];

      final response = await _model.generateContent(prompt);

      if (response.text == null || response.text!.isEmpty) {
        throw Exception('Empty transcription response');
      }

      return response.text!.trim();
    } catch (e) {
      throw Exception('Failed to transcribe audio: $e');
    }
  }

  /// Categorize task using AI
  Future<AICategorizationResponse> categorizeTask({
    required String transcription,
    required Map<String, List<Task>> taskTree,
  }) async {
    try {
      // Build task tree context
      final treeContext = _buildTreeContext(taskTree);

      final prompt = '''
Current task tree:
$treeContext

User said: "$transcription"

Analyze and suggest:
1. Which top category (work/personal)?
2. Which parent task ID (or null if it should be a root task under the category)?
3. Confidence (0.0-1.0)
4. Reasoning

Respond ONLY with valid JSON in this exact format:
{
  "category": "work",
  "suggestedParent": "task-id-or-null",
  "confidence": 0.92,
  "reasoning": "explanation"
}
''';

      final response = await _model.generateContent([Content.text(prompt)]);

      if (response.text == null || response.text!.isEmpty) {
        throw Exception('Empty categorization response');
      }

      // Extract JSON from response (handle markdown code blocks)
      String jsonText = response.text!.trim();
      if (jsonText.contains('```json')) {
        jsonText = jsonText
            .substring(jsonText.indexOf('```json') + 7)
            .replaceAll('```', '')
            .trim();
      } else if (jsonText.contains('```')) {
        jsonText = jsonText
            .substring(jsonText.indexOf('```') + 3)
            .replaceAll('```', '')
            .trim();
      }

      final jsonData = jsonDecode(jsonText) as Map<String, dynamic>;
      return AICategorizationResponse.fromJson(jsonData);
    } catch (e) {
      throw Exception('Failed to categorize task: $e');
    }
  }

  /// Build task tree context string
  String _buildTreeContext(Map<String, List<Task>> taskTree) {
    final buffer = StringBuffer();

    // Work category
    buffer.writeln('Work (root-work)');
    final workTasks = taskTree['work'] ?? [];
    for (final task in workTasks) {
      _buildTaskBranch(task, taskTree, buffer, 1);
    }

    // Personal category
    buffer.writeln('\nPersonal (root-personal)');
    final personalTasks = taskTree['personal'] ?? [];
    for (final task in personalTasks) {
      _buildTaskBranch(task, taskTree, buffer, 1);
    }

    return buffer.toString();
  }

  /// Build task branch recursively
  void _buildTaskBranch(
    Task task,
    Map<String, List<Task>> taskTree,
    StringBuffer buffer,
    int depth,
  ) {
    final indent = '  ' * depth;
    buffer.writeln('$indent├── ${task.title} (${task.id})');

    // Get children from task tree
    final children = taskTree[task.id] ?? [];
    for (final child in children) {
      _buildTaskBranch(child, taskTree, buffer, depth + 1);
    }
  }
}
