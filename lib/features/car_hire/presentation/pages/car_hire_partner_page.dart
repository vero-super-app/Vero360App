import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_company_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_company_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/features/car_hire/utils/car_hire_routes.dart';

/// First-comer landing for car hire partners.
///
/// Instead of dropping a brand-new owner straight into a long legal form,
/// this page explains the offer in three steps, lists exactly what is needed,
/// and only then opens the application. Existing partners get a single
/// "continue" action that takes them to their status or dashboard.
class CarHirePartnerPage extends ConsumerWidget {
  const CarHirePartnerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(carHireAccountProvider);
    final account = async.value;
    final hasProfile = account?.hasProfile ?? false;

    return Scaffold(
      backgroundColor: CarHirePalette.background,
      appBar: carHireAppBar(
        title: 'List your car',
        subtitle: 'Earn with Vero360 car hire',
        actions: [
          CarHireIconButton(
            icon: Icons.help_outline_rounded,
            tooltip: 'How it works',
            size: 36,
            iconSize: 18,
            onTap: () => _showHelp(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 150),
        children: [
          const _PartnerHero(),
          const SizedBox(height: 22),
          const CarHireSectionHeader(
            title: 'How it works',
            subtitle: 'Three short steps from application to first booking.',
          ),
          const SizedBox(height: 12),
          const _StepCard(
            number: '1',
            icon: Icons.assignment_outlined,
            title: 'Apply in about 5 minutes',
            body:
                'Tell us who you are, the areas you serve, and whether you '
                'are a company or a private owner.',
          ),
          const SizedBox(height: 10),
          const _StepCard(
            number: '2',
            icon: Icons.verified_user_outlined,
            title: 'Get verified',
            body:
                'Vero360 checks your identity or registration. Most '
                'applications are reviewed within 24 hours.',
          ),
          const SizedBox(height: 10),
          const _StepCard(
            number: '3',
            icon: Icons.add_road_rounded,
            title: 'Add your cars and earn',
            body:
                'Once approved, add a plate, daily rate and photos. Your car '
                'goes live and you manage every booking from your dashboard.',
          ),
          const SizedBox(height: 22),
          const _NeedCard(),
          const SizedBox(height: 16),
          const _ReassuranceCard(),
          const SizedBox(height: 16),
          if (hasProfile) _StatusNote(account: account!),
        ],
      ),
      bottomNavigationBar: _PartnerCta(
        account: account,
        loading: async.isLoading && account == null,
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: CarHirePalette.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: CarHirePalette.outlineVariant,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const Text('Partner questions', style: CarHireType.titleLarge),
                const SizedBox(height: 14),
                const _Faq(
                  question: 'Do I need a registered company?',
                  answer:
                      'No. Private owners can list a car as an individual, '
                      'as long as they can show a valid national ID.',
                ),
                const _Faq(
                  question: 'What does Vero360 charge?',
                  answer:
                      'Listing is free. Vero360 applies its published '
                      'service fee on completed bookings, shown before you '
                      'accept a rental.',
                ),
                const _Faq(
                  question: 'How do I get paid?',
                  answer:
                      'Rental earnings settle into your Vero360 wallet, so '
                      'you can withdraw to mobile money or a bank account.',
                ),
                const _Faq(
                  question: 'Can I pause a car?',
                  answer:
                      'Yes. Every car can be blocked for maintenance, '
                      'cleaning or safety reasons from the company dashboard.',
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.of(sheetContext).maybePop(),
                    style: carHirePrimaryButton(),
                    child: const Text('Got it'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Dark hero that sells the opportunity before asking for anything.
class _PartnerHero extends StatelessWidget {
  const _PartnerHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CarHirePalette.primaryContainer, CarHirePalette.primary],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: CarHireShape.floatingShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: const Icon(
                  Icons.directions_car_filled_rounded,
                  color: CarHirePalette.accent,
                  size: 23,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: CarHirePalette.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  'FREE TO APPLY',
                  style: TextStyle(
                    color: CarHirePalette.accent,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            'Put your car to work.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'List a private car or build a full rental company on Vero360. '
            'You set the rates, we bring verified renters and handle the '
            'booking journey.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.74),
              fontSize: 12.5,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 18),
          const Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _HeroChip(icon: Icons.bolt_rounded, label: 'Review in 24h'),
              _HeroChip(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Wallet payouts',
              ),
              _HeroChip(
                icon: Icons.verified_rounded,
                label: 'Verified renters',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: CarHirePalette.accentSoft),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
  });

  final String number;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return CarHireSurface(
      padding: const EdgeInsets.all(14),
      radius: 18,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CarHirePalette.accentPale,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: CarHirePalette.accent,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 15, color: CarHirePalette.onSurface),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: CarHireType.title.copyWith(fontSize: 13.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(body, style: CarHireType.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NeedCard extends StatelessWidget {
  const _NeedCard();

  static const _items = <(IconData, String)>[
    (Icons.badge_outlined, 'National ID or business registration'),
    (Icons.smartphone_rounded, 'A phone number for dispatch calls'),
    (Icons.photo_camera_outlined, 'Clear photos of each car'),
    (Icons.explore_outlined, 'The towns or airports you serve'),
  ];

  @override
  Widget build(BuildContext context) {
    return CarHireSurface(
      padding: const EdgeInsets.all(16),
      radius: 20,
      color: CarHirePalette.surfaceLow,
      borderColor: CarHirePalette.hairline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('What you will need', style: CarHireType.title),
          const SizedBox(height: 3),
          const Text(
            'Have these ready and the application takes a few minutes.',
            style: CarHireType.bodySmall,
          ),
          const SizedBox(height: 12),
          for (final (icon, label) in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(
                      color: CarHirePalette.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 14,
                      color: CarHirePalette.accent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      style: CarHireType.bodySmall.copyWith(
                        color: CarHirePalette.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
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

class _ReassuranceCard extends StatelessWidget {
  const _ReassuranceCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CarHirePalette.successSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 17,
            color: CarHirePalette.success,
          ),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Your documents stay private. Renters only see that the car '
              'and the company are approved.',
              style: TextStyle(
                color: CarHirePalette.success,
                fontSize: 11.5,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusNote extends StatelessWidget {
  const _StatusNote({required this.account});

  final CarHireAccount account;

  String get _message => switch (account.state) {
    CarHireAccountState.active =>
      'Your company is approved. Open your dashboard to add cars and manage '
          'bookings.',
    CarHireAccountState.inReview =>
      'Your application is with Vero360. You can check the latest status '
          'any time.',
    CarHireAccountState.needsInformation =>
      'Vero360 needs a few details before approving your application.',
    CarHireAccountState.rejected =>
      'Your last application was not approved. You can review the note and '
          'apply again.',
    CarHireAccountState.suspended =>
      'Your company is paused. Contact Vero360 support to restore it.',
    CarHireAccountState.none => '',
  };

  @override
  Widget build(BuildContext context) {
    if (_message.isEmpty) return const SizedBox.shrink();
    return CarHireInfoBanner(
      icon: account.isActive
          ? Icons.verified_rounded
          : Icons.hourglass_top_rounded,
      title: account.isActive ? 'You are already a partner' : 'Application',
      message: _message,
      tone: account.isActive
          ? CarHireInfoTone.success
          : CarHireInfoTone.accent,
    );
  }
}

class _PartnerCta extends StatelessWidget {
  const _PartnerCta({required this.account, required this.loading});

  final CarHireAccount? account;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final active = account?.isActive ?? false;
    final hasProfile = account?.hasProfile ?? false;
    final String label;
    final VoidCallback action;

    if (active) {
      label = 'Open company dashboard';
      action = () => CarHireRoutes.openCompany(context);
    } else if (hasProfile) {
      label = 'Check application status';
      action = () => CarHireRoutes.openAccountStatus(context);
    } else {
      label = 'Start application';
      action = () => CarHireRoutes.openApply(context, existing: account);
    }

    return Material(
      color: CarHirePalette.background.withValues(alpha: 0.96),
      elevation: 12,
      shadowColor: CarHirePalette.primary.withValues(alpha: 0.08),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: loading ? null : action,
                  style: carHirePrimaryButton(),
                  child: Text(label),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                active
                    ? 'Add a car in about two minutes.'
                    : 'Free to apply · Typical review in 4 to 24 hours',
                textAlign: TextAlign.center,
                style: CarHireType.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Faq extends StatelessWidget {
  const _Faq({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question, style: CarHireType.subtitle),
          const SizedBox(height: 3),
          Text(answer, style: CarHireType.bodySmall),
        ],
      ),
    );
  }
}
