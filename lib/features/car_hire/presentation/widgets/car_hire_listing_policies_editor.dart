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
    onChanged(value.copyWith(rentalModes: next.isEmpty ? <String>[mode] : next));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Always applied by Vero360', style: CarHireType.title.copyWith(fontSize: 13.5)),
        const SizedBox(height: 6),
        Text(
          'In-app payment, Vero-held deposit, cancellation table, GPS trip start, photo handover, no off-platform deals.',
          style: CarHireType.bodySmall,
        ),
        const SizedBox(height: 14),
        Text('Your listing rules', style: CarHireType.title.copyWith(fontSize: 13.5)),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Self-drive'),
          value: value.offersSelfDrive,
          onChanged: (_) => _toggleMode('SELF_DRIVE'),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('With driver'),
          value: value.offersWithDriver,
          onChanged: (_) => _toggleMode('WITH_DRIVER'),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Extra drivers'),
          value: value.extraDriversAllowed,
          onChanged: value.offersSelfDrive
              ? (checked) => onChanged(value.copyWith(extraDriversAllowed: checked ?? false))
              : null,
        ),
        if (value.extraDriversAllowed)
          TextFormField(
            initialValue: '${value.extraDriversMax > 0 ? value.extraDriversMax : 1}',
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Maximum extra drivers'),
            onChanged: (text) =>
                onChanged(value.copyWith(extraDriversMax: int.tryParse(text) ?? 1)),
          ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Smoking allowed'),
          value: value.smokingAllowed,
          onChanged: (checked) => onChanged(value.copyWith(smokingAllowed: checked ?? false)),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Pets allowed'),
          value: value.petsAllowed,
          onChanged: (checked) => onChanged(value.copyWith(petsAllowed: checked ?? false)),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Cross-border travel'),
          value: value.crossBorderAllowed,
          onChanged: (checked) => onChanged(value.copyWith(crossBorderAllowed: checked ?? false)),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Off-road use'),
          value: value.offRoadAllowed,
          onChanged: (checked) => onChanged(value.copyWith(offRoadAllowed: checked ?? false)),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Delivery / collection'),
          value: value.deliveryOffered,
          onChanged: (checked) => onChanged(value.copyWith(deliveryOffered: checked ?? false)),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Remote engine-off available'),
          value: value.immobilizeAvailable,
          onChanged: (checked) =>
              onChanged(value.copyWith(immobilizeAvailable: checked ?? false)),
        ),
        const SizedBox(height: 8),
        Text('Travel area', style: CarHireType.bodySmall.copyWith(fontWeight: FontWeight.w700)),
        DropdownButton<String>(
          isExpanded: true,
          value: value.travelAreaMode,
          items: const [
            DropdownMenuItem(value: 'NATIONWIDE', child: Text('Nationwide Malawi')),
            DropdownMenuItem(value: 'HIRE_AREA', child: Text('Hire area only')),
            DropdownMenuItem(value: 'DISTRICT', child: Text('Selected districts')),
          ],
          onChanged: (next) {
            if (next != null) onChanged(value.copyWith(travelAreaMode: next));
          },
        ),
        if (value.travelAreaMode == 'HIRE_AREA')
          TextFormField(
            initialValue: '${value.hireAreaRadiusKm}',
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Hire-area radius (km)'),
            onChanged: (text) =>
                onChanged(value.copyWith(hireAreaRadiusKm: int.tryParse(text) ?? 25)),
          ),
        if (value.travelAreaMode == 'DISTRICT')
          Wrap(
            spacing: 8,
            children: [
              for (final district in _districts)
                FilterChip(
                  label: Text(district.$2),
                  selected: value.allowedDistricts.contains(district.$1.trim()),
                  onSelected: (selected) {
                    final id = district.$1.trim();
                    final next = List<String>.from(value.allowedDistricts);
                    if (selected) {
                      next.add(id);
                    } else {
                      next.remove(id);
                    }
                    onChanged(value.copyWith(allowedDistricts: next));
                  },
                ),
            ],
          ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('GPS alerts if the car leaves this area'),
          value: value.geofenceAlerts,
          onChanged: value.travelAreaMode == 'NATIONWIDE'
              ? (checked) =>
                  onChanged(value.copyWith(geofenceAlerts: checked ?? false))
              : null,
        ),
        DropdownButtonFormField<String>(
          value: value.fuelPolicy,
          decoration: const InputDecoration(labelText: 'Fuel return'),
          items: const [
            DropdownMenuItem(value: 'SAME_LEVEL', child: Text('Same level as handover')),
            DropdownMenuItem(value: 'LISTING_STATED', child: Text('As stated on the listing')),
          ],
          onChanged: (next) {
            if (next != null) onChanged(value.copyWith(fuelPolicy: next));
          },
        ),
        TextFormField(
          initialValue: value.mileageAllowanceKm?.toStringAsFixed(0) ?? '',
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Daily mileage allowance (km)',
            hintText: 'Leave empty for no stated limit',
          ),
          onChanged: (text) => onChanged(
            value.copyWith(
              mileageAllowanceKm: text.trim().isEmpty
                  ? null
                  : double.tryParse(text),
            ),
          ),
        ),
        if (value.mileageAllowanceKm != null)
          TextFormField(
            initialValue: value.extraKmRate?.toStringAsFixed(0) ?? '',
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Extra km rate (MWK)'),
            onChanged: (text) => onChanged(
              value.copyWith(extraKmRate: double.tryParse(text)),
            ),
          ),
        TextFormField(
          initialValue: value.houseNotes,
          maxLength: 400,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'House notes (not legal terms)',
          ),
          onChanged: (text) => onChanged(value.copyWith(houseNotes: text)),
        ),
      ],
    );
  }
}
