import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:vero360_app/features/VeroCourier/Model/courier.models.dart';

Color courierStatusColor(CourierStatus status, ColorScheme cs) {
  switch (status) {
    case CourierStatus.pending:
      return cs.surfaceContainerHighest;
    case CourierStatus.accepted:
      return cs.primaryContainer;
    case CourierStatus.onTheWay:
      return cs.tertiaryContainer;
    case CourierStatus.delivered:
      return cs.secondaryContainer;
    case CourierStatus.cancelled:
      return cs.errorContainer;
  }
}

IconData courierStatusIcon(CourierStatus status) {
  switch (status) {
    case CourierStatus.pending:
      return PhosphorIconsBold.hourglassMedium;
    case CourierStatus.accepted:
      return PhosphorIconsBold.handWaving;
    case CourierStatus.onTheWay:
      return PhosphorIconsBold.truck;
    case CourierStatus.delivered:
      return PhosphorIconsBold.checkCircle;
    case CourierStatus.cancelled:
      return PhosphorIconsBold.xCircle;
  }
}

Color courierStatusTextColor(CourierStatus status, ColorScheme cs) {
  switch (status) {
    case CourierStatus.pending:
      return cs.onSurfaceVariant;
    case CourierStatus.accepted:
      return cs.onPrimaryContainer;
    case CourierStatus.onTheWay:
      return cs.onTertiaryContainer;
    case CourierStatus.delivered:
      return cs.onSecondaryContainer;
    case CourierStatus.cancelled:
      return cs.onErrorContainer;
  }
}

class CourierDeliveryCard extends StatelessWidget {
  final CourierDelivery delivery;
  final Widget? trailing;
  final Widget? footer;

  const CourierDeliveryCard({
    super.key,
    required this.delivery,
    this.trailing,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Delivery #${delivery.courierId}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  decoration: BoxDecoration(
                    color: courierStatusColor(delivery.status, cs),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        courierStatusIcon(delivery.status),
                        size: 13,
                        color: courierStatusTextColor(delivery.status, cs),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        delivery.status.value,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: courierStatusTextColor(delivery.status, cs),
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 4),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: 8),
            _lineItem(
              icon: PhosphorIconsRegular.phone,
              label: 'Phone',
              value: delivery.courierPhone,
            ),
            _lineItem(
              icon: PhosphorIconsRegular.mapPin,
              label: 'City',
              value: delivery.courierCity,
            ),
            const SizedBox(height: 6),
            _lineItem(
              icon: PhosphorIconsRegular.uploadSimple,
              label: 'Pickup',
              value: delivery.pickupLocation,
            ),
            _lineItem(
              icon: PhosphorIconsRegular.downloadSimple,
              label: 'Dropoff',
              value: delivery.dropoffLocation,
            ),
            if ((delivery.typeOfGoods ?? '').isNotEmpty)
              _lineItem(
                icon: PhosphorIconsRegular.package,
                label: 'TypeOfGoods',
                value: delivery.typeOfGoods!,
              ),
            if ((delivery.descriptionOfGoods ?? '').isNotEmpty)
              _lineItem(
                icon: PhosphorIconsRegular.notePencil,
                label: 'DescriptionOfGoods',
                value: delivery.descriptionOfGoods!,
              ),
            if ((delivery.additionalInformation ?? '').isNotEmpty)
              _lineItem(
                icon: PhosphorIconsRegular.info,
                label: 'AdditionalInformation',
                value: delivery.additionalInformation!,
              ),
            if (footer != null) ...[
              const SizedBox(height: 10),
              footer!,
            ],
          ],
        ),
      ),
    );
  }

  Widget _lineItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF8A8A8A)),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4A4A4A),
                    ),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

