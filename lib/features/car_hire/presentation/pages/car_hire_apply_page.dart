import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:vero360_app/features/car_hire/data/car_hire_api.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_company_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_company_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/settings/Settings.dart' show PolicyPage;
import 'package:vero360_app/utils/user_facing_error.dart';

/// Malawi cities and airport hubs applicants can serve from.
const _presetAreas = <String>[
  'Lilongwe',
  'Blantyre',
  'Mzuzu',
  'Zomba',
  'Mangochi',
  'Kamuzu International Airport',
  'Chileka Airport',
];

const _fleetSizes = <(String, String)>[
  ('1-2', '1 – 2 Cars'),
  ('3-5', '3 – 5 Cars'),
  ('6-15', '6 – 15 Cars'),
  ('15+', '15+ Fleet'),
];

/// Partner application. Collects only what operations needs to review —
/// identity, documents, service areas. Payout / withdraw details are not
/// asked here.
class CarHireApplyPage extends ConsumerStatefulWidget {
  const CarHireApplyPage({super.key, this.existing});

  final CarHireAccount? existing;

  @override
  ConsumerState<CarHireApplyPage> createState() => _CarHireApplyPageState();
}

class _CarHireApplyPageState extends ConsumerState<CarHireApplyPage> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final TextEditingController _name;
  late final TextEditingController _representative;
  late final TextEditingController _phone;
  late final TextEditingController _registrationNumber;
  late final TextEditingController _taxId;
  late final TextEditingController _idNumber;
  late bool _business;
  late Set<String> _areas;
  String _fleetSize = '3-5';
  bool _acceptedTerms = false;
  bool _submitting = false;
  String? _error;
  String? _uploadingType;

  /// Local file URLs already on the application, plus anything uploaded now.
  late Map<String, CompanyDocument> _documents;

  bool get _updating =>
      widget.existing?.state == CarHireAccountState.needsInformation &&
      widget.existing?.companyId != null;

  String get _accountEmail =>
      FirebaseAuth.instance.currentUser?.email?.trim() ?? '';

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final isBusiness = existing == null || existing.isBusiness;
    _name = TextEditingController(text: existing?.companyName ?? '');
    _representative = TextEditingController();
    _phone = TextEditingController(text: _localPhone(existing?.contactPhone));
    _registrationNumber = TextEditingController(
      text: existing?.registrationNumber ?? '',
    );
    _taxId = TextEditingController(text: existing?.taxId ?? '');
    _idNumber = TextEditingController(text: existing?.idNumber ?? '');
    _business = isBusiness;
    _areas = existing?.serviceAreas
            .where((area) => area.trim().isNotEmpty)
            .toSet() ??
        <String>{};
    _documents = <String, CompanyDocument>{
      for (final document
          in existing?.documents ?? const <CompanyDocument>[])
        document.type.toUpperCase(): document,
    };
  }

  @override
  void dispose() {
    _name.dispose();
    _representative.dispose();
    _phone.dispose();
    _registrationNumber.dispose();
    _taxId.dispose();
    _idNumber.dispose();
    super.dispose();
  }

  String _localPhone(String? raw) {
    final digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('265') && digits.length > 3) {
      return digits.substring(3);
    }
    if (digits.startsWith('0')) return digits.substring(1);
    return digits;
  }

  String get _fullPhone {
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('265')) return '+$digits';
    if (digits.startsWith('0')) return '+265${digits.substring(1)}';
    return '+265$digits';
  }

  List<CompanyDocument> get _documentList =>
      _documents.values.toList(growable: false);

  String? _required(String? value, String message) =>
      (value ?? '').trim().isEmpty ? message : null;

  Future<void> _pickDocument(String type) async {
    if (_uploadingType != null) return;
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 78,
        maxWidth: 1800,
      );
      if (file == null) return;
      setState(() => _uploadingType = type);
      final bytes = await file.readAsBytes();
      final url = await ref.read(carHireApiProvider).uploadPhoto(
            bytes,
            filename: file.name.trim().isEmpty ? '$type.jpg' : file.name,
          );
      if (!mounted) return;
      setState(() {
        _documents[type] = CompanyDocument(
          type: type,
          url: url,
          uploadedAt: DateTime.now().toUtc().toIso8601String(),
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is CarHireApiException
            ? error.message
            : 'The document could not be attached.';
      });
    } finally {
      if (mounted) setState(() => _uploadingType = null);
    }
  }

  void _clearDocument(String type) {
    setState(() => _documents.remove(type));
  }

  Future<void> _addCustomArea() async {
    final controller = TextEditingController();
    final area = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CarHirePalette.surface,
        title: const Text('Add a service area'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: carHireInputDecoration(
            label: 'Town, city or airport',
            hint: 'e.g. Salima',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            style: carHirePrimaryButton(),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (area == null || area.isEmpty) return;
    setState(() => _areas.add(area));
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_areas.isEmpty) {
      setState(() => _error = 'Select at least one service area.');
      return;
    }
    if (_business && !_documents.containsKey('BUSINESS_REGISTRATION')) {
      setState(
        () => _error = 'Attach a photo of the certificate of incorporation.',
      );
      return;
    }
    if (!_business && !_documents.containsKey('NATIONAL_ID')) {
      setState(() => _error = 'Attach a photo of the front of your national ID.');
      return;
    }
    if (!_acceptedTerms) {
      setState(
        () => _error =
            'Confirm that the registration and ID documents are authentic.',
      );
      return;
    }

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
          contactPhone: _fullPhone,
          serviceAreas: _areas.toList(growable: false),
          registrationNumber: _business ? _registrationNumber.text : '',
          taxId: _business ? _taxId.text : '',
          idNumber: _business ? '' : _idNumber.text,
          documents: _documentList,
        );
      } else {
        await api.applyForCarHireAccount(
          type: _business ? 'BUSINESS' : 'INDIVIDUAL',
          displayName: _name.text,
          contactPhone: _fullPhone,
          serviceAreas: _areas.toList(growable: false),
          registrationNumber: _business ? _registrationNumber.text : null,
          taxId: _business ? _taxId.text : null,
          idNumber: _business ? null : _idNumber.text,
          documents: _documentList,
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
                : 'Application received. Vero360 will review it within 24 hours.',
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
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: CarHirePalette.background,
      appBar: carHireAppBar(
        title: _updating ? 'Update application' : 'Partner Application',
        actions: [
          IconButton(
            tooltip: 'Help & support',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const PolicyPage(focusCarHire: true),
              ),
            ),
            icon: const Icon(
              Icons.support_agent_rounded,
              color: CarHirePalette.onSurfaceVariant,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(
              radius: 14,
              backgroundColor: CarHirePalette.primary,
              child: const Icon(
                Icons.person_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 132 + bottomInset),
          children: [
            _ProgressHeader(updating: _updating),
            const SizedBox(height: 18),
            const _TrustBanner(),
            const SizedBox(height: 18),
            if (!_updating) ...[
              _EntityToggle(
                business: _business,
                onChanged: (value) => setState(() => _business = value),
              ),
              const SizedBox(height: 18),
            ],
            if (_business) _companyFields() else _individualFields(),
            const SizedBox(height: 18),
            _ServiceAreasCard(
              selected: _areas,
              onToggle: (area) => setState(() {
                if (!_areas.add(area)) _areas.remove(area);
              }),
              onAddCustom: _addCustomArea,
            ),
            const SizedBox(height: 18),
            _FleetSizeCard(
              value: _fleetSize,
              onChanged: (value) => setState(() => _fleetSize = value),
            ),
            const SizedBox(height: 18),
            _TermsCard(
              accepted: _acceptedTerms,
              onChanged: (value) =>
                  setState(() => _acceptedTerms = value ?? false),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              CarHireInlineError(message: _error!),
            ],
          ],
        ),
      ),
      bottomNavigationBar: _SubmitBar(
        submitting: _submitting,
        updating: _updating,
        onSubmit: _submit,
      ),
    );
  }

  Widget _companyFields() {
    return Column(
      children: [
        _SectionCard(
          icon: Icons.apartment_rounded,
          title: 'Corporate details',
          badge: 'Company',
          children: [
            _LabeledField(
              label: 'Registered business legal name',
              icon: Icons.badge_outlined,
              child: TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: _fieldDecoration('e.g. Lilongwe Car Rentals'),
                validator: (value) => (value ?? '').trim().length < 2
                    ? 'Enter the registered company name'
                    : null,
              ),
            ),
            _LabeledField(
              label: 'Authorised representative & title',
              icon: Icons.account_circle_outlined,
              child: TextFormField(
                controller: _representative,
                textCapitalization: TextCapitalization.words,
                decoration: _fieldDecoration('Full name · role'),
                // Collected for the operator; Vero360 reaches them on the
                // dispatch phone. Not a backend field yet.
              ),
            ),
            _LabeledField(
              label: 'Fleet dispatch phone',
              child: _PhoneField(controller: _phone),
            ),
            _LabeledField(
              label: 'Operations email',
              icon: Icons.alternate_email_rounded,
              trailing: _accountEmail.isEmpty
                  ? null
                  : const Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: CarHirePalette.success,
                    ),
              child: TextFormField(
                initialValue: _accountEmail.isEmpty
                    ? 'Sign in to use your Vero360 email'
                    : _accountEmail,
                readOnly: true,
                enabled: false,
                decoration: _fieldDecoration(''),
              ),
            ),
            _LabeledField(
              label: 'Company registration number',
              hintBadge: 'Required',
              icon: Icons.pin_outlined,
              child: TextFormField(
                controller: _registrationNumber,
                textCapitalization: TextCapitalization.characters,
                decoration: _fieldDecoration('e.g. MBM-2024-1187'),
                validator: (value) =>
                    _required(value, 'Enter the company registration number'),
              ),
            ),
            _LabeledField(
              label: 'TPIN / tax identification number',
              icon: Icons.receipt_long_outlined,
              child: TextFormField(
                controller: _taxId,
                textCapitalization: TextCapitalization.characters,
                decoration: _fieldDecoration('e.g. TPIN-2049'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _DocumentCard(
          title: 'Certificate of incorporation',
          requiredLabel: true,
          document: _documents['BUSINESS_REGISTRATION'],
          uploading: _uploadingType == 'BUSINESS_REGISTRATION',
          onAttach: () => _pickDocument('BUSINESS_REGISTRATION'),
          onClear: () => _clearDocument('BUSINESS_REGISTRATION'),
        ),
        const SizedBox(height: 12),
        _DocumentCard(
          title: 'Tax clearance (optional)',
          document: _documents['TAX_CLEARANCE'],
          uploading: _uploadingType == 'TAX_CLEARANCE',
          onAttach: () => _pickDocument('TAX_CLEARANCE'),
          onClear: () => _clearDocument('TAX_CLEARANCE'),
          compact: true,
        ),
      ],
    );
  }

  Widget _individualFields() {
    return Column(
      children: [
        _SectionCard(
          icon: Icons.person_pin_circle_outlined,
          title: 'Personal host details',
          badge: 'Private host',
          accentBadge: true,
          children: [
            _LabeledField(
              label: 'Full legal name (as printed on ID)',
              icon: Icons.person_outline_rounded,
              child: TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: _fieldDecoration('e.g. John Banda'),
                validator: (value) => (value ?? '').trim().length < 2
                    ? 'Enter the name on your national ID'
                    : null,
              ),
            ),
            _LabeledField(
              label: 'Mobile phone number',
              child: _PhoneField(controller: _phone),
            ),
            _LabeledField(
              label: 'Account email',
              icon: Icons.mail_outline_rounded,
              trailing: _accountEmail.isEmpty
                  ? null
                  : const Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: CarHirePalette.success,
                    ),
              child: TextFormField(
                initialValue: _accountEmail.isEmpty
                    ? 'Sign in to use your Vero360 email'
                    : _accountEmail,
                readOnly: true,
                enabled: false,
                decoration: _fieldDecoration(''),
              ),
            ),
            _LabeledField(
              label: 'National ID number',
              hintBadge: 'Required',
              icon: Icons.badge_outlined,
              child: TextFormField(
                controller: _idNumber,
                textCapitalization: TextCapitalization.characters,
                decoration: _fieldDecoration('e.g. MW-448291'),
                validator: (value) =>
                    _required(value, 'Enter your national ID number'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _IdPhotoCard(
          front: _documents['NATIONAL_ID'],
          back: _documents['NATIONAL_ID_BACK'],
          uploadingFront: _uploadingType == 'NATIONAL_ID',
          uploadingBack: _uploadingType == 'NATIONAL_ID_BACK',
          onFront: () => _pickDocument('NATIONAL_ID'),
          onBack: () => _pickDocument('NATIONAL_ID_BACK'),
          onClearFront: () => _clearDocument('NATIONAL_ID'),
          onClearBack: () => _clearDocument('NATIONAL_ID_BACK'),
        ),
      ],
    );
  }
}

InputDecoration _fieldDecoration(String hint) {
  return const InputDecoration(
    isDense: true,
    border: InputBorder.none,
    hintStyle: TextStyle(
      color: CarHirePalette.muted,
      fontSize: 15,
      fontWeight: FontWeight.w500,
    ),
  ).copyWith(hintText: hint);
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.updating});

  final bool updating;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              updating ? 'RESUBMISSION' : 'REVIEW ONLY',
              style: const TextStyle(
                color: CarHirePalette.accent,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
            const Spacer(),
            const Text(
              'No payout details needed',
              style: CarHireType.labelSmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: const LinearProgressIndicator(
            value: 1,
            minHeight: 6,
            color: CarHirePalette.accent,
            backgroundColor: CarHirePalette.surfaceHigh,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          updating
              ? 'Update your review details'
              : 'Apply as a Car Hire Partner',
          style: CarHireType.headline.copyWith(
            color: CarHirePalette.primaryContainer,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'List your fleet or private car on Vero360. We only need identity '
          'and operating details for review — payout setup comes after approval.',
          style: CarHireType.body,
        ),
      ],
    );
  }
}

class _TrustBanner extends StatelessWidget {
  const _TrustBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CarHirePalette.surfaceLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Color(0xFFD4E3FF),
            child: Icon(
              Icons.verified_user_rounded,
              size: 18,
              color: CarHirePalette.primaryContainer,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Identity-checked onboarding',
                  style: TextStyle(
                    color: CarHirePalette.primaryContainer,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Registration, national ID and vehicle documents are reviewed by Vero360.',
                  style: CarHireType.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntityToggle extends StatelessWidget {
  const _EntityToggle({required this.business, required this.onChanged});

  final bool business;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: CarHirePalette.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: _EntityTab(
              selected: business,
              icon: Icons.apartment_rounded,
              title: 'Company',
              caption: 'Multi-vehicle fleet',
              onTap: () => onChanged(true),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _EntityTab(
              selected: !business,
              icon: Icons.person_rounded,
              title: 'Individual host',
              caption: 'Private owner',
              onTap: () => onChanged(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntityTab extends StatelessWidget {
  const _EntityTab({
    required this.selected,
    required this.icon,
    required this.title,
    required this.caption,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? CarHirePalette.surface : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected
                        ? CarHirePalette.primaryContainer
                        : CarHirePalette.muted,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: selected
                            ? CarHirePalette.primaryContainer
                            : CarHirePalette.onSurfaceVariant,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFD4E3FF)
                      : CarHirePalette.accentSoft,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  caption.toUpperCase(),
                  style: TextStyle(
                    color: selected
                        ? CarHirePalette.primaryContainer
                        : CarHirePalette.accent,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.badge,
    required this.children,
    this.accentBadge = false,
  });

  final IconData icon;
  final String title;
  final String badge;
  final bool accentBadge;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return CarHireSurface(
      padding: const EdgeInsets.all(16),
      shadow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: CarHirePalette.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: CarHirePalette.primaryContainer,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accentBadge
                      ? CarHirePalette.accentSoft
                      : CarHirePalette.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: accentBadge
                        ? CarHirePalette.accent
                        : CarHirePalette.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.child,
    this.icon,
    this.trailing,
    this.hintBadge,
  });

  final String label;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;
  final String? hintBadge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: CarHireType.label)),
              if (hintBadge != null)
                Text(
                  hintBadge!,
                  style: const TextStyle(
                    color: CarHirePalette.success,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: CarHirePalette.surfaceLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20, color: CarHirePalette.muted),
                  const SizedBox(width: 8),
                ],
                Expanded(child: child),
                ?trailing,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: CarHirePalette.surfaceContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            '🇲🇼  +265',
            style: TextStyle(
              color: CarHirePalette.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.phone,
            decoration: _fieldDecoration('991 000 000'),
            validator: (value) {
              final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
              return digits.length < 7
                  ? 'Enter a phone number Vero360 can call'
                  : null;
            },
          ),
        ),
      ],
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.title,
    required this.onAttach,
    required this.onClear,
    this.document,
    this.uploading = false,
    this.requiredLabel = false,
    this.compact = false,
  });

  final String title;
  final CompanyDocument? document;
  final bool uploading;
  final bool requiredLabel;
  final bool compact;
  final VoidCallback onAttach;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final attached = document != null;
    return CarHireSurface(
      padding: const EdgeInsets.all(16),
      shadow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: CarHirePalette.primaryContainer,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (requiredLabel)
                const Text(
                  'Required',
                  style: TextStyle(
                    color: CarHirePalette.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (attached)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: CarHirePalette.surfaceLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4E3FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.description_outlined,
                      color: CarHirePalette.primaryContainer,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fileName(document!.url),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const Text(
                          'Attached for review',
                          style: TextStyle(
                            color: CarHirePalette.success,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Replace',
                    onPressed: uploading ? null : onAttach,
                    icon: const Icon(Icons.sync_rounded, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: uploading ? null : onClear,
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            )
          else
            _AttachButton(
              label: compact ? 'Attach tax clearance photo' : 'Attach a photo',
              uploading: uploading,
              onTap: onAttach,
            ),
        ],
      ),
    );
  }
}

class _IdPhotoCard extends StatelessWidget {
  const _IdPhotoCard({
    required this.front,
    required this.back,
    required this.uploadingFront,
    required this.uploadingBack,
    required this.onFront,
    required this.onBack,
    required this.onClearFront,
    required this.onClearBack,
  });

  final CompanyDocument? front;
  final CompanyDocument? back;
  final bool uploadingFront;
  final bool uploadingBack;
  final VoidCallback onFront;
  final VoidCallback onBack;
  final VoidCallback onClearFront;
  final VoidCallback onClearBack;

  @override
  Widget build(BuildContext context) {
    return CarHireSurface(
      padding: const EdgeInsets.all(16),
      shadow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Government photo ID',
                  style: TextStyle(
                    color: CarHirePalette.primaryContainer,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                'Required',
                style: TextStyle(
                  color: CarHirePalette.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _IdSlot(
                  label: 'Front of card',
                  document: front,
                  uploading: uploadingFront,
                  onTap: onFront,
                  onClear: onClearFront,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _IdSlot(
                  label: 'Back of card',
                  document: back,
                  uploading: uploadingBack,
                  onTap: onBack,
                  onClear: onClearBack,
                  optional: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IdSlot extends StatelessWidget {
  const _IdSlot({
    required this.label,
    required this.onTap,
    required this.onClear,
    this.document,
    this.uploading = false,
    this.optional = false,
  });

  final String label;
  final CompanyDocument? document;
  final bool uploading;
  final bool optional;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final attached = document != null;
    return Material(
      color: CarHirePalette.surfaceLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: uploading ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 132,
          child: attached
              ? Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          document!.url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(Icons.description_outlined),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: GestureDetector(
                        onTap: onClear,
                        child: const CircleAvatar(
                          radius: 11,
                          backgroundColor: Colors.white,
                          child: Icon(Icons.close_rounded, size: 14),
                        ),
                      ),
                    ),
                    const Positioned(
                      bottom: 8,
                      left: 8,
                      child: CircleAvatar(
                        radius: 11,
                        backgroundColor: CarHirePalette.success,
                        child: Icon(Icons.check, size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (uploading)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: CarHirePalette.surfaceHigh,
                        child: Icon(
                          Icons.add_a_photo_outlined,
                          size: 18,
                          color: CarHirePalette.primaryContainer,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        color: CarHirePalette.primaryContainer,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      optional ? 'Optional' : 'Tap to upload',
                      style: CarHireType.labelSmall,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _AttachButton extends StatelessWidget {
  const _AttachButton({
    required this.label,
    required this.uploading,
    required this.onTap,
  });

  final String label;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: CarHirePalette.surfaceLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: uploading ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (uploading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(
                  Icons.upload_file_outlined,
                  size: 18,
                  color: CarHirePalette.onSurfaceVariant,
                ),
              const SizedBox(width: 8),
              Text(label, style: CarHireType.label),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceAreasCard extends StatelessWidget {
  const _ServiceAreasCard({
    required this.selected,
    required this.onToggle,
    required this.onAddCustom,
  });

  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback onAddCustom;

  @override
  Widget build(BuildContext context) {
    final extras = selected.where((area) => !_presetAreas.contains(area));
    return CarHireSurface(
      padding: const EdgeInsets.all(16),
      shadow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.explore_outlined,
                size: 20,
                color: CarHirePalette.accent,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Operating service areas',
                  style: TextStyle(
                    color: CarHirePalette.primaryContainer,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${selected.length} selected',
                style: const TextStyle(
                  color: CarHirePalette.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Select every zone where your cars can be picked up or delivered.',
            style: CarHireType.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final area in [..._presetAreas, ...extras])
                _AreaChip(
                  label: area,
                  selected: selected.contains(area),
                  onTap: () => onToggle(area),
                ),
              ActionChip(
                onPressed: onAddCustom,
                backgroundColor: CarHirePalette.accentSoft,
                side: BorderSide.none,
                avatar: const Icon(
                  Icons.add_location_alt_outlined,
                  size: 16,
                  color: CarHirePalette.onAccentSoft,
                ),
                label: const Text(
                  'Add custom area',
                  style: TextStyle(
                    color: CarHirePalette.onAccentSoft,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AreaChip extends StatelessWidget {
  const _AreaChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: CarHirePalette.primaryContainer,
      backgroundColor: CarHirePalette.surfaceContainer,
      side: BorderSide.none,
      avatar: Icon(
        selected ? Icons.check_circle_rounded : Icons.add_rounded,
        size: 16,
        color: selected ? CarHirePalette.accent : CarHirePalette.muted,
      ),
      label: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : CarHirePalette.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _FleetSizeCard extends StatelessWidget {
  const _FleetSizeCard({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return CarHireSurface(
      padding: const EdgeInsets.all(16),
      shadow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.directions_car_filled_outlined,
                size: 20,
                color: CarHirePalette.accent,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Estimated initial vehicles',
                  style: TextStyle(
                    color: CarHirePalette.primaryContainer,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text('For review only', style: CarHireType.labelSmall),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.6,
            children: [
              for (final option in _fleetSizes)
                _FleetOption(
                  label: option.$2,
                  selected: value == option.$1,
                  onTap: () => onChanged(option.$1),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FleetOption extends StatelessWidget {
  const _FleetOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? CarHirePalette.primaryContainer
          : CarHirePalette.surfaceLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : CarHirePalette.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              Icon(
                Icons.check_circle_rounded,
                size: 18,
                color: selected ? CarHirePalette.accent : Colors.transparent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TermsCard extends StatelessWidget {
  const _TermsCard({required this.accepted, required this.onChanged});

  final bool accepted;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CarHirePalette.surfaceLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: accepted,
            onChanged: onChanged,
            activeColor: CarHirePalette.accent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'I certify that the registration and identification documents '
                'are authentic and authorise Vero360 to review them for this '
                'car hire application.',
                style: CarHireType.bodySmall,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({
    required this.submitting,
    required this.updating,
    required this.onSubmit,
  });

  final bool submitting;
  final bool updating;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: CarHirePalette.background.withValues(alpha: 0.94),
      elevation: 12,
      shadowColor: CarHirePalette.primary.withValues(alpha: 0.08),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: submitting ? null : onSubmit,
                style: carHirePrimaryButton(),
                child: submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: CarHirePalette.onAccent,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            updating
                                ? 'Send for review'
                                : 'Submit application for review',
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 18),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 8),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_rounded,
                  size: 13,
                  color: CarHirePalette.success,
                ),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Typical review time: 4 to 24 hours',
                    style: CarHireType.labelSmall,
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

String _fileName(String url) {
  final path = Uri.tryParse(url)?.pathSegments;
  if (path == null || path.isEmpty) return 'Document';
  return path.last;
}
