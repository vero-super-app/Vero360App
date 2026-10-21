import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vero360_app/features/car_hire/data/car_hire_api.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_company_models.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_browse_page.dart';
import 'package:vero360_app/features/car_hire/presentation/pages/car_hire_company_page.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_company_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_skeletons.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/features/car_hire/utils/car_hire_routes.dart';
import 'package:vero360_app/utils/user_facing_error.dart';

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

    // Once the account is known to be a live company, the remaining wait is
    // the membership lookup, so show the dashboard's own skeleton instead of
    // a generic one. Both share the same frame, so the switch is quiet.
    final expectsCompany =
        ref.watch(carHireAccountProvider).value?.isActive ?? false;

    return Scaffold(
      backgroundColor: CarHirePalette.background,
      appBar: carHireAppBar(title: 'Car hire'),
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
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: _BannerTap(
          onTap: () => CarHireRoutes.openApply(context),
          child: const CarHireInfoBanner(
            icon: Icons.add_business_outlined,
            title: 'Rent out your cars on Vero360',
            message:
                'Car hire companies and individual owners can list '
                'cars and manage every booking from one account.',
            tone: CarHireInfoTone.accent,
          ),
        ),
      );
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
      appBar: carHireAppBar(title: 'Car hire account'),
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
              actionLabel: 'Apply now',
              onAction: () => CarHireRoutes.openApply(context),
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
                value.isEmpty ? '—' : value,
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

/// Apply for a car hire account, or update an application Vero360 sent back.
class CarHireApplyPage extends ConsumerStatefulWidget {
  const CarHireApplyPage({super.key, this.existing});

  final CarHireAccount? existing;

  @override
  ConsumerState<CarHireApplyPage> createState() => _CarHireApplyPageState();
}

class _CarHireApplyPageState extends ConsumerState<CarHireApplyPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _areas;
  late final TextEditingController _registrationNumber;
  late final TextEditingController _taxId;
  late final TextEditingController _idNumber;
  late final TextEditingController _payoutName;
  late final TextEditingController _payoutAccount;
  late final TextEditingController _bankName;
  late final TextEditingController _identityDocument;
  late final TextEditingController _insuranceDocument;
  late bool _business;
  late String _payoutMethod;
  bool _submitting = false;
  String? _error;

  bool get _updating =>
      widget.existing?.state == CarHireAccountState.needsInformation &&
      widget.existing?.companyId != null;

  /// Document type of the identity link field; individuals prove a national ID.
  String get _identityDocumentType =>
      _business ? 'BUSINESS_REGISTRATION' : 'NATIONAL_ID';

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final isBusiness = existing == null || existing.isBusiness;
    _name = TextEditingController(text: existing?.companyName ?? '');
    _phone = TextEditingController(text: existing?.contactPhone ?? '');
    _areas = TextEditingController(
      text: existing?.serviceAreas.join(', ') ?? '',
    );
    _registrationNumber = TextEditingController(
      text: existing?.registrationNumber ?? '',
    );
    _taxId = TextEditingController(text: existing?.taxId ?? '');
    _idNumber = TextEditingController(text: existing?.idNumber ?? '');
    _payoutName = TextEditingController(
      text: existing?.payoutAccountName ?? '',
    );
    _payoutAccount = TextEditingController(
      text: existing?.payoutAccountNumber ?? '',
    );
    _bankName = TextEditingController(text: existing?.payoutBankName ?? '');
    _identityDocument = TextEditingController(
      text:
          existing?.documentFor(
            isBusiness ? 'BUSINESS_REGISTRATION' : 'NATIONAL_ID',
          ) ??
          '',
    );
    _insuranceDocument = TextEditingController(
      text: existing?.documentFor('INSURANCE') ?? '',
    );
    _business = isBusiness;
    _payoutMethod = existing?.payoutMethod == 'MOBILE_MONEY'
        ? 'MOBILE_MONEY'
        : 'BANK';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _areas.dispose();
    _registrationNumber.dispose();
    _taxId.dispose();
    _idNumber.dispose();
    _payoutName.dispose();
    _payoutAccount.dispose();
    _bankName.dispose();
    _identityDocument.dispose();
    _insuranceDocument.dispose();
    super.dispose();
  }

  List<String> get _serviceAreas => _areas.text
      .split(',')
      .map((area) => area.trim())
      .where((area) => area.isNotEmpty)
      .toList(growable: false);

  /// Merges the document links in the form with anything already on file, so
  /// an edit never silently drops a document the owner uploaded earlier.
  List<CompanyDocument> get _documents {
    final byType = <String, CompanyDocument>{
      for (final document in widget.existing?.documents ?? const <CompanyDocument>[])
        document.type.toUpperCase(): document,
    };
    void put(String type, String url) {
      final link = url.trim();
      if (link.isEmpty) {
        byType.remove(type);
        return;
      }
      byType[type] = CompanyDocument(type: type, url: link);
    }

    put(_identityDocumentType, _identityDocument.text);
    put('INSURANCE', _insuranceDocument.text);
    return byType.values.toList(growable: false);
  }

  String? _required(String? value, String message) =>
      (value ?? '').trim().isEmpty ? message : null;

  String? _optionalLink(String? value) {
    final link = (value ?? '').trim();
    if (link.isEmpty) return null;
    if (!link.startsWith('http://') && !link.startsWith('https://')) {
      return 'Paste a link that starts with https://';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final api = ref.read(carHireApiProvider);
    try {
      if (_updating) {
        await api.updateCarHireCompany(
          widget.existing!.companyId!,
          displayName: _name.text,
          contactPhone: _phone.text,
          serviceAreas: _serviceAreas,
          registrationNumber: _business ? _registrationNumber.text : '',
          taxId: _business ? _taxId.text : '',
          idNumber: _business ? '' : _idNumber.text,
          payoutMethod: _payoutMethod,
          payoutAccountName: _payoutName.text,
          payoutAccountNumber: _payoutAccount.text,
          payoutBankName: _payoutMethod == 'BANK' ? _bankName.text : '',
          documents: _documents,
        );
      } else {
        await api.applyForCarHireAccount(
          type: _business ? 'BUSINESS' : 'INDIVIDUAL',
          displayName: _name.text,
          contactPhone: _phone.text,
          serviceAreas: _serviceAreas,
          registrationNumber: _business ? _registrationNumber.text : null,
          taxId: _business ? _taxId.text : null,
          idNumber: _business ? null : _idNumber.text,
          payoutMethod: _payoutMethod,
          payoutAccountName: _payoutName.text,
          payoutAccountNumber: _payoutAccount.text,
          payoutBankName: _payoutMethod == 'BANK' ? _bankName.text : null,
          documents: _documents,
        );
      }
      ref.invalidate(carHireAccountProvider);
      ref.invalidate(companyAccessProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            _updating
                ? 'Details sent. Your application is back in review.'
                : 'Application sent. Vero360 will review it shortly.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } on CarHireApiException catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      setState(() => _error = UserFacingError.from(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CarHirePalette.background,
      appBar: carHireAppBar(
        title: _updating ? 'Update application' : 'List your cars',
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const Text(
              'One account runs everything: your cars, prices, calendar and '
              'bookings. Vero360 reviews every application before cars go '
              'live.',
              style: CarHireType.bodySmall,
            ),
            if (!_updating) ...[
              const SizedBox(height: 18),
              const Text('I am a', style: CarHireType.subtitle),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.business_rounded),
                    label: Text('Car hire company'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.person_rounded),
                    label: Text('Individual owner'),
                  ),
                ],
                selected: {_business},
                showSelectedIcon: false,
                onSelectionChanged: (value) =>
                    setState(() => _business = value.first),
              ),
            ],
            const SizedBox(height: 18),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: carHireInputDecoration(
                label: _business ? 'Company name' : 'Your name',
                hint: _business
                    ? 'e.g. Lilongwe Car Rentals'
                    : 'e.g. John Banda',
              ),
              validator: (value) => (value ?? '').trim().length < 2
                  ? 'Enter a name renters will recognise'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: carHireInputDecoration(
                label: 'Contact phone',
                hint: '+265…',
              ),
              validator: (value) => (value ?? '').trim().length < 7
                  ? 'Enter a phone number renters can call'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _areas,
              textCapitalization: TextCapitalization.words,
              decoration: carHireInputDecoration(
                label: 'Service areas',
                hint: 'Lilongwe, Blantyre',
                helper: 'Separate areas with commas.',
              ),
            ),
            const SizedBox(height: 22),
            const Text('Verification', style: CarHireType.subtitle),
            const SizedBox(height: 4),
            const Text(
              'Vero360 checks these details before your cars go live. '
              'Only the review team sees them.',
              style: CarHireType.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_business) ...[
              TextFormField(
                controller: _registrationNumber,
                textCapitalization: TextCapitalization.characters,
                decoration: carHireInputDecoration(
                  label: 'Company registration number',
                  hint: 'e.g. MBM-2024-1187',
                ),
                validator: (value) => _required(
                  value,
                  'Enter the company registration number',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _taxId,
                textCapitalization: TextCapitalization.characters,
                decoration: carHireInputDecoration(
                  label: 'TPIN (optional)',
                  hint: 'Tax identification number',
                ),
              ),
            ] else ...[
              TextFormField(
                controller: _idNumber,
                textCapitalization: TextCapitalization.characters,
                decoration: carHireInputDecoration(
                  label: 'National ID',
                  hint: 'e.g. MW-448291',
                ),
                validator: (value) =>
                    _required(value, 'Enter your national ID number'),
              ),
            ],
            const SizedBox(height: 22),
            const Text('Payout details', style: CarHireType.subtitle),
            const SizedBox(height: 4),
            const Text(
              'Where Vero360 sends your rental earnings.',
              style: CarHireType.bodySmall,
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'BANK', label: Text('Bank transfer')),
                ButtonSegment(value: 'MOBILE_MONEY', label: Text('Mobile money')),
              ],
              selected: {_payoutMethod},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _payoutMethod = value.first),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _payoutName,
              textCapitalization: TextCapitalization.words,
              decoration: carHireInputDecoration(
                label: _business ? 'Account name' : 'Account holder name',
                hint: _business
                    ? 'Name on the company account'
                    : 'Name on the account',
              ),
              validator: (value) =>
                  _required(value, 'Enter the name on the payout account'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _payoutAccount,
              keyboardType: TextInputType.number,
              decoration: carHireInputDecoration(
                label: _payoutMethod == 'BANK'
                    ? 'Account number'
                    : 'Mobile money number',
                hint: _payoutMethod == 'BANK' ? 'e.g. 1002345678' : '+265…',
              ),
              validator: (value) =>
                  _required(value, 'Enter the payout account number'),
            ),
            if (_payoutMethod == 'BANK') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _bankName,
                textCapitalization: TextCapitalization.words,
                decoration: carHireInputDecoration(
                  label: 'Bank name',
                  hint: 'e.g. National Bank of Malawi',
                ),
                validator: (value) =>
                    _required(value, 'Enter the bank name for this account'),
              ),
            ],
            const SizedBox(height: 22),
            const Text(
              'Compliance documents (optional)',
              style: CarHireType.subtitle,
            ),
            const SizedBox(height: 4),
            const Text(
              'Paste a link to a shared file. You can add these later.',
              style: CarHireType.bodySmall,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _identityDocument,
              keyboardType: TextInputType.url,
              decoration: carHireInputDecoration(
                label: _business
                    ? 'Business registration link'
                    : 'National ID link',
                hint: 'https://…',
              ),
              validator: _optionalLink,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _insuranceDocument,
              keyboardType: TextInputType.url,
              decoration: carHireInputDecoration(
                label: 'Insurance certificate link',
                hint: 'https://…',
              ),
              validator: _optionalLink,
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              CarHireInlineError(message: _error!),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              style: carHirePrimaryButton(),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: CarHirePalette.onAccent,
                      ),
                    )
                  : Text(_updating ? 'Send for review' : 'Submit application'),
            ),
          ],
        ),
      ),
    );
  }
}
