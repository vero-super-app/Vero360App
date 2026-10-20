import 'package:flutter/material.dart';

import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/widgets/app_skeleton.dart';

/// Car-hire skeleton palette: warm bone tones that sit on the warm off-white
/// page instead of the cool grey used by the general marketplace skeletons.
class CarHireSkeleton {
  CarHireSkeleton._();

  static const List<Color> shimmer = <Color>[
    Color(0xFFEDE7E4),
    Color(0xFFF8F4F1),
    Color(0xFFEDE7E4),
  ];

  static const Color bone = Color(0xFFE9E3E0);
  static const Color boneLight = Color(0xFFF1EBE8);
  static const Color card = CarHirePalette.surface;
}

/// One shimmer wrapper per section, matching the real section's geometry.
class _SectionShimmer extends StatelessWidget {
  const _SectionShimmer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppSkeletonShimmer(colors: CarHireSkeleton.shimmer, child: child);
  }
}

/// Company rail placeholder: one circle and two lines per company.
class CarHireCompanyRailSkeleton extends StatelessWidget {
  const CarHireCompanyRailSkeleton({super.key, this.count = 5});

  final int count;

  @override
  Widget build(BuildContext context) {
    return _SectionShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: AppSkeletonBox(
              height: 14,
              width: 96,
              radius: 6,
              color: CarHireSkeleton.bone,
            ),
          ),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: count,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, _) => const SizedBox(
                width: 70,
                child: Column(
                  children: [
                    AppSkeletonBox(
                      width: 56,
                      height: 56,
                      radius: 28,
                      color: CarHireSkeleton.bone,
                    ),
                    SizedBox(height: 8),
                    AppSkeletonBox(
                      height: 9,
                      width: 56,
                      radius: 4,
                      color: CarHireSkeleton.boneLight,
                    ),
                    SizedBox(height: 5),
                    AppSkeletonBox(
                      height: 8,
                      width: 34,
                      radius: 4,
                      color: CarHireSkeleton.boneLight,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Category chip rail placeholder.
class CarHireFacetChipSkeleton extends StatelessWidget {
  const CarHireFacetChipSkeleton({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) {
    return _SectionShimmer(
      child: SizedBox(
        height: 66,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          itemCount: count,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, index) => AppSkeletonBox(
            height: 38,
            width: index == 0 ? 92 : 78,
            radius: 19,
            color: CarHireSkeleton.bone,
          ),
        ),
      ),
    );
  }
}

/// Result summary line placeholder ("12 cars available" + sort control).
class CarHireResultsHeaderSkeleton extends StatelessWidget {
  const CarHireResultsHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _SectionShimmer(
      child: const Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: AppSkeletonBox(
                height: 15,
                width: 130,
                radius: 6,
                color: CarHireSkeleton.bone,
              ),
            ),
            AppSkeletonBox(
              height: 13,
              width: 78,
              radius: 6,
              color: CarHireSkeleton.boneLight,
            ),
          ],
        ),
      ),
    );
  }
}

/// One listing card placeholder: 190px image with the real card's text lines.
class CarHireListingCardSkeleton extends StatelessWidget {
  const CarHireListingCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 190,
          decoration: BoxDecoration(
            color: CarHireSkeleton.bone,
            borderRadius: BorderRadius.circular(CarHireShape.cardRadius),
          ),
        ),
        const SizedBox(height: 12),
        const AppSkeletonBox(
          height: 15,
          width: 180,
          radius: 6,
          color: CarHireSkeleton.bone,
        ),
        const SizedBox(height: 8),
        const AppSkeletonBox(
          height: 11,
          width: 120,
          radius: 5,
          color: CarHireSkeleton.boneLight,
        ),
        const SizedBox(height: 6),
        const AppSkeletonBox(
          height: 11,
          width: 210,
          radius: 5,
          color: CarHireSkeleton.boneLight,
        ),
        const SizedBox(height: 10),
        const AppSkeletonBox(
          height: 13,
          width: 140,
          radius: 5,
          color: CarHireSkeleton.bone,
        ),
      ],
    );
  }
}

/// Result card list placeholder, one shimmer for the whole list.
class CarHireListingListSkeleton extends StatelessWidget {
  const CarHireListingListSkeleton({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return _SectionShimmer(
      child: Column(
        children: [
          for (var index = 0; index < count; index++)
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                index == 0 ? 4 : 0,
                16,
                index == count - 1 ? 8 : 20,
              ),
              child: const CarHireListingCardSkeleton(),
            ),
        ],
      ),
    );
  }
}

/// Small pill placeholder used by the detail availability row.
class CarHireAvailabilityPillSkeleton extends StatelessWidget {
  const CarHireAvailabilityPillSkeleton({super.key, this.width = 168});

  final double width;

  @override
  Widget build(BuildContext context) {
    return _SectionShimmer(
      child: AppSkeletonBox(
        height: 28,
        width: width,
        radius: 14,
        color: CarHireSkeleton.bone,
      ),
    );
  }
}

/// Whole vehicle-detail placeholder, only used when no cached car is available.
class CarHireDetailSkeleton extends StatelessWidget {
  const CarHireDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    // Scrollable so the placeholder never overflows on short screens while the
    // vehicle request is still in flight.
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: _SectionShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 264, color: CarHireSkeleton.bone),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: AppSkeletonBox(
                          height: 24,
                          width: 200,
                          radius: 8,
                          color: CarHireSkeleton.bone,
                        ),
                      ),
                      SizedBox(width: 12),
                      AppSkeletonBox(
                        height: 24,
                        width: 64,
                        radius: 12,
                        color: CarHireSkeleton.boneLight,
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  AppSkeletonBox(
                    height: 12,
                    width: 220,
                    radius: 5,
                    color: CarHireSkeleton.boneLight,
                  ),
                  SizedBox(height: 8),
                  AppSkeletonBox(
                    height: 12,
                    width: 160,
                    radius: 5,
                    color: CarHireSkeleton.boneLight,
                  ),
                  SizedBox(height: 18),
                  AppSkeletonBox(
                    height: 74,
                    radius: 20,
                    color: CarHireSkeleton.boneLight,
                  ),
                  SizedBox(height: 16),
                  AppSkeletonBox(
                    height: 96,
                    radius: 20,
                    color: CarHireSkeleton.boneLight,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Company / management pages
// ---------------------------------------------------------------------------

/// Four metric tiles inside a card: the fleet pulse placeholder.
class CarHireCompanyPulseSkeleton extends StatelessWidget {
  const CarHireCompanyPulseSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _SectionShimmer(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: CarHirePalette.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: CarHirePalette.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                AppSkeletonBox(
                  height: 14,
                  width: 88,
                  radius: 5,
                  color: CarHireSkeleton.bone,
                ),
                Spacer(),
                AppSkeletonBox(
                  height: 18,
                  width: 46,
                  radius: 9,
                  color: CarHireSkeleton.boneLight,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 0; i < 4; i++) ...[
                  if (i > 0) const SizedBox(width: 7),
                  const Expanded(
                    child: AppSkeletonBox(
                      height: 52,
                      radius: 11,
                      color: CarHireSkeleton.boneLight,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            const AppSkeletonBox(
              height: 48,
              radius: 12,
              color: CarHireSkeleton.boneLight,
            ),
          ],
        ),
      ),
    );
  }
}

/// Three "needs you today" rows.
class CarHireCompanyOpsRowSkeleton extends StatelessWidget {
  const CarHireCompanyOpsRowSkeleton({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return _SectionShimmer(
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(
                children: [
                  AppSkeletonBox(
                    width: 30,
                    height: 30,
                    radius: 15,
                    color: CarHireSkeleton.bone,
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppSkeletonBox(
                          height: 11,
                          width: 120,
                          radius: 4,
                          color: CarHireSkeleton.bone,
                        ),
                        SizedBox(height: 5),
                        AppSkeletonBox(
                          height: 9,
                          width: 170,
                          radius: 4,
                          color: CarHireSkeleton.boneLight,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8),
                  AppSkeletonBox(
                    height: 22,
                    width: 62,
                    radius: 11,
                    color: CarHireSkeleton.boneLight,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One fleet car card: thumbnail, title, status pill and two actions.
class CarHireCompanyCarCardSkeleton extends StatelessWidget {
  const CarHireCompanyCarCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _SectionShimmer(
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: CarHirePalette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: CarHirePalette.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                AppSkeletonBox(
                  width: 76,
                  height: 60,
                  radius: 10,
                  color: CarHireSkeleton.bone,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSkeletonBox(
                        height: 13,
                        width: 150,
                        radius: 5,
                        color: CarHireSkeleton.bone,
                      ),
                      SizedBox(height: 7),
                      AppSkeletonBox(
                        height: 10,
                        width: 110,
                        radius: 4,
                        color: CarHireSkeleton.boneLight,
                      ),
                      SizedBox(height: 7),
                      AppSkeletonBox(
                        height: 18,
                        width: 130,
                        radius: 9,
                        color: CarHireSkeleton.boneLight,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: const [
                Expanded(
                  child: AppSkeletonBox(
                    height: 34,
                    radius: 17,
                    color: CarHireSkeleton.boneLight,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: AppSkeletonBox(
                    height: 34,
                    radius: 17,
                    color: CarHireSkeleton.boneLight,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dashboard placeholder: header strip, pulse, today's operations and cars.
class CarHireCompanyDashboardSkeleton extends StatelessWidget {
  const CarHireCompanyDashboardSkeleton({super.key, this.cards = 2});

  final int cards;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionShimmer(
          child: Row(
            children: const [
              AppSkeletonBox(
                width: 42,
                height: 42,
                radius: 21,
                color: CarHireSkeleton.bone,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppSkeletonBox(
                      height: 15,
                      width: 130,
                      radius: 5,
                      color: CarHireSkeleton.bone,
                    ),
                    SizedBox(height: 6),
                    AppSkeletonBox(
                      height: 10,
                      width: 96,
                      radius: 4,
                      color: CarHireSkeleton.boneLight,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const CarHireCompanyPulseSkeleton(),
        const SizedBox(height: 18),
        const CarHireCompanyOpsRowSkeleton(),
        const SizedBox(height: 18),
        for (var i = 0; i < cards; i++) const CarHireCompanyCarCardSkeleton(),
      ],
    );
  }
}

/// Two payment-style lines used inside detail sheets.
class CarHireCompanyLineSkeleton extends StatelessWidget {
  const CarHireCompanyLineSkeleton({super.key, this.width = 160});

  final double width;

  @override
  Widget build(BuildContext context) {
    return _SectionShimmer(
      child: AppSkeletonBox(
        height: 12,
        width: width,
        radius: 5,
        color: CarHireSkeleton.boneLight,
      ),
    );
  }
}

/// Fleet page placeholder: stat row and three unit groups.
class CarHireCompanyFleetSkeleton extends StatelessWidget {
  const CarHireCompanyFleetSkeleton({super.key, this.groups = 3});

  final int groups;

  @override
  Widget build(BuildContext context) {
    return _SectionShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: CarHirePalette.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: CarHirePalette.hairline),
            ),
            child: Row(
              children: [
                for (var i = 0; i < 4; i++)
                  const Expanded(
                    child: Column(
                      children: [
                        AppSkeletonBox(
                          height: 17,
                          width: 34,
                          radius: 5,
                          color: CarHireSkeleton.bone,
                        ),
                        SizedBox(height: 5),
                        AppSkeletonBox(
                          height: 9,
                          width: 52,
                          radius: 4,
                          color: CarHireSkeleton.boneLight,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          for (var i = 0; i < groups; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              decoration: BoxDecoration(
                color: CarHirePalette.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: CarHirePalette.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppSkeletonBox(
                    height: 13,
                    width: 160,
                    radius: 5,
                    color: CarHireSkeleton.bone,
                  ),
                  const SizedBox(height: 6),
                  const AppSkeletonBox(
                    height: 9,
                    width: 54,
                    radius: 4,
                    color: CarHireSkeleton.boneLight,
                  ),
                  const SizedBox(height: 10),
                  for (var row = 0; row < 2; row++)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                AppSkeletonBox(
                                  height: 11,
                                  width: 78,
                                  radius: 4,
                                  color: CarHireSkeleton.bone,
                                ),
                                SizedBox(height: 5),
                                AppSkeletonBox(
                                  height: 9,
                                  width: 64,
                                  radius: 4,
                                  color: CarHireSkeleton.boneLight,
                                ),
                              ],
                            ),
                          ),
                          AppSkeletonBox(
                            height: 22,
                            width: 36,
                            radius: 11,
                            color: CarHireSkeleton.boneLight,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Booking inbox placeholder: a stack of rows.
class CarHireCompanyBookingListSkeleton extends StatelessWidget {
  const CarHireCompanyBookingListSkeleton({super.key, this.count = 4});

  final int count;

  @override
  Widget build(BuildContext context) {
    return _SectionShimmer(
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CarHirePalette.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: CarHirePalette.hairline),
              ),
              child: Row(
                children: [
                  const AppSkeletonBox(
                    width: 40,
                    height: 40,
                    radius: 12,
                    color: CarHireSkeleton.bone,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        AppSkeletonBox(
                          height: 12,
                          width: 140,
                          radius: 4,
                          color: CarHireSkeleton.bone,
                        ),
                        SizedBox(height: 6),
                        AppSkeletonBox(
                          height: 9,
                          width: 190,
                          radius: 4,
                          color: CarHireSkeleton.boneLight,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const AppSkeletonBox(
                    height: 20,
                    width: 54,
                    radius: 10,
                    color: CarHireSkeleton.boneLight,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Company booking detail placeholder: summary card and the action buttons.
class CarHireCompanyBookingSkeleton extends StatelessWidget {
  const CarHireCompanyBookingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _SectionShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: CarHirePalette.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: CarHirePalette.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    AppSkeletonBox(
                      height: 20,
                      width: 92,
                      radius: 10,
                      color: CarHireSkeleton.bone,
                    ),
                    SizedBox(width: 6),
                    AppSkeletonBox(
                      height: 20,
                      width: 70,
                      radius: 10,
                      color: CarHireSkeleton.boneLight,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < 6; i++)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 9),
                    child: Row(
                      children: [
                        AppSkeletonBox(
                          height: 10,
                          width: 62,
                          radius: 4,
                          color: CarHireSkeleton.boneLight,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: AppSkeletonBox(
                            height: 11,
                            radius: 4,
                            color: CarHireSkeleton.bone,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const AppSkeletonBox(
            height: 46,
            radius: 23,
            color: CarHireSkeleton.boneLight,
          ),
          const SizedBox(height: 8),
          const AppSkeletonBox(
            height: 42,
            radius: 21,
            color: CarHireSkeleton.boneLight,
          ),
        ],
      ),
    );
  }
}

/// Vehicle workspace placeholder: hero, snapshot, location and reservation.
class CarHireCompanyUnitSkeleton extends StatelessWidget {
  const CarHireCompanyUnitSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _SectionShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSkeletonBox(
            height: 42,
            radius: 13,
            color: CarHireSkeleton.boneLight,
          ),
          const SizedBox(height: 12),
          const AppSkeletonBox(
            height: 176,
            radius: 18,
            color: CarHireSkeleton.bone,
          ),
          const SizedBox(height: 10),
          const AppSkeletonBox(
            height: 14,
            width: 170,
            radius: 5,
            color: CarHireSkeleton.bone,
          ),
          const SizedBox(height: 12),
          const AppSkeletonBox(
            height: 92,
            radius: 16,
            color: CarHireSkeleton.boneLight,
          ),
          const SizedBox(height: 12),
          const AppSkeletonBox(
            height: 96,
            radius: 16,
            color: CarHireSkeleton.boneLight,
          ),
          const SizedBox(height: 12),
          const AppSkeletonBox(
            height: 104,
            radius: 16,
            color: CarHireSkeleton.boneLight,
          ),
        ],
      ),
    );
  }
}

/// Generic list row skeleton for sheet sections (documents, blocks, units).
class CarHireCompanyRowSkeleton extends StatelessWidget {
  const CarHireCompanyRowSkeleton({super.key, this.count = 2});

  final int count;

  @override
  Widget build(BuildContext context) {
    return _SectionShimmer(
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: CarHirePalette.surfaceLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: const [
                  AppSkeletonBox(
                    width: 18,
                    height: 18,
                    radius: 5,
                    color: CarHireSkeleton.bone,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: AppSkeletonBox(
                      height: 11,
                      radius: 4,
                      color: CarHireSkeleton.bone,
                    ),
                  ),
                  SizedBox(width: 10),
                  AppSkeletonBox(
                    width: 48,
                    height: 22,
                    radius: 11,
                    color: CarHireSkeleton.boneLight,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
