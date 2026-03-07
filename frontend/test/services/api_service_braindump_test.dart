import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:frontend/models/api_response.dart';
import 'package:frontend/services/api_service.dart';

import '../helpers/test_helpers.dart';

void main() {
  late MockDio mockDio;
  late ApiService apiService;

  setUp(() {
    mockDio = MockDio();
    apiService = ApiService(dio: mockDio);
  });

  // ──────────────── BrainDumpTaskProposal model ────────────────

  group('BrainDumpTaskProposal', () {
    test('fromJson full fields', () {
      final json = {
        'id': 'p1',
        'action': 'add',
        'content': 'Buy groceries',
        'description': 'From the store',
        'category': 'home',
        'due_date': '2025-06-01T10:00:00.000Z',
        'priority': 'high',
        'parent_id': 'parent-1',
        'labels': ['shopping'],
        'changes': {'priority': 'low'},
        'matched_task_id': 'task-123',
        'confidence': 0.95,
        'tags': ['urgent'],
        'estimated_hours': 1.5,
        'alternate_matches': [
          {'id': 'alt-1', 'title': 'Alt task', 'category': 'home'}
        ],
        'match_explanation': 'Matched "groceries" (similarity: 87%)',
      };

      final proposal = BrainDumpTaskProposal.fromJson(json);
      expect(proposal.id, 'p1');
      expect(proposal.action, 'add');
      expect(proposal.content, 'Buy groceries');
      expect(proposal.description, 'From the store');
      expect(proposal.category, 'home');
      expect(proposal.dueDate, isNotNull);
      expect(proposal.priority, 'high');
      expect(proposal.parentId, 'parent-1');
      expect(proposal.labels, ['shopping']);
      expect(proposal.changes, {'priority': 'low'});
      expect(proposal.matchedTaskId, 'task-123');
      expect(proposal.confidence, 0.95);
      expect(proposal.tags, ['urgent']);
      expect(proposal.estimatedHours, 1.5);
      expect(proposal.alternateMatches, hasLength(1));
      expect(proposal.matchExplanation, contains('87%'));
    });

    test('fromJson minimal (defaults)', () {
      final json = {
        'id': 'p2',
        'content': 'Simple task',
        'category': 'career',
      };

      final proposal = BrainDumpTaskProposal.fromJson(json);
      expect(proposal.id, 'p2');
      expect(proposal.action, 'add'); // default
      expect(proposal.content, 'Simple task');
      expect(proposal.labels, isEmpty); // default empty list
      expect(proposal.description, isNull);
      expect(proposal.dueDate, isNull);
      expect(proposal.priority, isNull);
      expect(proposal.parentId, isNull);
      expect(proposal.confidence, isNull);
    });

    test('toJson roundtrip', () {
      final original = BrainDumpTaskProposal(
        id: 'rt-1',
        action: 'edit',
        content: 'Update report',
        category: 'career',
        priority: 'medium',
        tags: ['work'],
        estimatedHours: 2.0,
      );

      final json = original.toJson();
      final restored = BrainDumpTaskProposal.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.action, original.action);
      expect(restored.content, original.content);
      expect(restored.category, original.category);
      expect(restored.priority, original.priority);
      expect(restored.tags, original.tags);
      expect(restored.estimatedHours, original.estimatedHours);
    });

    test('fromJson with alternate_matches', () {
      final json = {
        'id': 'p3',
        'content': 'Complete report',
        'category': 'career',
        'action': 'complete',
        'matched_task_id': 'task-1',
        'alternate_matches': [
          {'id': 'alt-1', 'title': 'Report A', 'category': 'career'},
          {'id': 'alt-2', 'title': 'Report B', 'category': 'career'},
        ],
      };

      final proposal = BrainDumpTaskProposal.fromJson(json);
      expect(proposal.alternateMatches, hasLength(2));
      expect(proposal.alternateMatches![0]['title'], 'Report A');
    });
  });

  // ──────────────── BrainDumpResponse model ────────────────

  group('BrainDumpResponse', () {
    test('fromJson with tasks', () {
      final json = {
        'success': true,
        'transcription': 'buy milk and call mom',
        'message': 'Found 2 tasks',
        'tasks': [
          {'id': 'p1', 'action': 'add', 'content': 'Buy milk', 'category': 'home'},
          {'id': 'p2', 'action': 'add', 'content': 'Call mom', 'category': 'relationships'},
        ],
      };

      final response = BrainDumpResponse.fromJson(json);
      expect(response.success, true);
      expect(response.transcription, 'buy milk and call mom');
      expect(response.message, 'Found 2 tasks');
      expect(response.tasks, hasLength(2));
      expect(response.tasks[0].content, 'Buy milk');
    });

    test('fromJson empty tasks', () {
      final json = {
        'success': true,
        'transcription': 'asdfgh',
        'tasks': [],
      };

      final response = BrainDumpResponse.fromJson(json);
      expect(response.success, true);
      expect(response.tasks, isEmpty);
      expect(response.message, isNull);
    });
  });

  // ──────────────── BrainDumpSubmitResponse model ────────────────

  group('BrainDumpSubmitResponse', () {
    test('fromJson', () {
      final json = {
        'success': true,
        'created_count': 3,
        'created_task_ids': ['id-1', 'id-2', 'id-3'],
        'message': 'Created 3 tasks',
      };

      final response = BrainDumpSubmitResponse.fromJson(json);
      expect(response.success, true);
      expect(response.createdCount, 3);
      expect(response.createdTaskIds, hasLength(3));
      expect(response.message, 'Created 3 tasks');
    });
  });

  // ──────────────── ApiService.processBrainDump ────────────────

  group('ApiService.processBrainDump', () {
    test('success returns BrainDumpResponse', () async {
      when(() => mockDio.post(
            '/agent/braindump',
            data: any(named: 'data'),
          )).thenAnswer((_) async => Response(
                data: {
                  'success': true,
                  'transcription': 'buy groceries',
                  'tasks': [
                    {'id': 'p1', 'action': 'add', 'content': 'Buy groceries', 'category': 'home'},
                  ],
                },
                statusCode: 200,
                requestOptions: RequestOptions(path: '/agent/braindump'),
              ));

      final result = await apiService.processBrainDump(transcription: 'buy groceries');
      expect(result.success, true);
      expect(result.tasks, hasLength(1));
      expect(result.tasks[0].content, 'Buy groceries');
    });

    test('sends category in request body', () async {
      when(() => mockDio.post(
            '/agent/braindump',
            data: any(named: 'data'),
          )).thenAnswer((_) async => Response(
                data: {
                  'success': true,
                  'transcription': 'test',
                  'tasks': [],
                },
                statusCode: 200,
                requestOptions: RequestOptions(path: '/agent/braindump'),
              ));

      await apiService.processBrainDump(transcription: 'test', category: 'health');

      final captured = verify(() => mockDio.post(
            '/agent/braindump',
            data: captureAny(named: 'data'),
          )).captured.last as Map<String, dynamic>;
      expect(captured['category'], 'health');
    });

    test('sends parent_id in request body', () async {
      when(() => mockDio.post(
            '/agent/braindump',
            data: any(named: 'data'),
          )).thenAnswer((_) async => Response(
                data: {
                  'success': true,
                  'transcription': 'test',
                  'tasks': [],
                },
                statusCode: 200,
                requestOptions: RequestOptions(path: '/agent/braindump'),
              ));

      await apiService.processBrainDump(transcription: 'test', parentId: 'parent-123');

      final captured = verify(() => mockDio.post(
            '/agent/braindump',
            data: captureAny(named: 'data'),
          )).captured.last as Map<String, dynamic>;
      expect(captured['parent_id'], 'parent-123');
    });

    test('error propagates ApiError', () async {
      when(() => mockDio.post(
            '/agent/braindump',
            data: any(named: 'data'),
          )).thenThrow(DioException(
            requestOptions: RequestOptions(path: '/agent/braindump'),
            response: Response(
              statusCode: 500,
              data: {'detail': 'Internal error'},
              requestOptions: RequestOptions(path: '/agent/braindump'),
            ),
            type: DioExceptionType.badResponse,
          ));

      expect(
        () => apiService.processBrainDump(transcription: 'test'),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ──────────────── ApiService.submitBrainDump ────────────────

  group('ApiService.submitBrainDump', () {
    test('success returns BrainDumpSubmitResponse', () async {
      when(() => mockDio.post(
            '/agent/braindump/submit',
            data: any(named: 'data'),
          )).thenAnswer((_) async => Response(
                data: {
                  'success': true,
                  'created_count': 2,
                  'created_task_ids': ['id-1', 'id-2'],
                  'message': 'Created 2 tasks',
                },
                statusCode: 200,
                requestOptions: RequestOptions(path: '/agent/braindump/submit'),
              ));

      final proposals = [
        BrainDumpTaskProposal(id: 'p1', content: 'Task 1', category: 'career'),
        BrainDumpTaskProposal(id: 'p2', content: 'Task 2', category: 'home'),
      ];

      final result = await apiService.submitBrainDump(tasks: proposals);
      expect(result.success, true);
      expect(result.createdCount, 2);
      expect(result.createdTaskIds, ['id-1', 'id-2']);
    });

    test('empty proposals list', () async {
      when(() => mockDio.post(
            '/agent/braindump/submit',
            data: any(named: 'data'),
          )).thenAnswer((_) async => Response(
                data: {
                  'success': true,
                  'created_count': 0,
                  'created_task_ids': <String>[],
                  'message': 'No tasks created',
                },
                statusCode: 200,
                requestOptions: RequestOptions(path: '/agent/braindump/submit'),
              ));

      final result = await apiService.submitBrainDump(tasks: []);
      expect(result.createdCount, 0);
    });
  });

  // ──────────────── ApiService FCM token methods ────────────────

  group('ApiService.registerFcmToken', () {
    test('sends correct body', () async {
      when(() => mockDio.post(
            '/notifications/token',
            data: any(named: 'data'),
          )).thenAnswer((_) async => Response(
                data: {'status': 'ok'},
                statusCode: 200,
                requestOptions: RequestOptions(path: '/notifications/token'),
              ));

      await apiService.registerFcmToken('fcm-abc', 'android', 'Asia/Kolkata');

      final captured = verify(() => mockDio.post(
            '/notifications/token',
            data: captureAny(named: 'data'),
          )).captured.last as Map<String, dynamic>;

      expect(captured['token'], 'fcm-abc');
      expect(captured['platform'], 'android');
      expect(captured['timezone'], 'Asia/Kolkata');
    });

    test('error propagates', () async {
      when(() => mockDio.post(
            '/notifications/token',
            data: any(named: 'data'),
          )).thenThrow(DioException(
            requestOptions: RequestOptions(path: '/notifications/token'),
            type: DioExceptionType.connectionTimeout,
          ));

      expect(
        () => apiService.registerFcmToken('token', 'android', 'UTC'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('ApiService.unregisterFcmToken', () {
    test('sends correct body', () async {
      when(() => mockDio.delete(
            '/notifications/token',
            data: any(named: 'data'),
          )).thenAnswer((_) async => Response(
                data: {'status': 'ok'},
                statusCode: 200,
                requestOptions: RequestOptions(path: '/notifications/token'),
              ));

      await apiService.unregisterFcmToken('fcm-abc');

      final captured = verify(() => mockDio.delete(
            '/notifications/token',
            data: captureAny(named: 'data'),
          )).captured.last as Map<String, dynamic>;

      expect(captured['token'], 'fcm-abc');
    });

    test('error propagates', () async {
      when(() => mockDio.delete(
            '/notifications/token',
            data: any(named: 'data'),
          )).thenThrow(DioException(
            requestOptions: RequestOptions(path: '/notifications/token'),
            response: Response(
              statusCode: 404,
              data: {'detail': 'Not found'},
              requestOptions: RequestOptions(path: '/notifications/token'),
            ),
            type: DioExceptionType.badResponse,
          ));

      expect(
        () => apiService.unregisterFcmToken('missing-token'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
