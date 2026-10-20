import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vero360_app/features/car_hire/data/models/car_hire_company_models.dart';
import 'package:vero360_app/features/car_hire/presentation/providers/car_hire_company_providers.dart';
import 'package:vero360_app/features/car_hire/presentation/theme/car_hire_theme.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_company_widgets.dart';
import 'package:vero360_app/features/car_hire/presentation/widgets/car_hire_states.dart';
import 'package:vero360_app/utils/formatters.dart';

/// Every unit in the company fleet: plates, service due dates and quick
/// blocks. Pricing, photos and adding cars stay on the web workspace.
class CarHireCompanyFleetPage extends ConsumerWidget {
  const CarHireCompanyFleetPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(companyAccessProvider);

    return Scaffold(
      backgroundColor: CarHirePalette.background,
      appBar: carHireAppBar(title: 'Fleet'),
      body: access.when(
        loading: () => const CarHireLoadingState(message: 'Loading fleet…'),
        error: (error, _) => CarHireErrorState(
          error: error,
          onRetry: () => ref.invalidate(companyAccessProvider),
        ),
        data: (access) => _FleetView(access: access),
      ),
    );
  }
}

class _FleetView extends ConsumerWidget {
  const _FleetView({required this.access});

  final CompanyAccess access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleet = ref.watch(companyFleetProvider);
    final busy = ref.watch(companyActionProvider).submitting;

    Future<void> toggle(FleetUnit unit, bool inService) async {
      final ok = await ref.read(companyActionProvider.notifier).run(
            (api) => api.setUnitInService(unit.id, inService),
          );
      if (!context.mounted) return;
      if (ok) {
        showCompanySnack(
          context,
          inService
              ? '${unit.plateLabel} is back in service.'
              : '${unit.plateLabel} is out of service.',
        );
      } else {
        showCompanySnack(
          context,
          ref.read(companyActionProvider).error?.message ??
              'Could not update the car.',
          error: true,
        );
      }
    }

    return RefreshIndicator(
      color: CarHirePalette.accent,
      onRefresh: () => ref.refresh(companyFleetProvider.future),
      child: fleet.when(
        loading: () => const CarHireLoadingState(message: 'Loading fleet…'),
        error: (error, _) => ListView(
          children: [
            CarHireErrorState(
              error: error,
              onRetry: () => ref.invalidate(companyFleetProvider),
            ),
          ],
        ),
        data: (units) {
          if (units.isEmpty) {
            return ListView(
              children: const [
                CarHireEmptyState(
                  title: 'No cars yet',
                  message: 'Add cars and plates from the web workspace.',
                ),
              ],
            );
          }

          final listings = <String, List<FleetUnit>>{};
          for (final unit in units) {
            listings.putIfAbsent(unit.listingKey, () => <FleetUnit>[]).add(unit);
          }
          final outOfService = units.where((u) => !u.car.isAvailable).length;
          final dueSoon = units.where((u) => u.serviceDueSoon).length;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              if (!access.canManageFleet)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: CarHireInfoBanner(
                    icon: Icons.visibility_outlined,
                    title: 'View only',
                    message: 'Ask the company owner for the fleet permission '
                        'to take cars out of service or block dates.',
                  ),
                ),
              CarHireSurface(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    _FleetStat(label: 'Units', value: '${units.length}'),
                    _FleetStat(
                      label: 'In service',
                      value: '${units.length - outOfService}',
                    ),
                    _FleetStat(
                      label: 'Out',
                      value: '$outOfService',
                      tone: outOfService > 0 ? CarHirePalette.error : null,
                    ),
                    _FleetStat(
                      label: 'Service due',
                      value: '$dueSoon',
                      tone: dueSoon > 0 ? CarHirePalette.warning : null,
                    ),
                  ],
                ),
              ),
              for (final group in listings.values)
                CarHireSurface(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group.first.car.title, style: CarHireType.subtitle),
                      Text(
                        group.length == 1 ? '1 unit' : '${group.length} units',
                        style: CarHireType.labelSmall,
                      ),
                      const SizedBox(height: 4),
                      for (final unit in group)
                        _FleetUnitRow(
                          unit: unit,
                          canManage: access.canManageFleet,
                          busy: busy,
                          onToggle: (value) => toggle(unit, value),
                          onBlock: () =>
                              showCompanyBlockSheet(context, unit: unit),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _FleetStat extends StatelessWidget {
  const _FleetStat({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: CarHirePalette.onSurface,
            ).copyWith(color: tone),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: CarHireType.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _FleetUnitRow extends StatelessWidget {
  const _FleetUnitRow({
    required this.unit,
    required this.canManage,
    required this.busy,
    required this.onToggle,
    required this.onBlock,
  });

  final FleetUnit unit;
  final bool canManage;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback onBlock;

  @override
  Widget build(BuildContext context) {
    final inService = unit.car.isAvailable;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unit.plateLabel,
                  style: CarHireType.label.copyWith(
                    color: CarHirePalette.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 6,
                  children: [
                    Text(
                      inService ? 'In service' : 'Out of service',
                      style: CarHireType.labelSmall.copyWith(
                        color: inService
                            ? CarHirePalette.success
                            : CarHirePalette.error,
                      ),
                    ),
                    if (unit.serviceDueSoon)
                      Text(
                        'Service due '
                        '${CarHireFormatters.formatDate(unit.nextServiceDueAt!)}',
                        style: CarHireType.labelSmall.copyWith(
                          color: CarHirePalette.warning,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (canManage) ...[
            IconButton(
              tooltip: 'Block dates',
              onPressed: busy ? null : onBlock,
              icon: const Icon(Icons.event_busy_outlined, size: 20),
            ),
            Switch(
              value: inService,
              activeThumbColor: CarHirePalette.accent,
              onChanged: busy ? null : onToggle,
            ),
          ],
        ],
      ),
    );
  }
}
