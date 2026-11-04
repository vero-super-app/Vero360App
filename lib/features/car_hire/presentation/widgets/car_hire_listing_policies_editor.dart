import 'package:flutter/material.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_policy_models.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';

const _districts = <(String, String)>[
  ('chitipa', 'Chitipa'),
  ('karonga', 'Karonga'),
  ('rumphi', 'Rumphi'),
  ('mzimba', 'Mzimba'),
  ('nkhata-bay', 'Nkhata Bay'),
  ('likoma', 'Likoma'),
  ('kasungu', 'Kasungu'),
  ('nkhotakota', 'Nkhotakota'),
  ('ntchisi', 'Ntchisi'),
  ('dowa', 'Dowa'),
  ('salima', 'Salima'),
  ('lilongwe', 'Lilongwe'),
  ('mchinji', 'Mchinji'),
  ('dedza', 'Dedza'),
  ('ntcheu', 'Ntcheu'),
  ('mangochi', 'Mangochi'),
  ('machinga', 'Machinga'),
  ('zomba', 'Zomba'),
  ('chiradzulu', 'Chiradzulu'),
  ('blantyre', 'Blantyre'),
  ('mwanza', 'Mwanza'),
  ('thyolo', 'Thyolo'),
  ('mulanje', 'Mulanje'),
  ('phalombe', 'Phalombe'),
  ('chikwawa', 'Chikwawa'),
  ('nsanje', 'Nsanje'),
  ('balaka', 'Balaka'),
  ('neno', 'Neno'),
];

/// Listing rules, drawn with the same pieces as the wizard fields above:
/// labelled fields, choice pills and quiet check rows. The platform terms are
/// stated once as a note; everything below is the owner's own choice.
class CarHireListingPoliciesEditor extends StatelessWidget {
  const CarHireListingPoliciesEditor({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final CarHireListingPolicies value;
  final ValueChanged<CarHireListingPolicies> onChanged;

  void _toggleMode(String mode) {
    final next = List<String>.from(value.rentalModes);
    if (next.contains(mode)) {
      next.remove(mode);
    } else {
      next.add(mode);
    }
    onChanged(
      value.copyWith(rentalModes: next.isEmpty ? <String>[mode] : next),
    );
  }

  void _toggleDistrict(String id, bool selected) {
    final next = List<String>.from(value.allowedDistricts);
    if (selected) {
      if (!next.contains(id)) next.add(id);
    } else {
      next.remove(id);
    }
    onChanged(value.copyWith(allowedDistricts: next));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _VeroNote(),
        const SizedBox(height: 14),
        const CarHireFieldLabel('Rental modes'),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            CarHireChoiceChip(
              label: 'Self-drive',
              icon: Icons.key_rounded,
              selected: value.offersSelfDrive,
              onTap: () => _toggleMode('SELF_DRIVE'),
            ),
            CarHireChoiceChip(
              label: 'With driver',
              icon: Icons.person_outline_rounded,
              selected: value.offersWithDriver,
              onTap: () => _toggleMode('WITH_DRIVER'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const CarHireFieldLabel('Guest extras'),
        CarHireCheckRow(
          label: 'Extra drivers',
          subtitle: value.offersSelfDrive
              ? 'Let renters add licensed drivers'
              : 'Needs self-drive to be offered',
          value: value.extraDriversAllowed,
          enabled: value.offersSelfDrive,
          onChanged: value.offersSelfDrive
              ? (checked) =>
                    onChanged(value.copyWith(extraDriversAllowed: checked))
              : null,
        ),
        if (value.extraDriversAllowed) ...[
          const CarHireFieldLabel('Maximum extra drivers'),
          TextFormField(
            initialValue:
                '${value.extraDriversMax > 0 ? value.extraDriversMax : 1}',
            keyboardType: TextInputType.number,
            decoration: carHireInputDecoration(
              hint: '2',
              helper: 'Renters can add up to this many drivers.',
            ),
            onChanged: (text) => onChanged(
              value.copyWith(extraDriversMax: int.tryParse(text) ?? 1),
            ),
          ),
          const SizedBox(height: 12),
        ],
        CarHireCheckRow(
          label: 'Smoking allowed',
          value: value.smokingAllowed,
          onChanged: (checked) =>
              onChanged(value.copyWith(smokingAllowed: checked)),
        ),
        CarHireCheckRow(
          label: 'Pets allowed',
          value: value.petsAllowed,
          onChanged: (checked) =>
              onChanged(value.copyWith(petsAllowed: checked)),
        ),
        CarHireCheckRow(
          label: 'Cross-border travel',
          subtitle: 'Malawi to Zambia, Tanzania or Mozambique',
          value: value.crossBorderAllowed,
          onChanged: (checked) =>
              onChanged(value.copyWith(crossBorderAllowed: checked)),
        ),
        CarHireCheckRow(
          label: 'Off-road use',
          value: value.offRoadAllowed,
          onChanged: (checked) =>
              onChanged(value.copyWith(offRoadAllowed: checked)),
        ),
        CarHireCheckRow(
          label: 'Delivery / collection',
          subtitle: 'Hand the car over at an address you agree',
          value: value.deliveryOffered,
          onChanged: (checked) =>
              onChanged(value.copyWith(deliveryOffered: checked)),
        ),
        CarHireCheckRow(
          label: 'Remote engine-off available',
          subtitle: 'You can immobilise the car from Vero while it is out',
          value: value.immobilizeAvailable,
          onChanged: (checked) =>
              onChanged(value.copyWith(immobilizeAvailable: checked)),
        ),
        const SizedBox(height: 7),
        const CarHireFieldLabel('Travel area'),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            CarHireChoiceChip(
              label: 'Nationwide Malawi',
              selected: value.travelAreaMode == 'NATIONWIDE',
              onTap: () =>
                  onChanged(value.copyWith(travelAreaMode: 'NATIONWIDE')),
            ),
            CarHireChoiceChip(
              label: 'Hire area only',
              selected: value.travelAreaMode == 'HIRE_AREA',
              onTap: () =>
                  onChanged(value.copyWith(travelAreaMode: 'HIRE_AREA')),
            ),
            CarHireChoiceChip(
              label: 'Selected districts',
              selected: value.travelAreaMode == 'DISTRICT',
              onTap: () =>
                  onChanged(value.copyWith(travelAreaMode: 'DISTRICT')),
            ),
          ],
        ),
        if (value.travelAreaMode == 'HIRE_AREA') ...[
          const SizedBox(height: 12),
          const CarHireFieldLabel('Hire-area radius (km)'),
          TextFormField(
            initialValue: '${value.hireAreaRadiusKm}',
            keyboardType: TextInputType.number,
            decoration: carHireInputDecoration(
              hint: '25',
              helper: 'How far from your branch the car may go.',
            ),
            onChanged: (text) => onChanged(
              value.copyWith(hireAreaRadiusKm: int.tryParse(text) ?? 25),
            ),
          ),
        ],
        if (value.travelAreaMode == 'DISTRICT') ...[
          const SizedBox(height: 12),
          CarHireFieldLabel(
            'Districts you serve',
            trailing: value.allowedDistricts.isEmpty
                ? null
                : TextButton(
                    onPressed: () =>
                        onChanged(value.copyWith(allowedDistricts: <String>[])),
                    style: TextButton.styleFrom(
                      foregroundColor: CarHirePalette.accent,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Clear',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final district in _districts)
                CarHireChoiceChip(
                  label: district.$2,
                  selected: value.allowedDistricts.contains(district.$1.trim()),
                  onTap: () => _toggleDistrict(
                    district.$1.trim(),
                    !value.allowedDistricts.contains(district.$1.trim()),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        CarHireCheckRow(
          label: 'GPS alerts if the car leaves this area',
          subtitle: value.travelAreaMode == 'NATIONWIDE'
              ? 'You are alerted the moment the car is out of area'
              : 'Always on outside the area you set',
          value: value.geofenceAlerts,
          enabled: value.travelAreaMode == 'NATIONWIDE',
          onChanged: value.travelAreaMode == 'NATIONWIDE'
              ? (checked) => onChanged(value.copyWith(geofenceAlerts: checked))
              : null,
        ),
        const CarHireFieldLabel('Fuel return'),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            CarHireChoiceChip(
              label: 'Same level',
              selected: value.fuelPolicy == 'SAME_LEVEL',
              onTap: () => onChanged(value.copyWith(fuelPolicy: 'SAME_LEVEL')),
            ),
            CarHireChoiceChip(
              label: 'As stated',
              selected: value.fuelPolicy == 'LISTING_STATED',
              onTap: () =>
                  onChanged(value.copyWith(fuelPolicy: 'LISTING_STATED')),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const CarHireFieldLabel('Daily mileage allowance (km)'),
        TextFormField(
          initialValue: value.mileageAllowanceKm?.toStringAsFixed(0) ?? '',
          keyboardType: TextInputType.number,
          decoration: carHireInputDecoration(
            hint: 'No limit',
            helper: 'Leave empty for no stated limit.',
          ),
          onChanged: (text) => onChanged(
            value.copyWith(
              mileageAllowanceKm: text.trim().isEmpty
                  ? null
                  : double.tryParse(text),
            ),
          ),
        ),
        if (value.mileageAllowanceKm != null) ...[
          const SizedBox(height: 12),
          const CarHireFieldLabel('Extra km rate (MWK)'),
          TextFormField(
            initialValue: value.extraKmRate?.toStringAsFixed(0) ?? '',
            keyboardType: TextInputType.number,
            decoration: carHireInputDecoration(
              hint: '1500',
              helper: 'Charged per km beyond the daily allowance.',
            ),
            onChanged: (text) =>
                onChanged(value.copyWith(extraKmRate: double.tryParse(text))),
          ),
        ],
        const SizedBox(height: 12),
        const CarHireFieldLabel('House notes (not legal terms)'),
        TextFormField(
          initialValue: value.houseNotes,
          maxLength: 400,
          maxLines: 3,
          decoration: carHireInputDecoration(
            hint: 'Anything a renter should know before booking',
            helper: 'Shown on the listing. Platform terms above always apply.',
            alignLabelWithHint: true,
          ),
          onChanged: (text) => onChanged(value.copyWith(houseNotes: text)),
        ),
      ],
    );
  }
}

/// The platform terms, stated once as a quiet note instead of a checkbox list.
class _VeroNote extends StatelessWidget {
  const _VeroNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
      decoration: BoxDecoration(
        color: CarHirePalette.accentPale,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CarHirePalette.accentSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.verified_user_outlined,
            size: 15,
            color: CarHirePalette.onAccentSoft,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Always applied by Vero360',
                  style: CarHireType.label.copyWith(
                    color: CarHirePalette.onAccentSoft,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'In-app payment, Vero-held deposit, cancellation table, GPS '
                  'trip start, photo handover, no off-platform deals.',
                  style: CarHireType.bodySmall.copyWith(
                    fontSize: 11,
                    color: CarHirePalette.onAccentSoft,
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
