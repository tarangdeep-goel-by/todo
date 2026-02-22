import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/models/task.dart';
import 'package:frontend/models/api_response.dart';

/// Mock Dio for API service tests
class MockDio extends Mock implements Dio {}

/// Mock ApiService for widget tests
class MockApiService extends Mock implements ApiService {}

/// Factory for a test Task with sensible defaults
Task createTestTask({
  String id = 'test-id-1',
  String userId = 'test-user',
  String title = 'Test Task',
  String? description,
  String? parentId,
  String category = 'work',
  String? categoryId,
  String status = 'active',
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? dueDate,
  DateTime? completedAt,
  String transcription = 'test task',
  Map<String, dynamic>? aiPlacementJson,
  String? priority,
  double? estimatedHours,
}) {
  final now = DateTime(2025, 1, 15);
  return Task(
    id: id,
    userId: userId,
    title: title,
    description: description,
    parentId: parentId,
    category: category,
    categoryId: categoryId,
    status: status,
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
    dueDate: dueDate,
    completedAt: completedAt,
    transcription: transcription,
    aiPlacementJson: aiPlacementJson,
    priority: priority,
    estimatedHours: estimatedHours,
  );
}

/// Factory for a test AgentResponse
AgentResponse createTestAgentResponse({
  bool success = true,
  String message = 'Done',
  String type = 'confirmation',
  Map<String, dynamic>? data,
}) {
  return AgentResponse(
    success: success,
    message: message,
    type: type,
    data: data,
  );
}

/// Wrap a widget in ProviderScope + MaterialApp for testing
Widget buildTestApp(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}
