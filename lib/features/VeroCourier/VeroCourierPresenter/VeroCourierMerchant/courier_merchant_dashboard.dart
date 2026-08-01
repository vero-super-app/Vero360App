import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:vero360_app/GernalServices/api_exception.dart';
import 'package:vero360_app/features/VeroCourier/Model/courier.models.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierPresenter/courier_widgets.dart';
import 'package:vero360_app/features/VeroCourier/VeroCourierService/vero_courier_service.dart';

class CourierMerchantDashboard extends StatefulWidget {
  final String email;
  const CourierMerchantDashboard({super.key, required this.email});

  @override
  State<CourierMerchantDashboard> createState() => _CourierMerchantDashboardState();
}

class _CourierMerchantDashboardState extends State<CourierMerchantDashboard> {
  static const _skyBlue = Color(0xFF2D9CDB);
  static const _mintGreen = Color(0xFF27AE60);
  static const _violet = Color(0xFF9B51E0);
  static const _rose = Color(0xFFEB5757);

  final CourierService _service = const CourierService();

  List<CourierDelivery> _all = const [];
  bool _loading = true;
  bool _busy = false;
  CourierStatus? _filter;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final data = await _service.getAllDeliveries();
      if (!mounted) return;
      setState(() => _all = data);
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Failed to fetch courier deliveries.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(CourierDelivery d, CourierStatus status) async {
    setState(() => _busy = true);
    try {
      await _service.updateStatus(id: d.courierId, status: status);
      _toast('Delivery #${d.courierId} updated to ${status.value}.');
      await _reload();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Could not update status.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(CourierDelivery d) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Delivery'),
            content: Text('Delete delivery #${d.courierId}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    setState(() => _busy = true);
    try {
      await _service.deleteDelivery(d.courierId);
      _toast('Delivery #${d.courierId} deleted.');
      await _reload();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Could not delete delivery.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deliveries = _filter == null
        ? _all
        : _all.where((d) => d.status == _filter).toList();

    final total = _all.length;
    final pending = _all.where((d) => d.status == CourierStatus.pending).length;
    final active = _all
        .where(
          (d) =>
              d.status == CourierStatus.accepted || d.status == CourierStatus.onTheWay,
        )
        .length;
    final done = _all.where((d) => d.status == CourierStatus.delivered).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Courier Merchant Dashboard'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _reload,
            icon: const Icon(PhosphorIconsBold.arrowsClockwise),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _countCard('Total', total, PhosphorIconsBold.package, _skyBlue),
                _countCard('Pending', pending, PhosphorIconsBold.hourglassMedium, _violet),
                _countCard('Active', active, PhosphorIconsBold.truck, _mintGreen),
                _countCard('Delivered', done, PhosphorIconsBold.checkCircle, _rose),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Filter by status',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                  const SizedBox(width: 8),
                  ...CourierStatus.values.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(s.value),
                        selected: _filter == s,
                        onSelected: (_) => setState(() => _filter = s),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (deliveries.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('No deliveries for selected filter.'),
                ),
              )
            else
              ...deliveries.map((d) => _deliveryTile(context, d)),
          ],
        ),
      ),
    );
  }

  Widget _countCard(String title, int value, IconData icon, Color accent) {
    return Container(
      width: 165,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 12)),
              Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _deliveryTile(BuildContext context, CourierDelivery d) {
    return CourierDeliveryCard(
      delivery: d,
      trailing: PopupMenuButton<String>(
        enabled: !_busy,
        icon: const Icon(PhosphorIconsBold.dotsThreeVertical),
        onSelected: (value) async {
          if (value == 'delete') {
            await _delete(d);
            return;
          }
          final selectedStatus = CourierStatus.values.firstWhere(
            (s) => s.value == value,
            orElse: () => d.status,
          );
          if (selectedStatus != d.status) {
            await _setStatus(d, selectedStatus);
          }
        },
        itemBuilder: (_) => [
          ...CourierStatus.values.map(
            (status) => PopupMenuItem<String>(
              value: status.value,
              child: Text('Set ${status.value}'),
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<String>(
            value: 'delete',
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }
}