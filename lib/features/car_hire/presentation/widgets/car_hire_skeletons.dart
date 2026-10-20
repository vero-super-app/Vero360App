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
