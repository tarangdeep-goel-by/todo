import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:frontend/services/api_service.dart';
import 'package:frontend/services/audio_service.dart';
import 'package:frontend/services/speech_service.dart';
import 'package:frontend/services/ramble_websocket_service.dart';
import 'package:frontend/config/theme.dart';
import 'package:frontend/models/task.dart';

/// Mock Dio for API service tests
class MockDio extends Mock implements Dio {}

/// Mock ApiService for widget tests
class MockApiService extends Mock implements ApiService {}

/// Mock SpeechToText for speech service tests
class MockSpeechToText extends Mock implements SpeechToText {}

/// Mock WebSocketChannel for websocket service tests
class MockWebSocketChannel extends Mock implements WebSocketChannel {}

/// Mock WebSocketSink for websocket service tests
class MockWebSocketSink extends Mock implements WebSocketSink {}

/// Mock AudioService for widget tests
class MockAudioService extends Mock implements AudioService {}

/// Mock RambleWebSocketService for widget tests
class MockRambleWebSocketService extends Mock implements RambleWebSocketService {}

/// Mock SpeechService for widget tests
class MockSpeechService extends Mock implements SpeechService {}

/// Create a test palette map with all 8 domains
Map<String, DomainPalette> createTestPaletteMap() {
  return {
    'career': DomainColors.careerDark,
    'home': DomainColors.homeDark,
    'health': DomainColors.palettes[2].withName('Health'),
    'growth': DomainColors.growthDark,
    'recreation': DomainColors.recreationDark,
    'finance': DomainColors.financeDark,
    'relationships': DomainColors.relationshipsDark,
    'community': DomainColors.communityDark,
  };
}

/// Factory for a test Task with sensible defaults
Task createTestTask({
  String id = 'test-id-1',
  String userId = 'test-user',
  String title = 'Test Task',
  String? description,
  String? parentId,
  String category = 'career',
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

/// Wrap a widget in ProviderScope + MaterialApp for testing
Widget buildTestApp(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

/// Wrap a widget in ProviderScope + MaterialApp with an Overlay for testing
/// snackbars and other overlay-based widgets.
Widget buildOverlayTestApp(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(
        body: Overlay(
          initialEntries: [
            OverlayEntry(builder: (_) => child),
          ],
        ),
      ),
    ),
  );
}
