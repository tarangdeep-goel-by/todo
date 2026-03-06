import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../providers/connectivity_provider.dart';
import '../providers/task_store_provider.dart';
import '../providers/sync_provider.dart';

class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);
    final storeState = ref.watch(taskStoreProvider);

    // Determine banner state
    String? message;
    IconData? icon;
    if (!isOnline) {
      message = 'No connection — data may be stale';
      icon = Icons.cloud_off;
    } else if (storeState.error != null && storeState.hasLoadedOnce) {
      message = 'Couldn\'t refresh — showing cached data';
      icon = Icons.sync_problem;
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: message == null
          ? const SizedBox.shrink()
          : Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.navBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(icon, color: AppColors.secondaryText, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => ref.read(syncServiceProvider).sync(),
                    child: const Icon(Icons.refresh, color: AppColors.darkText, size: 18),
                  ),
                ],
              ),
            ),
    );
  }
}
