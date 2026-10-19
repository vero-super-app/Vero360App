import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vero360_app/features/car_hire/data/car_hire_api.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_status_badge.dart';
import 'package:vero360_app/features/car_rental/utils/car_rental_colors.dart';
import 'package:vero360_app/utils/toasthelper.dart';
import 'package:vero360_app/utils/user_facing_error.dart';

class CarHireInspectionPage extends ConsumerStatefulWidget {
  const CarHireInspectionPage({
    super.key,
    required this.bookingId,
    required this.type,
    this.booking,
  });

  final int bookingId;
  final InspectionType type;
  final CarHireBooking? booking;

  @override
  ConsumerState<CarHireInspectionPage> createState() =>
      _CarHireInspectionPageState();
}

class _CarHireInspectionPageState
    extends ConsumerState<CarHireInspectionPage> {
  static const List<String> _conditions = <String>[
    'EXCELLENT',
    'GOOD',
    'FAIR',
    'POOR',
    'DAMAGED',
  ];

  static const List<String> _checklistOptions = <String>[
    'EXTERIOR',
    'TYRES',
    'INTERIOR',
    'DOCUMENTS',
    'FUEL',
  ];

  final TextEditingController _odometerController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _mediaController = TextEditingController();

  final Set<String> _checklist = <String>{};
  double _fuelLevel = 50;
  String _condition = 'GOOD';
  String? _formError;

  @override
  void dispose() {
    _odometerController.dispose();
    _notesController.dispose();
    _mediaController.dispose();
    super.dispose();
  }

  bool get _isPickup => widget.type == InspectionType.pickup;

  Future<void> _refresh() async {
    ref.invalidate(bookingInspectionsProvider(widget.bookingId));
    try {
      await ref.read(bookingInspectionsProvider(widget.bookingId).future);
    } catch (_) {
      // The provider renders the error state.
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _formError = null);

    final odometerText = _odometerController.text.trim();
    final odometer =
        odometerText.isEmpty ? null : int.tryParse(odometerText);
    if (odometerText.isNotEmpty && odometer == null) {
      setState(() {
        _formError = 'Enter the odometer reading as a whole number of km.';
      });
      return;
    }

    final media = _mediaController.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);

    final result = await ref.read(inspectionSubmitProvider.notifier).submit(
          bookingId: widget.bookingId,
          type: widget.type,
          odometer: odometer,
          fuelLevel: _fuelLevel,
          condition: _condition,
          checklist: _checklist.toList(growable: false),
          notes: _notesController.text,
          media: media,
        );
    if (!mounted) return;

    if (result != null) {
      _odometerController.clear();
      _notesController.clear();
      _mediaController.clear();
      setState(() {
        _checklist.clear();
        _fuelLevel = 50;
      });
      ToastHelper.showToast(
        context,
        '${_isPickup ? 'Pick-up' : 'Return'} inspection submitted.',
      );
      return;
    }

    final error = ref.read(inspectionSubmitProvider).error;
    setState(() => _formError = error?.message ?? _formError);
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(UserFacingError.sanitize(error.message)),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _acknowledge(
    HandoverInspection inspection, {
    required bool accept,
  }) async {
    String? note;
    if (!accept) {
      note = await showDialog<String>(
        context: context,
        builder: (_) => const _DeclineInspectionDialog(),
      );
      if (note == null || !mounted) return;
    }

    final result =
        await ref.read(inspectionAcknowledgeProvider.notifier).acknowledge(
              bookingId: widget.bookingId,
              inspectionId: inspection.id,
              accept: accept,
              note: note,
            );
    if (!mounted) return;

    if (result != null) {
      ToastHelper.showToast(
        context,
        accept
            ? 'Inspection accepted.'
            : 'Inspection declined. Vero360 support can review it.',
      );
      return;
    }

    final error = ref.read(inspectionAcknowledgeProvider).error;
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(UserFacingError.sanitize(error.message)),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final inspections = ref.watch(
      bookingInspectionsProvider(widget.bookingId),
    );
    final submitState = ref.watch(inspectionSubmitProvider);
    final acknowledgeState = ref.watch(inspectionAcknowledgeProvider);

    return Scaffold(
      backgroundColor: CarHirePalette.background,
      appBar: carHireAppBar(
        title: _isPickup ? 'Pick-up inspection' : 'Return inspection',
        actions: [
          CarHireIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh',
            onTap: _refresh,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: RefreshIndicator(
        color: CarRentalColors.brandOrange,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            14,
            16,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            _introCard(),
            const SizedBox(height: 12),
            _formCard(submitState),
            const SizedBox(height: 12),
            _existingInspectionsCard(inspections, acknowledgeState),
          ],
        ),
      ),
    );
  }

  Widget _introCard() {
    final booking = widget.booking;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isPickup ? 'Record the vehicle at pick-up' : 'Record the vehicle at return',
            style: const TextStyle(
              color: CarRentalColors.title,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (booking != null) ...[
            const SizedBox(height: 8),
            Text(
              '${booking.bookingNumberLabel}'
              '${booking.car == null ? '' : ' · ${booking.car!.title}'}',
              style: const TextStyle(
                color: CarRentalColors.grey,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _formCard(CarHireMutationState submitState) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle('Your inspection'),
          const SizedBox(height: 12),
          TextField(
            controller: _odometerController,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: _decoration(
              label: 'Odometer (km)',
              hint: 'For example 45210',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Fuel level',
                  style: TextStyle(
                    color: CarRentalColors.title,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${_fuelLevel.round()}%',
                style: const TextStyle(
                  color: CarRentalColors.brandOrange,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          Slider(
            value: _fuelLevel,
            min: 0,
            max: 100,
            divisions: 20,
            label: '${_fuelLevel.round()}%',
            activeColor: CarRentalColors.brandOrange,
            inactiveColor: CarRentalColors.brandOrangePale,
            onChanged: (value) => setState(() => _fuelLevel = value),
          ),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            initialValue: _condition,
            isExpanded: true,
            decoration: _decoration(label: 'Condition'),
            items: _conditions
                .map(
                  (condition) => DropdownMenuItem<String>(
                    value: condition,
                    child: Text(_humanize(condition)),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value == null) return;
              setState(() => _condition = value);
            },
          ),
          const SizedBox(height: 14),
          const Text(
            'Checklist',
            style: TextStyle(
              color: CarRentalColors.title,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _checklistOptions.map((item) {
              final selected = _checklist.contains(item);
              return FilterChip(
                label: Text(_humanize(item)),
                selected: selected,
                selectedColor: CarRentalColors.brandOrangePale,
                checkmarkColor: CarRentalColors.brandOrange,
                labelStyle: TextStyle(
                  color: selected
                      ? CarRentalColors.title
                      : CarRentalColors.body,
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                side: BorderSide(
                  color: selected
                      ? CarRentalColors.brandOrange
                      : CarHirePalette.hairline,
                ),
                onSelected: (value) {
                  setState(() {
                    if (value) {
                      _checklist.add(item);
                    } else {
                      _checklist.remove(item);
                    }
                  });
                },
              );
            }).toList(growable: false),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: _decoration(
              label: 'Notes (optional)',
              hint: 'Scratches, warning lights, missing items…',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _mediaController,
            textCapitalization: TextCapitalization.none,
            decoration: _decoration(
              label: 'Photo references (optional)',
              hint: 'photo-123, photo-456',
            ),
          ),
          if (_formError != null) ...[
            const SizedBox(height: 10),
            CarHireInlineError(message: _formError!),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: submitState.submitting ? null : _submit,
            icon: submitState.submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.fact_check_outlined, size: 18),
            label: Text(
              submitState.submitting
                  ? 'Submitting inspection…'
                  : 'Submit ${_isPickup ? 'pick-up' : 'return'} inspection',
            ),
            style: carHirePrimaryButton(),
          ),
        ],
      ),
    );
  }

  Widget _existingInspectionsCard(
    AsyncValue<List<HandoverInspection>> inspections,
    CarHireMutationState acknowledgeState,
  ) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionTitle('Inspection history'),
          const SizedBox(height: 10),
          inspections.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
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
            ),
            error: (error, _) => CarHireInlineError(
              message: error is CarHireApiException
                  ? error.message
                  : UserFacingError.from(error),
              onRetry: _refresh,
            ),
            data: (items) {
              if (items.isEmpty) {
                return const Text(
                  'No inspections recorded for this booking yet.',
                  style: TextStyle(
                    color: CarRentalColors.body,
                    fontSize: 12,
                  ),
                );
              }
              return Column(
                children: [
                  for (final inspection in items)
                    _inspectionTile(inspection, acknowledgeState),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _inspectionTile(
    HandoverInspection inspection,
    CarHireMutationState acknowledgeState,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: CarRentalColors.greyLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CarHirePalette.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${inspection.typeLabel} · ${inspection.actorLabel}',
                  style: const TextStyle(
                    color: CarRentalColors.title,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: CarHireStatusBadge.inspection(inspection.status),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _InfoRow(label: 'Recorded', value: inspection.createdAtLabel),
          _InfoRow(label: 'Odometer', value: inspection.odometerLabel),
          _InfoRow(label: 'Fuel', value: inspection.fuelLevelLabel),
          _InfoRow(label: 'Condition', value: inspection.conditionLabel),
          _InfoRow(label: 'Checklist', value: inspection.checklistLabel),
          if (inspection.notes != null && inspection.notes!.trim().isNotEmpty)
            _InfoRow(label: 'Notes', value: inspection.notes!),
          if (inspection.media.isNotEmpty)
            _InfoRow(label: 'Media', value: inspection.mediaLabel),
          if (inspection.isDisputed &&
              inspection.disputeReason != null &&
              inspection.disputeReason!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            CarHireInlineError(message: inspection.disputeReason!),
          ],
          if (inspection.acknowledgements.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 6),
            for (final acknowledgement in inspection.acknowledgements)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '${acknowledgement.partyLabel} '
                  '${acknowledgement.decisionLabel.toLowerCase()}'
                  '${acknowledgement.createdAtLabel.isEmpty ? '' : ' · ${acknowledgement.createdAtLabel}'}'
                  '${acknowledgement.note == null || acknowledgement.note!.trim().isEmpty ? '' : ' — ${acknowledgement.note}'}',
                  style: const TextStyle(
                    color: CarRentalColors.body,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ),
          ],
          if (inspection.awaitingRenterDecision) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: acknowledgeState.submitting
                        ? null
                        : () => _acknowledge(inspection, accept: false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: CarRentalColors.error,
                      side: const BorderSide(color: CarRentalColors.error),
                      minimumSize: const Size.fromHeight(40),
                    ),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: acknowledgeState.submitting
                        ? null
                        : () => _acknowledge(inspection, accept: true),
                    style: FilledButton.styleFrom(
                      backgroundColor: CarRentalColors.success,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(40),
                    ),
                    child: acknowledgeState.submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  InputDecoration _decoration({
    required String label,
    String? hint,
    String? helper,
    bool alignLabelWithHint = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 2,
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

  String _humanize(String value) {
    return value
        .split(RegExp(r'[_\s]+'))
        .where((part) => part.isNotEmpty)
        .map((part) {
          final lower = part.toLowerCase();
          return '${lower.substring(0, 1).toUpperCase()}${lower.substring(1)}';
        })
        .join(' ');
  }
}

class _DeclineInspectionDialog extends StatefulWidget {
  const _DeclineInspectionDialog();

  @override
  State<_DeclineInspectionDialog> createState() =>
      _DeclineInspectionDialogState();
}

class _DeclineInspectionDialogState extends State<_DeclineInspectionDialog> {
  final TextEditingController _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Decline this inspection?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Declining records your disagreement and lets Vero360 support '
            'review the handover. You can add a reason below.',
            style: TextStyle(fontSize: 12, height: 1.45),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Keep inspection'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: CarRentalColors.error,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(_noteController.text.trim()),
          child: const Text('Decline'),
        ),
      ],
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: CarRentalColors.grey,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: CarRentalColors.title,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
