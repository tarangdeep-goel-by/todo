import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/task.dart';
import '../models/api_response.dart';
import '../models/category.dart';
import '../config/constants.dart';

/// Service for backend API communication
class ApiService {
  final Dio _dio;

  ApiService({String? baseUrl, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl ?? AppConstants.apiBaseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 15),
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

  /// Process voice command with transcribed text
  Future<AgentResponse> processVoiceCommand(String transcription, String userId) async {
    try {
      final response = await _dio.post('/agent/process', data: {
        'transcription': transcription,
        'user_id': userId,
      });
      return AgentResponse.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Resolve a question response (user picked an option)
  Future<AgentResponse> resolveQuestion({
    required String userId,
    required String action,
    String? selectedTaskId,
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await _dio.post('/agent/resolve', data: {
        'user_id': userId,
        'action': action,
        'selected_task_id': ?selectedTaskId,
        'data': ?data,
      });
      return AgentResponse.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Process brain dump — extract task proposals from voice transcription
  Future<BrainDumpResponse> processBrainDump({
    required String transcription,
    required String userId,
    String? category,
    String? parentId,
  }) async {
    try {
      final data = <String, dynamic>{
        'transcription': transcription,
        'user_id': userId,
      };
      if (category != null) data['category'] = category;
      if (parentId != null) data['parent_id'] = parentId;
      final response = await _dio.post('/agent/braindump', data: data);
      return BrainDumpResponse.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Submit reviewed brain dump tasks
  Future<BrainDumpSubmitResponse> submitBrainDump({
    required String userId,
    required List<BrainDumpTaskProposal> tasks,
  }) async {
    try {
      final payload = {
        'user_id': userId,
        'tasks': tasks.map((t) => t.toJson()).toList(),
      };
      debugPrint('[API] submitBrainDump POST /agent/braindump/submit payload=${tasks.length} tasks');
      debugPrint('[API] submitBrainDump baseUrl=${_dio.options.baseUrl}');
      final response = await _dio.post('/agent/braindump/submit', data: payload);
      debugPrint('[API] submitBrainDump response status=${response.statusCode}');
      return BrainDumpSubmitResponse.fromJson(response.data);
    } on DioException catch (e) {
      debugPrint('[API] submitBrainDump DioException type=${e.type} message=${e.message}');
      debugPrint('[API] submitBrainDump response=${e.response?.statusCode} data=${e.response?.data}');
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

  /// Complete task (cascades to all descendants via PUT endpoint)
  Future<Task> completeTask(String taskId) async {
    try {
      final response = await _dio.put('/tasks/$taskId/complete');
      return Task.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Delete task
  Future<void> deleteTask(String taskId, {String userId = AppConstants.defaultUserId}) async {
    try {
      await _dio.delete('/tasks/$taskId', queryParameters: {
        'user_id': userId,
      });
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get categories for user
  Future<List<Category>> getCategories(String userId) async {
    try {
      final response = await _dio.get('/categories', queryParameters: {
        'user_id': userId,
      });
      return (response.data as List)
          .map((json) => Category.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Create a new category
  Future<Category> createCategory(String userId, String name) async {
    try {
      final response = await _dio.post('/categories', data: {
        'user_id': userId,
        'name': name,
      });
      return Category.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Delete a category
  Future<void> deleteCategory(String categoryId, {String userId = AppConstants.defaultUserId}) async {
    try {
      await _dio.delete('/categories/$categoryId', queryParameters: {
        'user_id': userId,
      });
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Handle Dio errors
  String _handleError(DioException e) {
    if (e.response != null) {
      final detail = e.response!.data['detail'];
      if (detail is String) return detail;
      if (detail is List) return detail.map((d) => d['msg'] ?? d.toString()).join(', ');
      return 'Server error occurred';
    } else if (e.type == DioExceptionType.connectionTimeout) {
      return 'Connection timeout';
    } else if (e.type == DioExceptionType.receiveTimeout) {
      return 'Receive timeout';
    } else {
      return 'Network error occurred';
    }
  }
}
