import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vero360_app/features/car_hire/data/car_hire_api.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/features/car_rental/utils/car_rental_colors.dart';
import 'package:vero360_app/utils/formatters.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/utils/user_facing_error.dart';

class CarHireReportPage extends ConsumerStatefulWidget {
  const CarHireReportPage({
    super.key,
    required this.bookingId,
    this.initialTab = 0,
    this.bookingNumber,
  });

  final int bookingId;
  final int initialTab;
  final String? bookingNumber;

  @override
  ConsumerState<CarHireReportPage> createState() => _CarHireReportPageState();
}

class _CarHireReportPageState extends ConsumerState<CarHireReportPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final TextEditingController _incidentDescriptionController =
      TextEditingController();
  final TextEditingController _incidentPhoneController = TextEditingController();
  final TextEditingController _supportSubjectController = TextEditingController();
  final TextEditingController _supportMessageController = TextEditingController();

  IncidentType _incidentType = IncidentType.accident;
  SupportCaseCategory _supportCategory = SupportCaseCategory.booking;
  String? _incidentError;
  String? _supportError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab == 1 ? 1 : 0,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _incidentDescriptionController.dispose();
    _incidentPhoneController.dispose();
    _supportSubjectController.dispose();
    _supportMessageController.dispose();
    super.dispose();
  }

  Future<void> _submitIncident() async {
    FocusScope.of(context).unfocus();
    final description = _incidentDescriptionController.text.trim();
    if (description.length < 5) {
      setState(() {
        _incidentError =
            'Describe what happened in at least 5 characters so support can '
            'help.';
      });
      return;
    }

    setState(() => _incidentError = null);
    final result = await ref.read(incidentReportProvider.notifier).report(
          bookingId: widget.bookingId,
          type: _incidentType,
          description: description,
          contactPhone: _incidentPhoneController.text,
        );
    if (!mounted) return;

    if (result != null) {
      _incidentDescriptionController.clear();
      _incidentPhoneController.clear();
      setState(() {});
      ToastHelper.showToast(
        context,
        'Incident reported. Vero360 support can see it on this booking.',
      );
      return;
    }

    final error = ref.read(incidentReportProvider).error;
    setState(() => _incidentError = error?.message ?? _incidentError);
    _showError(error);
  }

  Future<void> _submitSupportCase() async {
    FocusScope.of(context).unfocus();
    final subject = _supportSubjectController.text.trim();
    final message = _supportMessageController.text.trim();
    if (subject.isEmpty) {
      setState(() => _supportError = 'Add a short subject for your request.');
      return;
    }
    if (message.isEmpty) {
      setState(() => _supportError = 'Describe what you need help with.');
      return;
    }

    setState(() => _supportError = null);
    final result = await ref.read(supportCaseProvider.notifier).open(
          bookingId: widget.bookingId,
          category: _supportCategory,
          subject: subject,
          message: message,
        );
    if (!mounted) return;

    if (result != null) {
      _supportSubjectController.clear();
      _supportMessageController.clear();
      setState(() {});
      ToastHelper.showToast(
        context,
        'Support case opened. Keep your booking number handy for follow-up.',
      );
      return;
    }

    final error = ref.read(supportCaseProvider).error;
    setState(() => _supportError = error?.message ?? _supportError);
    _showError(error);
  }

  void _showError(CarHireApiException? error) {
    if (error == null || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(UserFacingError.sanitize(error.message)),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final incidentState = ref.watch(incidentReportProvider);
    final supportState = ref.watch(supportCaseProvider);

    return Scaffold(
      backgroundColor: CarHirePalette.background,
      appBar: carHireAppBar(
        title: 'Report an issue',
        bottom: TabBar(
          controller: _tabController,
          labelColor: CarHirePalette.accent,
          unselectedLabelColor: CarHirePalette.muted,
          indicatorColor: CarHirePalette.accent,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
          labelStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
          tabs: const [
            Tab(
              icon: Icon(Icons.report_problem_outlined, size: 19),
              text: 'Incident',
            ),
            Tab(
              icon: Icon(Icons.support_agent_rounded, size: 19),
              text: 'Support case',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _incidentTab(incidentState),
          _supportTab(supportState),
        ],
      ),
    );
  }

  Widget _incidentTab(CarHireMutationState state) {
    final incidents = ref.watch(bookingIncidentsProvider(widget.bookingId));

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionTitle('Report an incident'),
              const SizedBox(height: 4),
              Text(
                'Use this for accidents, breakdowns, theft, safety problems '
                'or a provider who did not show up.${_bookingReference()}',
                style: const TextStyle(
                  color: CarRentalColors.body,
                  fontSize: 11.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<IncidentType>(
                initialValue: _incidentType,
                isExpanded: true,
                decoration: _decoration('Incident type'),
                items: IncidentType.values
                    .where((type) => type != IncidentType.unknown)
                    .map(
                      (type) => DropdownMenuItem<IncidentType>(
                        value: type,
                        child: Text(type.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _incidentType = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _incidentDescriptionController,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: _decoration(
                  'What happened?',
                  hint: 'Where, when and what you observed. '
                      'At least 5 characters.',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _incidentPhoneController,
                keyboardType: TextInputType.phone,
                decoration: _decoration(
                  'Contact phone (optional)',
                  hint: '+265…',
                ),
              ),
              if (_incidentError != null) ...[
                const SizedBox(height: 10),
                CarHireInlineError(message: _incidentError!),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: state.submitting ? null : _submitIncident,
                icon: state.submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  state.submitting ? 'Reporting…' : 'Report incident',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: CarRentalColors.error,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      CarRentalColors.error.withValues(alpha: 0.4),
                  disabledForegroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _incidentHistory(incidents),
      ],
    );
  }

  Widget _incidentHistory(AsyncValue<List<IncidentReport>> incidents) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle('Reported incidents'),
          const SizedBox(height: 8),
          incidents.when(
            loading: () => const _SmallLoading(),
            error: (error, _) => CarHireInlineError(
              message: error is CarHireApiException
                  ? error.message
                  : UserFacingError.from(error),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const Text(
                  'No incidents reported for this booking.',
                  style: TextStyle(
                    color: CarRentalColors.body,
                    fontSize: 12,
                  ),
                );
              }
              return Column(
                children: [
                  for (final incident in items)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: CarRentalColors.greyLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: CarHirePalette.hairline),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  incident.typeLabel,
                                  style: const TextStyle(
                                    color: CarRentalColors.title,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Text(
                                incident.statusLabel,
                                style: const TextStyle(
                                  color: CarRentalColors.brandOrange,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            incident.description,
                            style: const TextStyle(
                              color: CarRentalColors.body,
                              fontSize: 11.5,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            incident.createdAt == null
                                ? 'Report time not provided'
                                : 'Reported ${CarHireFormatters.formatDateTime(incident.createdAt!)}',
                            style: const TextStyle(
                              color: CarRentalColors.grey,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _supportTab(CarHireMutationState state) {
    final cases = ref.watch(bookingSupportCasesProvider(widget.bookingId));

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionTitle('Open a support case'),
              const SizedBox(height: 4),
              Text(
                'Tell Vero360 support what you need. For handover or damage '
                'disputes, include dates and inspection references.'
                '${_bookingReference()}',
                style: const TextStyle(
                  color: CarRentalColors.body,
                  fontSize: 11.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<SupportCaseCategory>(
                initialValue: _supportCategory,
                isExpanded: true,
                decoration: _decoration('Category'),
                items: SupportCaseCategory.values
                    .where((category) => category != SupportCaseCategory.unknown)
                    .map(
                      (category) => DropdownMenuItem<SupportCaseCategory>(
                        value: category,
                        child: Text(category.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _supportCategory = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _supportSubjectController,
                textCapitalization: TextCapitalization.sentences,
                decoration: _decoration(
                  'Subject',
                  hint: 'Short summary of your request',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _supportMessageController,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: _decoration(
                  'Message',
                  hint: 'What do you need help with?',
                  alignLabelWithHint: true,
                ),
              ),
              if (_supportError != null) ...[
                const SizedBox(height: 10),
                CarHireInlineError(message: _supportError!),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: state.submitting ? null : _submitSupportCase,
                icon: state.submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.support_agent_rounded, size: 18),
                label: Text(
                  state.submitting ? 'Sending…' : 'Send to support',
                ),
                style: carHirePrimaryButton(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _supportHistory(cases),
      ],
    );
  }

  Widget _supportHistory(AsyncValue<List<SupportCase>> cases) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle('Recent support cases'),
          const SizedBox(height: 8),
          cases.when(
            loading: () => const _SmallLoading(),
            error: (error, _) => CarHireInlineError(
              message: error is CarHireApiException
                  ? error.message
                  : UserFacingError.from(error),
            ),
            data: (items) {
              if (items.isEmpty) {
                return const Text(
                  'No support cases for this booking yet.',
                  style: TextStyle(
                    color: CarRentalColors.body,
                    fontSize: 12,
                  ),
                );
              }
              return Column(
                children: [
                  for (final supportCase in items)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: CarRentalColors.greyLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: CarHirePalette.hairline),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  supportCase.subject.isEmpty
                                      ? supportCase.categoryLabel
                                      : supportCase.subject,
                                  style: const TextStyle(
                                    color: CarRentalColors.title,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Text(
                                supportCase.statusLabel,
                                style: const TextStyle(
                                  color: CarRentalColors.brandOrange,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${supportCase.categoryLabel} · '
                            '${supportCase.createdAtLabel}',
                            style: const TextStyle(
                              color: CarRentalColors.grey,
                              fontSize: 10.5,
                            ),
                          ),
                          if (supportCase.message.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              supportCase.message,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: CarRentalColors.body,
                                fontSize: 11.5,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _bookingReference() {
    final number = widget.bookingNumber?.trim();
    if (number == null || number.isEmpty) return '';
    return ' This will be attached to $number.';
  }

  InputDecoration _decoration(
    String label, {
    String? hint,
    bool alignLabelWithHint = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: alignLabelWithHint,
      filled: true,
      fillColor: CarHirePalette.surfaceLow,
      isDense: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: CarHirePalette.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: CarHirePalette.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: CarHirePalette.accent, width: 1.5),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CarHireSurface(
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: CarHireType.title);
  }
}

class _SmallLoading extends StatelessWidget {
  const _SmallLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: CarRentalColors.brandOrange,
          ),
        ),
      ),
    );
  }
}
