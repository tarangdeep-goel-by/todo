import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:todo/services/agent_service.dart';
import 'package:todo/services/gemini_service.dart';
import 'package:todo/data/repositories/task_repository.dart';
import 'package:todo/data/models/agent_intent.dart';
import 'package:todo/data/models/task.dart';
import 'package:todo/data/models/ai_placement.dart';

@GenerateMocks([GeminiService, TaskRepository])
import 'agent_service_test.mocks.dart';

void main() {
  late AgentService agentService;
  late MockGeminiService mockGeminiService;
  late MockTaskRepository mockTaskRepository;

  setUp(() {
    mockGeminiService = MockGeminiService();
    mockTaskRepository = MockTaskRepository();
    agentService = AgentService(
      geminiService: mockGeminiService,
      taskRepository: mockTaskRepository,
    );
  });

  group('AgentService - ADD Intent', () {
    test('should create task with correct parameters', () async {
      // Arrange
      const audioPath = '/path/to/audio.m4a';
      const transcription = 'Add groceries to shopping list';

      // Mock transcription
      when(mockGeminiService.transcribeAudio(audioPath))
          .thenAnswer((_) async => transcription);

      // Mock intent detection
      final intent = AgentIntent(
        intent: IntentType.add,
        confidence: 0.95,
        parameters: {
          'title': 'groceries',
          'category': 'personal',
          'suggestedParent': null,
        },
      );
      when(mockGeminiService.detectIntent(
        transcription: transcription,
        taskTree: anyNamed('taskTree'),
      )).thenAnswer((_) async => intent);

      // Mock task creation
      when(mockTaskRepository.createTask(
        title: 'groceries',
        category: TaskCategory.personal,
        transcription: 'groceries',
        aiPlacement: anyNamed('aiPlacement'),
        parentId: anyNamed('parentId'),
      )).thenAnswer((_) async => 'task-123');

      // Mock task queries for tree building
      when(mockTaskRepository.getTasksByCategory(TaskCategory.work))
          .thenAnswer((_) async => []);
      when(mockTaskRepository.getTasksByCategory(TaskCategory.personal))
          .thenAnswer((_) async => []);

      // Act
      final response = await agentService.processVoiceCommand(audioPath);

      // Assert
      expect(response.success, isTrue);
      expect(response.message, contains('Created task'));
      expect(response.data?['title'], 'groceries');
      expect(response.data?['category'], 'personal');

      // Verify task creation was called
      verify(mockTaskRepository.createTask(
        title: 'groceries',
        category: TaskCategory.personal,
        transcription: 'groceries',
        aiPlacement: anyNamed('aiPlacement'),
        parentId: anyNamed('parentId'),
      )).called(1);
    });

    test('should handle low confidence with error', () async {
      // Arrange
      const audioPath = '/path/to/audio.m4a';
      const transcription = 'mumblemumblemumble';

      when(mockGeminiService.transcribeAudio(audioPath))
          .thenAnswer((_) async => transcription);

      final intent = AgentIntent(
        intent: IntentType.unknown,
        confidence: 0.3,
        parameters: {},
      );
      when(mockGeminiService.detectIntent(
        transcription: transcription,
        taskTree: anyNamed('taskTree'),
      )).thenAnswer((_) async => intent);

      when(mockTaskRepository.getTasksByCategory(any))
          .thenAnswer((_) async => []);

      // Act
      final response = await agentService.processVoiceCommand(audioPath);

      // Assert
      expect(response.success, isFalse);
      expect(response.message, contains('Not sure what you meant'));
    });
  });

  group('AgentService - COMPLETE Intent', () {
    test('should complete task when single match found', () async {
      // Arrange
      const audioPath = '/path/to/audio.m4a';
      const transcription = 'Complete the backend API task';

      when(mockGeminiService.transcribeAudio(audioPath))
          .thenAnswer((_) async => transcription);

      final intent = AgentIntent(
        intent: IntentType.complete,
        confidence: 0.92,
        parameters: {
          'taskQuery': 'backend API',
        },
      );
      when(mockGeminiService.detectIntent(
        transcription: transcription,
        taskTree: anyNamed('taskTree'),
      )).thenAnswer((_) async => intent);

      // Mock task tree with matching task
      final task = Task(
        id: 'task-123',
        userId: 'user-1',
        title: 'Backend API',
        category: TaskCategory.work,
        status: TaskStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transcription: 'Backend API',
        aiPlacement: const AIPlacement(confidence: 0.9, reasoning: 'test'),
      );

      when(mockTaskRepository.getTasksByCategory(TaskCategory.work))
          .thenAnswer((_) async => [task]);
      when(mockTaskRepository.getTasksByCategory(TaskCategory.personal))
          .thenAnswer((_) async => []);

      when(mockTaskRepository.markTaskDone('task-123'))
          .thenAnswer((_) async => {});

      // Act
      final response = await agentService.processVoiceCommand(audioPath);

      // Assert
      expect(response.success, isTrue);
      expect(response.message, contains('Completed task'));
      expect(response.data?['taskId'], 'task-123');

      verify(mockTaskRepository.markTaskDone('task-123')).called(1);
    });

    test('should ask for clarification when multiple matches found', () async {
      // Arrange
      const audioPath = '/path/to/audio.m4a';
      const transcription = 'Complete the meeting task';

      when(mockGeminiService.transcribeAudio(audioPath))
          .thenAnswer((_) async => transcription);

      final intent = AgentIntent(
        intent: IntentType.complete,
        confidence: 0.88,
        parameters: {
          'taskQuery': 'meeting',
        },
      );
      when(mockGeminiService.detectIntent(
        transcription: transcription,
        taskTree: anyNamed('taskTree'),
      )).thenAnswer((_) async => intent);

      // Mock multiple matching tasks
      final task1 = Task(
        id: 'task-1',
        userId: 'user-1',
        title: 'Team Meeting Notes',
        category: TaskCategory.work,
        status: TaskStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transcription: 'Team Meeting Notes',
        aiPlacement: const AIPlacement(confidence: 0.9, reasoning: 'test'),
      );

      final task2 = Task(
        id: 'task-2',
        userId: 'user-1',
        title: 'Client Meeting Prep',
        category: TaskCategory.work,
        status: TaskStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transcription: 'Client Meeting Prep',
        aiPlacement: const AIPlacement(confidence: 0.9, reasoning: 'test'),
      );

      when(mockTaskRepository.getTasksByCategory(TaskCategory.work))
          .thenAnswer((_) async => [task1, task2]);
      when(mockTaskRepository.getTasksByCategory(TaskCategory.personal))
          .thenAnswer((_) async => []);

      // Act
      final response = await agentService.processVoiceCommand(audioPath);

      // Assert
      expect(response.success, isTrue);
      expect(response.type, AgentResponseType.question);
      expect(response.message, contains('Found 2 tasks'));
      expect(response.data?['matches'], hasLength(2));
      expect(response.data?['action'], 'complete');
    });

    test('should return error when no matches found', () async {
      // Arrange
      const audioPath = '/path/to/audio.m4a';
      const transcription = 'Complete the nonexistent task';

      when(mockGeminiService.transcribeAudio(audioPath))
          .thenAnswer((_) async => transcription);

      final intent = AgentIntent(
        intent: IntentType.complete,
        confidence: 0.85,
        parameters: {
          'taskQuery': 'nonexistent',
        },
      );
      when(mockGeminiService.detectIntent(
        transcription: transcription,
        taskTree: anyNamed('taskTree'),
      )).thenAnswer((_) async => intent);

      when(mockTaskRepository.getTasksByCategory(any))
          .thenAnswer((_) async => []);

      // Act
      final response = await agentService.processVoiceCommand(audioPath);

      // Assert
      expect(response.success, isFalse);
      expect(response.message, contains('Could not find task'));
    });
  });

  group('AgentService - DELETE Intent', () {
    test('should ask for confirmation before deleting', () async {
      // Arrange
      const audioPath = '/path/to/audio.m4a';
      const transcription = 'Delete my old notes';

      when(mockGeminiService.transcribeAudio(audioPath))
          .thenAnswer((_) async => transcription);

      final intent = AgentIntent(
        intent: IntentType.delete,
        confidence: 0.90,
        parameters: {
          'taskQuery': 'old notes',
        },
      );
      when(mockGeminiService.detectIntent(
        transcription: transcription,
        taskTree: anyNamed('taskTree'),
      )).thenAnswer((_) async => intent);

      final task = Task(
        id: 'task-456',
        userId: 'user-1',
        title: 'Old Notes',
        category: TaskCategory.personal,
        status: TaskStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transcription: 'Old Notes',
        aiPlacement: const AIPlacement(confidence: 0.9, reasoning: 'test'),
      );

      when(mockTaskRepository.getTasksByCategory(TaskCategory.work))
          .thenAnswer((_) async => []);
      when(mockTaskRepository.getTasksByCategory(TaskCategory.personal))
          .thenAnswer((_) async => [task]);

      // Act
      final response = await agentService.processVoiceCommand(audioPath);

      // Assert
      expect(response.success, isTrue);
      expect(response.type, AgentResponseType.question);
      expect(response.message, contains('Are you sure'));
      expect(response.data?['requiresConfirmation'], isTrue);
      expect(response.data?['taskId'], 'task-456');
    });
  });

  group('AgentService - EDIT Intent', () {
    test('should update task with changes', () async {
      // Arrange
      const audioPath = '/path/to/audio.m4a';
      const transcription = 'Change doctor appointment to tomorrow';

      when(mockGeminiService.transcribeAudio(audioPath))
          .thenAnswer((_) async => transcription);

      final intent = AgentIntent(
        intent: IntentType.edit,
        confidence: 0.91,
        parameters: {
          'taskQuery': 'doctor appointment',
          'changes': {
            'dueDate': 'tomorrow',
          },
        },
      );
      when(mockGeminiService.detectIntent(
        transcription: transcription,
        taskTree: anyNamed('taskTree'),
      )).thenAnswer((_) async => intent);

      final task = Task(
        id: 'task-789',
        userId: 'user-1',
        title: 'Doctor Appointment',
        category: TaskCategory.personal,
        status: TaskStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        transcription: 'Doctor Appointment',
        aiPlacement: const AIPlacement(confidence: 0.9, reasoning: 'test'),
      );

      when(mockTaskRepository.getTasksByCategory(TaskCategory.work))
          .thenAnswer((_) async => []);
      when(mockTaskRepository.getTasksByCategory(TaskCategory.personal))
          .thenAnswer((_) async => [task]);

      when(mockTaskRepository.updateTask(
        'task-789',
        dueDate: anyNamed('dueDate'),
      )).thenAnswer((_) async => {});

      // Act
      final response = await agentService.processVoiceCommand(audioPath);

      // Assert
      expect(response.success, isTrue);
      expect(response.message, contains('Updated'));
      expect(response.data?['taskId'], 'task-789');

      verify(mockTaskRepository.updateTask(
        'task-789',
        dueDate: anyNamed('dueDate'),
      )).called(1);
    });
  });

  group('AgentService - QUERY Intent', () {
    test('should return task count and list', () async {
      // Arrange
      const audioPath = '/path/to/audio.m4a';
      const transcription = 'Show my work tasks';

      when(mockGeminiService.transcribeAudio(audioPath))
          .thenAnswer((_) async => transcription);

      final intent = AgentIntent(
        intent: IntentType.query,
        confidence: 0.94,
        parameters: {
          'filters': {
            'category': 'work',
          },
        },
      );
      when(mockGeminiService.detectIntent(
        transcription: transcription,
        taskTree: anyNamed('taskTree'),
      )).thenAnswer((_) async => intent);

      final tasks = [
        Task(
          id: 'task-1',
          userId: 'user-1',
          title: 'Project Alpha',
          category: TaskCategory.work,
          status: TaskStatus.active,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transcription: 'Project Alpha',
          aiPlacement: const AIPlacement(confidence: 0.9, reasoning: 'test'),
        ),
        Task(
          id: 'task-2',
          userId: 'user-1',
          title: 'Backend API',
          category: TaskCategory.work,
          status: TaskStatus.active,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          transcription: 'Backend API',
          aiPlacement: const AIPlacement(confidence: 0.9, reasoning: 'test'),
        ),
      ];

      when(mockTaskRepository.getTasksByCategory(TaskCategory.work))
          .thenAnswer((_) async => tasks);
      when(mockTaskRepository.getTasksByCategory(TaskCategory.personal))
          .thenAnswer((_) async => []);

      // Act
      final response = await agentService.processVoiceCommand(audioPath);

      // Assert
      expect(response.success, isTrue);
      expect(response.message, contains('2'));
      expect(response.message, contains('work'));
      expect(response.data?['count'], 2);
    });
  });
}
