import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../config/spacing.dart';
import '../config/typography.dart';
import '../config/theme.dart';
import '../providers/api_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/local_data_provider.dart';
import '../providers/sync_provider.dart';
import '../providers/task_filter_provider.dart';
import '../providers/task_store_provider.dart';
import '../services/haptic_service.dart';
import '../services/tracker/tracker.dart';
import '../services/tracker/tracker_keys.dart';
import 'archive_screen.dart';

/// Profile screen showing user info and sign out
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Tracker.instance.screenView(screen: 'profile');
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? 'User';
    final email = user?.email ?? '';
    final photoUrl = user?.photoURL;
    final creationTime = user?.metadata.creationTime;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Container(
              height: AppSpacing.topBarHeight,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticService.light();
                      Navigator.of(context).pop();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        color: AppColors.darkText,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Profile',
                    style: AppTypography.ctaLabelText(
                      color: AppColors.darkText,
                    ).copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  children: [
                    const SizedBox(height: AppSpacing.xxl),

                    // Avatar
                    _Avatar(photoUrl: photoUrl, displayName: displayName),
                    const SizedBox(height: AppSpacing.lg),

                    // Name
                    Text(
                      displayName,
                      style: GoogleFonts.bricolageGrotesque(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        color: AppColors.darkText,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs),

                    // Email
                    Text(
                      email,
                      style: AppTypography.ctaLabelText(
                        color: AppColors.secondaryText,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // Member since
                    if (creationTime != null)
                      Text(
                        'Member since ${DateFormat.yMMMM().format(creationTime)}',
                        style: AppTypography.metadataText(
                          color: AppColors.tertiaryText,
                        ).copyWith(
                          fontSize: 13,
                          letterSpacing: 0.3,
                        ),
                      ),

                    const SizedBox(height: AppSpacing.xl),

                    // Archive row
                    GestureDetector(
                      key: TK.archiveLink,
                      onTap: () {
                        HapticService.light();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ArchiveScreen(),
                          ),
                        );
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sm),
                        child: Row(
                          children: [
                            Icon(
                              Icons.archive_outlined,
                              color: AppColors.secondaryText,
                              size: 20,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              'Archive',
                              style: AppTypography.ctaLabelText(
                                color: AppColors.darkText,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.chevron_right,
                              color: AppColors.tertiaryText,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Sign out button
                    GestureDetector(
                      key: TK.signOutButton,
                      onTap: () => _confirmSignOut(context, ref),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.snackbarError.primary
                                .withValues(alpha: 0.3),
                          ),
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusSm),
                        ),
                        child: Text(
                          'Sign out',
                          textAlign: TextAlign.center,
                          style: AppTypography.ctaLabelText(
                            color: AppColors.snackbarError.primary,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.xxl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmSignOut(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navBg,
        title: Text(
          'Sign out?',
          style: TextStyle(color: AppColors.darkText),
        ),
        content: Text(
          'Your tasks will be here when you return.',
          style: TextStyle(color: AppColors.secondaryText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.secondaryText),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop(); // Close profile screen
              // Full cleanup before sign out
              ref.read(syncServiceProvider).stopPeriodicSync();
              ref.invalidate(audioServiceProvider);
              // Clear in-memory state first to prevent flicker on re-login
              ref.read(taskStoreProvider.notifier).state =
                  const TaskStoreState();
              ref.read(categoriesProvider.notifier).state = [];
              await ref.read(localDataServiceProvider).clearAll();
              await ref.read(authServiceProvider).signOut();
              // Invalidate providers to reset state
              ref.invalidate(syncServiceProvider);
              ref.invalidate(taskStoreProvider);
              ref.invalidate(categoriesProvider);
              ref.invalidate(taskFilterProvider);
            },
            child: Text(
              'Sign out',
              style: TextStyle(color: AppColors.snackbarError.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? photoUrl;
  final String displayName;

  const _Avatar({required this.photoUrl, required this.displayName});

  @override
  Widget build(BuildContext context) {
    const size = 88.0;

    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: AppColors.navBg,
        backgroundImage: NetworkImage(photoUrl!),
      );
    }

    // Initials fallback
    final initials = displayName
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: AppColors.navBg,
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: GoogleFonts.bricolageGrotesque(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: AppColors.secondaryText,
        ),
      ),
    );
  }
}
