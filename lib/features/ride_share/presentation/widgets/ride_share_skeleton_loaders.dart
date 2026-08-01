import 'package:flutter/material.dart';
import 'package:vero360_app/widgets/app_skeleton.dart';

/// VeroRide skeleton palette — warm neutrals that pair with brand orange.
class RideShareSkeleton {
  RideShareSkeleton._();

  static const Color bone = Color(0xFFE2E6EF);
  static const Color boneLight = Color(0xFFF0F2F6);
  static const Color cardBg = Colors.white;
  static const Color border = Color(0xFFE2E6EF);
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.child, this.padding = const EdgeInsets.all(14)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: RideShareSkeleton.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RideShareSkeleton.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Bottom sheet on [DriverDashboard] while driver profile loads.
class DriverDashboardSheetSkeleton extends StatelessWidget {
  const DriverDashboardSheetSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppSkeletonShimmer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SkeletonCard(
              child: Row(
                children: [
                  AppSkeletonBox(
                    width: 64,
                    height: 64,
                    radius: 32,
                    color: RideShareSkeleton.bone,
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppSkeletonBox(
                          height: 16,
                          width: 140,
                          radius: 6,
                          color: RideShareSkeleton.bone,
                        ),
                        SizedBox(height: 10),
                        AppSkeletonBox(
                          height: 22,
                          width: 88,
                          radius: 12,
                          color: RideShareSkeleton.boneLight,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AppSkeletonBox(
                    height: 72,
                    radius: 12,
                    color: RideShareSkeleton.bone,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppSkeletonBox(
                    height: 72,
                    radius: 12,
                    color: RideShareSkeleton.bone,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const AppSkeletonBox(
              height: 14,
              width: 100,
              radius: 5,
              color: RideShareSkeleton.bone,
            ),
            const SizedBox(height: 12),
            const AppSkeletonBox(
              height: 48,
              radius: 12,
              color: RideShareSkeleton.bone,
            ),
            const SizedBox(height: 10),
            const AppSkeletonBox(
              height: 48,
              radius: 12,
              color: RideShareSkeleton.bone,
            ),
            const SizedBox(height: 10),
            AppSkeletonBox(
              height: 48,
              radius: 12,
              color: RideShareSkeleton.bone.withValues(alpha: 0.85),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trip history / trip earnings screen initial load.
class RideHistoryScreenSkeleton extends StatelessWidget {
  const RideHistoryScreenSkeleton({super.key, this.showDriverEarnings = false});

  final bool showDriverEarnings;

  @override
  Widget build(BuildContext context) {
    return AppSkeletonShimmer(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (showDriverEarnings) ...[
            const _DriverEarningsCardSkeleton(),
            const SizedBox(height: 12),
          ],
          const _HistorySummarySkeleton(),
          const SizedBox(height: 12),
          const _HistoryFilterSkeleton(),
          const SizedBox(height: 16),
          for (var i = 0; i < 4; i++) ...[
            const _RideHistoryTripCardSkeleton(),
            if (i < 3) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _DriverEarningsCardSkeleton extends StatelessWidget {
  const _DriverEarningsCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF16284C),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSkeletonBox(
            height: 12,
            width: 100,
            radius: 5,
            color: Color(0xFF2A3A5C),
          ),
          SizedBox(height: 10),
          AppSkeletonBox(
            height: 32,
            width: 160,
            radius: 8,
            color: Color(0xFF2A3A5C),
          ),
          SizedBox(height: 6),
          AppSkeletonBox(
            height: 10,
            width: 72,
            radius: 4,
            color: Color(0xFF2A3A5C),
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppSkeletonBox(
                  height: 56,
                  radius: 12,
                  color: Color(0xFF2A3A5C),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: AppSkeletonBox(
                  height: 56,
                  radius: 12,
                  color: Color(0xFF2A3A5C),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: AppSkeletonBox(
                  height: 56,
                  radius: 12,
                  color: Color(0xFF2A3A5C),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistorySummarySkeleton extends StatelessWidget {
  const _HistorySummarySkeleton();

  @override
  Widget build(BuildContext context) {
    return const _SkeletonCard(
      padding: EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Row(
        children: [
          Expanded(child: _SummaryStatSkeleton()),
          _VerticalDividerSkeleton(),
          Expanded(child: _SummaryStatSkeleton()),
          _VerticalDividerSkeleton(),
          Expanded(child: _SummaryStatSkeleton()),
        ],
      ),
    );
  }
}

class _SummaryStatSkeleton extends StatelessWidget {
  const _SummaryStatSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        AppSkeletonBox(
          width: 22,
          height: 22,
          radius: 11,
          color: RideShareSkeleton.bone,
        ),
        SizedBox(height: 8),
        AppSkeletonBox(
          height: 14,
          width: 48,
          radius: 5,
          color: RideShareSkeleton.bone,
        ),
        SizedBox(height: 6),
        AppSkeletonBox(
          height: 10,
          width: 56,
          radius: 4,
          color: RideShareSkeleton.boneLight,
        ),
      ],
    );
  }
}

class _VerticalDividerSkeleton extends StatelessWidget {
  const _VerticalDividerSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: RideShareSkeleton.border,
    );
  }
}

class _HistoryFilterSkeleton extends StatelessWidget {
  const _HistoryFilterSkeleton();

  @override
  Widget build(BuildContext context) {
    return const _SkeletonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSkeletonBox(
            height: 14,
            width: 110,
            radius: 5,
            color: RideShareSkeleton.bone,
          ),
          SizedBox(height: 10),
          AppSkeletonBox(
            height: 46,
            width: double.infinity,
            radius: 12,
            color: RideShareSkeleton.boneLight,
          ),
          SizedBox(height: 12),
          Row(
            children: [
              AppSkeletonBox(
                height: 32,
                width: 52,
                radius: 16,
                color: RideShareSkeleton.bone,
              ),
              SizedBox(width: 8),
              AppSkeletonBox(
                height: 32,
                width: 88,
                radius: 16,
                color: RideShareSkeleton.boneLight,
              ),
              SizedBox(width: 8),
              AppSkeletonBox(
                height: 32,
                width: 80,
                radius: 16,
                color: RideShareSkeleton.boneLight,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RideHistoryTripCardSkeleton extends StatelessWidget {
  const _RideHistoryTripCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const _SkeletonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSkeletonBox(
                width: 44,
                height: 44,
                radius: 12,
                color: RideShareSkeleton.bone,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSkeletonBox(
                      height: 14,
                      width: double.infinity,
                      radius: 6,
                      color: RideShareSkeleton.bone,
                    ),
                    SizedBox(height: 8),
                    AppSkeletonBox(
                      height: 11,
                      width: 120,
                      radius: 4,
                      color: RideShareSkeleton.boneLight,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AppSkeletonBox(
                    height: 14,
                    width: 72,
                    radius: 5,
                    color: RideShareSkeleton.bone,
                  ),
                  SizedBox(height: 8),
                  AppSkeletonBox(
                    height: 20,
                    width: 48,
                    radius: 10,
                    color: RideShareSkeleton.boneLight,
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: 12),
          AppSkeletonBox(
            height: 10,
            width: double.infinity,
            radius: 4,
            color: RideShareSkeleton.boneLight,
          ),
        ],
      ),
    );
  }
}

/// Driver Center — profile tab loading.
class DriverCenterProfileTabSkeleton extends StatelessWidget {
  const DriverCenterProfileTabSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppSkeletonShimmer(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: const [
          _SkeletonCard(
            child: Row(
              children: [
                AppSkeletonBox(
                  width: 64,
                  height: 64,
                  radius: 32,
                  color: RideShareSkeleton.bone,
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSkeletonBox(
                        height: 16,
                        width: 150,
                        radius: 6,
                        color: RideShareSkeleton.bone,
                      ),
                      SizedBox(height: 8),
                      AppSkeletonBox(
                        height: 11,
                        width: 80,
                        radius: 4,
                        color: RideShareSkeleton.boneLight,
                      ),
                      SizedBox(height: 10),
                      AppSkeletonBox(
                        height: 22,
                        width: 120,
                        radius: 12,
                        color: RideShareSkeleton.boneLight,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12),
          _HistorySummarySkeleton(),
          SizedBox(height: 16),
          _InfoSectionSkeleton(lines: 4),
          SizedBox(height: 12),
          _InfoSectionSkeleton(lines: 3),
          SizedBox(height: 20),
          AppSkeletonBox(
            height: 48,
            width: double.infinity,
            radius: 12,
            color: RideShareSkeleton.bone,
          ),
        ],
      ),
    );
  }
}

/// Driver Center — vehicle tab loading.
class DriverCenterVehicleTabSkeleton extends StatelessWidget {
  const DriverCenterVehicleTabSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppSkeletonShimmer(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: const [
          AppSkeletonBox(
            height: 16,
            width: 180,
            radius: 6,
            color: RideShareSkeleton.bone,
          ),
          SizedBox(height: 6),
          AppSkeletonBox(
            height: 12,
            width: double.infinity,
            radius: 4,
            color: RideShareSkeleton.boneLight,
          ),
          SizedBox(height: 14),
          _VehicleCardSkeleton(),
        ],
      ),
    );
  }
}

class _InfoSectionSkeleton extends StatelessWidget {
  const _InfoSectionSkeleton({required this.lines});

  final int lines;

  @override
  Widget build(BuildContext context) {
    return _SkeletonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSkeletonBox(
            height: 14,
            width: 130,
            radius: 5,
            color: RideShareSkeleton.bone,
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < lines; i++) ...[
            Row(
              children: [
                AppSkeletonBox(
                  height: 11,
                  width: 90,
                  radius: 4,
                  color: RideShareSkeleton.boneLight,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppSkeletonBox(
                    height: 11,
                    width: double.infinity,
                    radius: 4,
                    color: RideShareSkeleton.bone,
                  ),
                ),
              ],
            ),
            if (i < lines - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _VehicleCardSkeleton extends StatelessWidget {
  const _VehicleCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const _SkeletonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppSkeletonBox(
                width: 44,
                height: 44,
                radius: 12,
                color: RideShareSkeleton.bone,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSkeletonBox(
                      height: 14,
                      width: 140,
                      radius: 6,
                      color: RideShareSkeleton.bone,
                    ),
                    SizedBox(height: 8),
                    AppSkeletonBox(
                      height: 11,
                      width: 80,
                      radius: 4,
                      color: RideShareSkeleton.boneLight,
                    ),
                  ],
                ),
              ),
              AppSkeletonBox(
                height: 22,
                width: 64,
                radius: 12,
                color: RideShareSkeleton.boneLight,
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              AppSkeletonBox(
                height: 28,
                width: 72,
                radius: 8,
                color: RideShareSkeleton.boneLight,
              ),
              SizedBox(width: 8),
              AppSkeletonBox(
                height: 28,
                width: 64,
                radius: 8,
                color: RideShareSkeleton.boneLight,
              ),
            ],
          ),
          SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: AppSkeletonBox(
                  height: 32,
                  radius: 8,
                  color: RideShareSkeleton.boneLight,
                ),
              ),
              SizedBox(width: 12),
              AppSkeletonBox(
                height: 32,
                width: 64,
                radius: 8,
                color: RideShareSkeleton.bone,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact earnings card skeleton while summary API is still loading.
class DriverEarningsCardSkeleton extends StatelessWidget {
  const DriverEarningsCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppSkeletonShimmer(child: _DriverEarningsCardSkeleton());
  }
}
