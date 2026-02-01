import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:todo/screens/home_screen.dart';
import 'package:todo/screens/add_task_screen.dart';
import 'package:todo/screens/task_detail_screen.dart';

/// App routing configuration using GoRouter
class AppRouter {
  // Private constructor
  AppRouter._();

  /// Route paths
  static const String home = '/';
  static const String addTask = '/add-task';
  static const String taskDetail = '/task/:id';

  /// Router instance
  static final GoRouter router = GoRouter(
    initialLocation: home,
    routes: [
      GoRoute(
        path: home,
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: addTask,
        name: 'add-task',
        builder: (context, state) => const AddTaskScreen(),
      ),
      GoRoute(
        path: taskDetail,
        name: 'task-detail',
        builder: (context, state) {
          final taskId = state.pathParameters['id'] ?? '';
          return TaskDetailScreen(taskId: taskId);
        },
      ),
    ],
    errorBuilder: (context, state) {
      return Scaffold(
        body: Center(
          child: Text('Page not found: ${state.uri}'),
        ),
      );
    },
  );
}
