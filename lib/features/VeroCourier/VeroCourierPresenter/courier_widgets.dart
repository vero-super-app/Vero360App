import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:vero360_app/features/VeroCourier/Model/courier.models.dart';
import 'package:vero360_app/utils/merchant_contact_display.dart';

Color courierStatusColor(CourierStatus status, ColorScheme cs) {
  switch (status) {
    case CourierStatus.pending:
      return const Color(0xFFFFF4E5);
    case CourierStatus.accepted:
      return const Color(0xFFE8F4FD);
    case CourierStatus.onTheWay:
      return const Color(0xFFE8F8F1);
    case CourierStatus.delivered:
      return const Color(0xFFEAF7EE);
    case CourierStatus.cancelled:
      return const Color(0xFFFDEEEE);
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
      return const Color(0xFFB45309);
    case CourierStatus.accepted:
      return const Color(0xFF0369A1);
    case CourierStatus.onTheWay:
      return const Color(0xFF047857);
    case CourierStatus.delivered:
      return const Color(0xFF15803D);
    case CourierStatus.cancelled:
      return const Color(0xFFB91C1C);
  }
}

class CourierDeliveryCard extends StatelessWidget {
  static const _ink = Color(0xFF101010);
  static const _muted = Color(0xFF6B7280);
  static const _border = Color(0xFFECEEF2);
  static const _brandOrange = Color(0xFFFF8A00);

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
    final view = delivery.view;
    final hasGoods = (delivery.typeOfGoods ?? '').trim().isNotEmpty ||
        (delivery.descriptionOfGoods ?? '').trim().isNotEmpty;
    final hasNotes = (view.notes ?? '').trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 14),
            _buildPeopleRow(view),
            const SizedBox(height: 14),
            _buildRouteSection(),
            if (hasGoods) ...[
              const SizedBox(height: 14),
              _buildGoodsSection(),
            ],
            if (hasNotes) ...[
              const SizedBox(height: 14),
              _buildNotesSection(view.notes!),
            ],
            if (footer != null) ...[
              const SizedBox(height: 12),
              footer!,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Delivery #${delivery.courierId}',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: _ink,
              letterSpacing: -0.3,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: courierStatusColor(delivery.status, const ColorScheme.light()),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                courierStatusIcon(delivery.status),
                size: 13,
                color: courierStatusTextColor(
                  delivery.status,
                  const ColorScheme.light(),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                delivery.status.value,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: courierStatusTextColor(
                    delivery.status,
                    const ColorScheme.light(),
                  ),
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
    );
  }

  Widget _buildPeopleRow(CourierDeliveryView view) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _personSection(
            label: 'Sender',
            icon: PhosphorIconsBold.paperPlaneTilt,
            accent: const Color(0xFF2D9CDB),
            name: view.senderName,
            phone: view.senderPhone,
            location: view.senderCity,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _personSection(
            label: 'Receiver',
            icon: PhosphorIconsBold.user,
            accent: _brandOrange,
            name: view.recipientName,
            phone: view.recipientPhone,
            location: view.recipientAddress ?? delivery.dropoffLocation,
          ),
        ),
      ],
    );
  }

  Widget _personSection({
    required String label,
    required IconData icon,
    required Color accent,
    required String? name,
    required String? phone,
    required String? location,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: accent,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _personField('Name', name),
          _personField('Phone', _formatPhone(phone), isPhone: true),
          _personField('City', location),
        ],
      ),
    );
  }

  String _formatPhone(String? raw) {
    final display = safeMerchantPhone(raw);
    return display == 'No phone number' ? 'No phone' : display;
  }

  Widget _personField(String label, String? value, {bool isPhone = false}) {
    final text = (value ?? '').trim();
    final isMissing = text.isEmpty || (isPhone && text == 'No phone');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: _muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text.isEmpty ? '—' : text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isMissing ? FontWeight.w400 : FontWeight.w600,
                color: isMissing ? _muted : _ink,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _routeStop(
            icon: PhosphorIconsFill.mapPin,
            iconColor: const Color(0xFF27AE60),
            label: 'Pickup',
            value: delivery.pickupLocation,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 9),
            child: Row(
              children: [
                Container(
                  width: 2,
                  height: 18,
                  color: const Color(0xFFD1D5DB),
                ),
              ],
            ),
          ),
          _routeStop(
            icon: PhosphorIconsFill.mapPin,
            iconColor: const Color(0xFFEB5757),
            label: 'Drop-off',
            value: delivery.dropoffLocation,
          ),
        ],
      ),
    );
  }

  Widget _routeStop({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    final text = value.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                text.isEmpty ? '—' : text,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: text.isEmpty ? _muted : _ink,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGoodsSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _brandOrange.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                PhosphorIconsBold.package,
                size: 14,
                color: _brandOrange,
              ),
              const SizedBox(width: 6),
              const Text(
                'Package details',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: _brandOrange,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if ((delivery.typeOfGoods ?? '').trim().isNotEmpty)
            _goodsRow('Type', delivery.typeOfGoods!),
          if ((delivery.descriptionOfGoods ?? '').trim().isNotEmpty)
            _goodsRow('Description', delivery.descriptionOfGoods!),
        ],
      ),
    );
  }

  Widget _goodsRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: _muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim(),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _ink,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesSection(String notes) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                PhosphorIconsRegular.note,
                size: 14,
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 6),
              Text(
                'Notes',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            notes.trim(),
            style: const TextStyle(
              fontSize: 13,
              color: _ink,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
