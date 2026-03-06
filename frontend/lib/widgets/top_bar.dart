import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/theme.dart';
import '../providers/connectivity_provider.dart';
import '../providers/local_data_provider.dart';
import '../providers/task_store_provider.dart';

/// Top bar with app name, offline chip, and pending sync badge.
class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);

    return Container(
      height: AppSpacing.topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          Text(
            'Amble',
            style: AppTypography.ctaLabelText(
              color: AppColors.darkText,
            ).copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          if (!isOnline) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.darkText.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 12,
                    color: AppColors.darkText.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Offline',
                    style: AppTypography.metadataText(
                      color: AppColors.darkText.withValues(alpha: 0.5),
                    ).copyWith(fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          const _PendingSyncBadge(),
        ],
      ),
    );
  }
}

class _PendingSyncBadge extends ConsumerStatefulWidget {
  const _PendingSyncBadge();

  @override
  ConsumerState<_PendingSyncBadge> createState() => _PendingSyncBadgeState();
}

class _PendingSyncBadgeState extends ConsumerState<_PendingSyncBadge> {
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final localDb = ref.read(localDataServiceProvider);
    final count = await localDb.pendingMutationCount();
    if (mounted && count != _pendingCount) {
      setState(() => _pendingCount = count);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    // Re-check count when online status or task store changes (sync completed)
    ref.listen(isOnlineProvider, (_, _) => _refresh());
    ref.listen(taskStoreProvider, (_, _) => _refresh());

    if (_pendingCount == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.priorityMedium.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sync_rounded,
            size: 12,
            color: AppColors.priorityMedium,
          ),
          const SizedBox(width: 4),
          Text(
            '$_pendingCount pending',
            style: AppTypography.metadataText(
              color: AppColors.priorityMedium,
            ).copyWith(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
