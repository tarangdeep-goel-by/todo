import 'package:dio/dio.dart';
import '../models/task.dart';
import '../models/api_response.dart';
import '../config/constants.dart';

/// Service for backend API communication
class ApiService {
  final Dio _dio;

  ApiService({String? baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl ?? AppConstants.apiBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ));

  /// Get all tasks for user
  Future<List<Task>> getTasks(String userId) async {
    try {
      final response = await _dio.get('/tasks', queryParameters: {
        'user_id': userId,
      });

      final taskListResponse = TaskListResponse.fromJson(response.data);
      return taskListResponse.tasks;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get tasks by category
  Future<List<Task>> getTasksByCategory(String userId, String category) async {
    try {
      final response = await _dio.get('/tasks', queryParameters: {
        'user_id': userId,
        'category': category,
      });

      return (response.data as List).map((json) => Task.fromJson(json)).toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Process voice command with audio file
  Future<AgentResponse> processVoiceCommand(String audioPath, String userId) async {
    try {
      final formData = FormData.fromMap({
        'audio': await MultipartFile.fromFile(
          audioPath,
          filename: 'voice.m4a',
        ),
        'user_id': userId,
      });

      final response = await _dio.post('/agent/process', data: formData);
      return AgentResponse.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Create task manually
  Future<Task> createTask(CreateTaskRequest request) async {
    try {
      final response = await _dio.post('/tasks', data: request.toJson());
      return Task.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Update task (complete, edit, etc.)
  Future<Task> updateTask(String taskId, UpdateTaskRequest request) async {
    try {
      final response = await _dio.patch('/tasks/$taskId', data: request.toJson());
      return Task.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Delete task
  Future<void> deleteTask(String taskId) async {
    try {
      await _dio.delete('/tasks/$taskId');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Handle Dio errors
  String _handleError(DioException e) {
    if (e.response != null) {
      return e.response!.data['detail'] ?? 'Server error occurred';
    } else if (e.type == DioExceptionType.connectionTimeout) {
      return 'Connection timeout';
    } else if (e.type == DioExceptionType.receiveTimeout) {
      return 'Receive timeout';
    } else {
      return 'Network error occurred';
    }
  }
}
