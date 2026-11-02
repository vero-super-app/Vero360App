import 'package:flutter/material.dart';
import 'package:vero360_app/features/car_hire/data/models/car_hire_policy_models.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/utils/car_hire_routes.dart';

class CarHirePolicyBlock extends StatelessWidget {
  const CarHirePolicyBlock({
    super.key,
    required this.policies,
    this.title = 'Vero360 rental rules',
  });

  final CarHireListingPolicies policies;
  final String title;

  @override
  Widget build(BuildContext context) {
    final chips = policies.chips.isNotEmpty
        ? policies.chips
        : <CarHirePolicyChip>[
            CarHirePolicyChip(
              id: 'self',
              label: policies.offersSelfDrive ? 'Self-drive' : 'No self-drive',
              allowed: policies.offersSelfDrive,
            ),
            CarHirePolicyChip(
              id: 'driver',
              label: policies.offersWithDriver ? 'With driver' : 'No provided driver',
              allowed: policies.offersWithDriver,
            ),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: CarHireType.title.copyWith(fontSize: 14)),
        const SizedBox(height: 6),
        Text(
          'These are the policies Vero uses, plus the rules this listing has ticked.',
          style: CarHireType.bodySmall,
        ),
        const SizedBox(height: 10),
        const Text(
          'Vero360 is the facilitator. Pay in the App. The deposit is held by Vero360. '
          'Handover uses photos and GPS. Self-drive needs a valid licence.',
          style: CarHireType.bodySmall,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final chip in chips)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: chip.allowed == false
                      ? const Color(0xFFF8FAFC)
                      : CarHirePalette.accentPale,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  chip.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: chip.allowed == false
                        ? CarHirePalette.muted
                        : CarHirePalette.onAccentSoft,
                  ),
                ),
              ),
          ],
        ),
        if (policies.houseNotes.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(policies.houseNotes.trim(), style: CarHireType.body),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => CarHireRoutes.openTerms(context),
            child: const Text('Read the Vero360 Car Hire Service Policy'),
          ),
        ),
      ],
    );
  }
}
