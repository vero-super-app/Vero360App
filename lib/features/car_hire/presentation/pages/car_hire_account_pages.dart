import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_company_models.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_browse_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_company_page.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_company_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_skeletons.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/features/car_hire/utils/car_hire_routes.dart';

/// Car hire entry point. A live car hire account lands on its company home;
/// everyone else lands on the renter marketplace.
///
/// The destination is resolved once, behind a single skeleton shell, so
/// opening car hire never shows two stacked loading screens.
class CarHireHomePage extends ConsumerWidget {
  const CarHireHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(carHireEntryProvider);

    // Keep the last resolved destination while refreshing: the entry must
    // never bounce back to a loader once the user is already inside.
    final destination = entry.value;
    if (destination != null) {
      return switch (destination) {
        CarHireEntryDestination.company => const CarHireCompanyPage(
          asHome: true,
        ),
        CarHireEntryDestination.marketplace => const CarHireBrowsePage(),
      };
    }

    // Once the account is known to be a live company — or the login is a
    // member of one — the remaining wait is the membership lookup, so show
    // the dashboard's own skeleton instead of a generic one. Both share the
    // same frame, so the switch is quiet.
    final expectsCompany =
        (ref.watch(carHireAccountProvider).value?.isActive ?? false) ||
        (ref.watch(companyAccessProvider).value?.hasCompany ?? false);

    return Scaffold(
      backgroundColor: CarHirePalette.background,
      appBar: carHireAppBar(
        title: 'Car hire',
        subtitle: 'Rent a car or earn with yours',
      ),
      body: Semantics(
        label: 'Opening car hire',
        container: true,
        child: ExcludeSemantics(
          child: expectsCompany
              ? const SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 32),
                  child: CarHireCompanyDashboardSkeleton(),
                )
              : const CarHireEntrySkeleton(),
        ),
      ),
    );
  }
}

/// Status strip shown on the marketplace for accounts that are not live yet,
/// and a "list your cars" invitation for renters.
class CarHireAccountBanner extends ConsumerWidget {
  const CarHireAccountBanner({super.key, this.renterInvite = false});

  /// When true, renders only the invitation for accounts without a profile.
  final bool renterInvite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(carHireAccountProvider).value;
    if (account == null) return const SizedBox.shrink();

    if (renterInvite) {
      if (account.hasProfile) return const SizedBox.shrink();
      return const _PartnerInviteCard();
    }

    final copy = _statusCopy(account);
    if (copy == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: _BannerTap(
        onTap: () => CarHireRoutes.openAccountStatus(context),
        child: CarHireInfoBanner(
          icon: copy.icon,
          title: copy.title,
          message: copy.short,
          tone: copy.tone,
        ),
      ),
    );
  }
}

/// Persistent "Rent out your cars" card for accounts without a profile.
///
/// Unlike the old one-time sheet, this stays available on the marketplace so
/// a new car hire owner can always find the way in.
class _PartnerInviteCard extends StatelessWidget {
  const _PartnerInviteCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Material(
        color: CarHirePalette.accentPale,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => CarHireRoutes.openPartner(context),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: CarHirePalette.accentSoft),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: CarHirePalette.surface,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add_road_rounded,
                    size: 19,
                    color: CarHirePalette.accent,
                  ),
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Have a car? List it on Vero360',
                        style: TextStyle(
                          color: CarHirePalette.onAccentSoft,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.1,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Company or private owner · verified renters · '
                        'wallet payouts',
                        style: TextStyle(
                          color: CarHirePalette.onAccentSoft,
                          fontSize: 10.8,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_rounded,
                  size: 17,
                  color: CarHirePalette.onAccentSoft,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BannerTap extends StatelessWidget {
  const _BannerTap({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: child,
      ),
    );
  }
}

class _StatusCopy {
  const _StatusCopy({
    required this.icon,
    required this.title,
    required this.short,
    required this.long,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String short;
  final String long;
  final CarHireInfoTone tone;
}

_StatusCopy? _statusCopy(CarHireAccount account) {
  final name = account.companyName.isEmpty
      ? 'Your company'
      : account.companyName;
  switch (account.state) {
    case CarHireAccountState.inReview:
      return _StatusCopy(
        icon: Icons.hourglass_top_rounded,
        title: 'Application under review',
        short: '$name is being reviewed by Vero360. Tap for details.',
        long:
            'Vero360 is checking $name. Once approved, opening Car hire '
            'takes you straight to your company home to add cars and manage '
            'bookings.',
        tone: CarHireInfoTone.accent,
      );
    case CarHireAccountState.needsInformation:
      return _StatusCopy(
        icon: Icons.edit_note_rounded,
        title: 'Vero360 needs more information',
        short: 'Update your details to continue the review.',
        long:
            'Vero360 needs a few changes before approving $name. Update '
            'your details and the application goes back into review.',
        tone: CarHireInfoTone.warning,
      );
    case CarHireAccountState.rejected:
      return _StatusCopy(
        icon: Icons.block_rounded,
        title: 'Application not approved',
        short: 'See why and apply again.',
        long:
            '$name was not approved. Read the note below, fix what is '
            'needed and apply again.',
        tone: CarHireInfoTone.error,
      );
    case CarHireAccountState.suspended:
      return _StatusCopy(
        icon: Icons.pause_circle_outline_rounded,
        title: '$name is suspended',
        short: 'Your cars are hidden from renters. Tap for details.',
        long:
            'Your cars are hidden from renters and new bookings are '
            'paused. Contact Vero360 support to restore $name.',
        tone: CarHireInfoTone.error,
      );
    case CarHireAccountState.none:
    case CarHireAccountState.active:
      return null;
  }
}

/// Explains where the account stands and offers the next step.
class CarHireAccountStatusPage extends ConsumerWidget {
  const CarHireAccountStatusPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(carHireAccountProvider);
    return Scaffold(
      backgroundColor: CarHirePalette.background,
      appBar: carHireAppBar(
        title: 'Car hire account',
        subtitle: 'Application status',
      ),
      body: async.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        skipError: true,
        loading: () => Semantics(
          label: 'Checking car hire account',
          container: true,
          child: const ExcludeSemantics(
            child: CarHireAccountStatusSkeleton(),
          ),
        ),
        error: (error, _) => CarHireErrorState(
          error: error,
          onRetry: () => ref.invalidate(carHireAccountProvider),
        ),
        data: (account) {
          if (account.isActive) {
            return CarHireEmptyState(
              icon: Icons.verified_rounded,
              title: '${account.companyName} is live',
              message:
                  'Your company is approved. Open your company home to '
                  'manage cars and bookings.',
              actionLabel: 'Open company home',
              onAction: () => CarHireRoutes.openCompany(context),
            );
          }
          final copy = _statusCopy(account);
          if (copy == null) {
            return CarHireEmptyState(
              icon: Icons.add_business_outlined,
              title: 'No car hire account yet',
              message: 'Apply to list your cars on Vero360.',
              actionLabel: 'Get started',
              onAction: () => CarHireRoutes.openPartner(context),
            );
          }
          final note = account.reviewerNote?.trim() ?? '';
          return RefreshIndicator(
            color: CarHirePalette.accent,
            onRefresh: () async {
              ref.invalidate(carHireAccountProvider);
              await ref.read(carHireAccountProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                CarHireInfoBanner(
                  icon: copy.icon,
                  title: copy.title,
                  message: copy.long,
                  tone: copy.tone,
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  CarHireSurface(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Note from Vero360',
                          style: CarHireType.subtitle,
                        ),
                        const SizedBox(height: 6),
                        Text(note, style: CarHireType.bodySmall),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _DetailsCard(account: account),
                const SizedBox(height: 18),
                if (account.state == CarHireAccountState.needsInformation)
                  FilledButton(
                    onPressed: () =>
                        CarHireRoutes.openApply(context, existing: account),
                    style: carHirePrimaryButton(),
                    child: const Text('Update details'),
                  ),
                if (account.state == CarHireAccountState.rejected)
                  FilledButton(
                    onPressed: () =>
                        CarHireRoutes.openApply(context, existing: account),
                    style: carHirePrimaryButton(),
                    child: const Text('Apply again'),
                  ),
                if (account.state == CarHireAccountState.inReview)
                  const Text(
                    'Pull down to check for updates.',
                    textAlign: TextAlign.center,
                    style: CarHireType.labelSmall,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.account});

  final CarHireAccount account;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(label, style: CarHireType.labelSmall),
            ),
            Expanded(
              child: Text(
                value.isEmpty ? 'â€”' : value,
                style: const TextStyle(
                  color: CarHirePalette.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return CarHireSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          row('Name', account.companyName),
          row('Account type', account.isBusiness ? 'Company' : 'Individual'),
          row('Phone', account.contactPhone ?? ''),
          row('Service areas', account.serviceAreas.join(', ')),
        ],
      ),
    );
  }
}
