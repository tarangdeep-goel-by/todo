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
  Future<TaskListResponse> getTasksByCategory(
    String userId,
    String category,
  ) async {
    try {
      final response = await _dio.get('/tasks', queryParameters: {
        'user_id': userId,
        'category': category,
      });

      return TaskListResponse.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get tasks with advanced filtering and sorting
  Future<TaskListResponse> getTasksAdvanced({
    required String userId,
    String? category,
    String? priority,
    String? status,
    String? parentId,
    String? tags,
    DateTime? createdAtGte,
    DateTime? createdAtLte,
    DateTime? dueDateGte,
    DateTime? dueDateLte,
    String? sort,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'user_id': userId,
        'limit': limit,
        'offset': offset,
      };

      if (category != null) queryParams['category'] = category;
      if (priority != null) queryParams['priority'] = priority;
      if (status != null) queryParams['status'] = status;
      if (parentId != null) queryParams['parent_id'] = parentId;
      if (tags != null) queryParams['tags'] = tags;
      if (createdAtGte != null) {
        queryParams['created_at_gte'] = createdAtGte.toIso8601String();
      }
      if (createdAtLte != null) {
        queryParams['created_at_lte'] = createdAtLte.toIso8601String();
      }
      if (dueDateGte != null) {
        queryParams['due_date_gte'] = dueDateGte.toIso8601String();
      }
      if (dueDateLte != null) {
        queryParams['due_date_lte'] = dueDateLte.toIso8601String();
      }
      if (sort != null) queryParams['sort'] = sort;

      final response = await _dio.get('/tasks', queryParameters: queryParams);
      return TaskListResponse.fromJson(response.data);
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
