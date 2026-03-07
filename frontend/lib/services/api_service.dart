import 'package:dio/dio.dart';
import '../models/task.dart';
import '../models/api_response.dart';
import '../models/api_error.dart';
import '../models/category.dart';
import '../config/constants.dart';
import 'auth_interceptor.dart';
import 'api_retry.dart';
import 'app_logger.dart';

/// Service for backend API communication
class ApiService {
  final _logger = AppLogger.instance;
  final Dio _dio;

  /// Exposed for AppLogger log shipping initialization.
  Dio get dio => _dio;

  ApiService({String? baseUrl, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl ?? AppConstants.apiBaseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 15),
            )) {
    // Add auth interceptor unless a custom Dio was provided (tests)
    if (dio == null) {
      final interceptor = AuthInterceptor();
      _dio.interceptors.add(interceptor);
      interceptor.attachDio(_dio);
    }
  }

  /// Get all tasks for user
  Future<List<Task>> getTasks() async {
    try {
      final response = await _dio.get('/tasks');

      final taskListResponse = TaskListResponse.fromJson(response.data);
      return taskListResponse.tasks;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get tasks by category
  Future<TaskListResponse> getTasksByCategory(String category) async {
    try {
      final response = await _dio.get('/tasks', queryParameters: {
        'category': category,
      });

      return TaskListResponse.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get tasks with advanced filtering and sorting
  Future<TaskListResponse> getTasksAdvanced({
    String? category,
    String? priority,
    String? status,
    String? parentId,
    String? tags,
    DateTime? createdAtGte,
    DateTime? createdAtLte,
    DateTime? dueDateGte,
    DateTime? dueDateLte,
    DateTime? updatedAtGte,
    String? sort,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final queryParams = <String, dynamic>{
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
      if (updatedAtGte != null) {
        queryParams['updated_at_gte'] = updatedAtGte.toIso8601String();
      }
      if (sort != null) queryParams['sort'] = sort;

      final response = await _dio.get('/tasks', queryParameters: queryParams);
      return TaskListResponse.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// [getTasksAdvanced] with automatic retry on transient errors.
  Future<TaskListResponse> getTasksAdvancedWithRetry({
    String? category,
    String? priority,
    String? status,
    String? parentId,
    String? tags,
    DateTime? updatedAtGte,
    String? sort,
    int limit = 50,
    int offset = 0,
  }) {
    return retryWithBackoff(() => getTasksAdvanced(
          category: category,
          priority: priority,
          status: status,
          parentId: parentId,
          tags: tags,
          updatedAtGte: updatedAtGte,
          sort: sort,
          limit: limit,
          offset: offset,
        ));
  }

  /// Process brain dump — extract task proposals from voice transcription
  Future<BrainDumpResponse> processBrainDump({
    required String transcription,
    String? category,
    String? parentId,
  }) async {
    return retryWithBackoff(() async {
      try {
        final data = <String, dynamic>{
          'transcription': transcription,
        };
        if (category != null) data['category'] = category;
        if (parentId != null) data['parent_id'] = parentId;
        final response = await _dio.post('/agent/braindump', data: data);
        return BrainDumpResponse.fromJson(response.data);
      } on DioException catch (e) {
        throw _handleError(e);
      }
    });
  }

  /// Submit reviewed brain dump tasks
  Future<BrainDumpSubmitResponse> submitBrainDump({
    required List<BrainDumpTaskProposal> tasks,
  }) async {
    return retryWithBackoff(() async {
      try {
        final payload = {
          'tasks': tasks.map((t) => t.toJson()).toList(),
        };
        _logger.info('braindump.submit', logger: 'ApiService', data: {'task_count': tasks.length});
        final response = await _dio.post('/agent/braindump/submit', data: payload);
        return BrainDumpSubmitResponse.fromJson(response.data);
      } on DioException catch (e) {
        throw _handleError(e);
      }
    });
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
  Future<void> deleteTask(String taskId) async {
    try {
      await _dio.delete('/tasks/$taskId');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get categories for user
  Future<List<Category>> getCategories() async {
    try {
      final response = await _dio.get('/categories');
      return (response.data as List)
          .map((json) => Category.fromJson(json as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Create a new category
  Future<Category> createCategory(String name) async {
    try {
      final response = await _dio.post('/categories', data: {
        'name': name,
      });
      return Category.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Delete a category
  Future<void> deleteCategory(String categoryId) async {
    try {
      await _dio.delete('/categories/$categoryId');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Get archived tasks
  Future<List<Task>> getArchivedTasks({int limit = 50, int offset = 0}) async {
    try {
      final response = await _dio.get('/tasks/archived', queryParameters: {
        'limit': limit,
        'offset': offset,
      });
      final tasks = (response.data['tasks'] as List)
          .map((json) => Task.fromJson(json as Map<String, dynamic>))
          .toList();
      return tasks;
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Restore an archived task
  Future<Task> restoreTask(String taskId) async {
    try {
      final response = await _dio.put('/tasks/$taskId/restore');
      return Task.fromJson(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Permanently delete an archived task
  Future<void> permanentDeleteTask(String taskId) async {
    try {
      await _dio.delete('/tasks/$taskId/permanent');
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Search tasks by query string
  Future<TaskSearchResponse> searchTasks(
    String query, {
    int limit = 10,
  }) async {
    try {
      final response = await _dio.get('/tasks/search', queryParameters: {
        'q': query,
        'limit': limit,
      });
      return TaskSearchResponse.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Register FCM token with backend
  Future<void> registerFcmToken(String token, String platform, String timezone) async {
    try {
      await _dio.post('/notifications/token', data: {
        'token': token,
        'platform': platform,
        'timezone': timezone,
      });
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Unregister FCM token from backend
  Future<void> unregisterFcmToken(String token) async {
    try {
      await _dio.delete('/notifications/token', data: {
        'token': token,
      });
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }

  /// Handle Dio errors — returns structured [ApiError].
  ApiError _handleError(DioException e) {
    if (e.response != null) {
      final statusCode = e.response!.statusCode ?? 500;
      String message;
      try {
        final detail = e.response!.data['detail'];
        if (detail is String) {
          message = detail;
        } else if (detail is List) {
          message = detail.map((d) => d['msg'] ?? d.toString()).join(', ');
        } else {
          message = 'Server error occurred';
        }
      } catch (_) {
        message = 'Server error occurred';
      }

      if (statusCode == 401) {
        return ApiError(message: message, type: ApiErrorType.auth, statusCode: statusCode);
      } else if (statusCode == 400 || statusCode == 422) {
        return ApiError(message: message, type: ApiErrorType.validation, statusCode: statusCode);
      } else {
        return ApiError(message: message, type: ApiErrorType.server, statusCode: statusCode);
      }
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
        return const ApiError(message: 'Connection timeout', type: ApiErrorType.timeout);
      case DioExceptionType.receiveTimeout:
        return const ApiError(message: 'Receive timeout', type: ApiErrorType.timeout);
      default:
        return const ApiError(message: 'Network error occurred', type: ApiErrorType.network);
    }
  }
}
