import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vero360_app/Home/CustomersProfilepage.dart';
import 'package:vero360_app/features/ride_share/presentation/providers/driver_provider.dart';

class DriverProfileSettings extends ConsumerStatefulWidget {
  const DriverProfileSettings({super.key});

  @override
  ConsumerState<DriverProfileSettings> createState() =>
      _DriverProfileSettingsState();
}

class _DriverProfileSettingsState extends ConsumerState<DriverProfileSettings>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const Color _brandOrange = Color(0xFFFF8A00);
  static const Color _brandNavy = Color(0xFF16284C);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & Settings'),
        backgroundColor: _brandNavy,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _brandOrange,
          tabs: const [
            Tab(text: 'Personal'),
            Tab(text: 'Driver Info'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Personal Profile (reuse ProfilePage)
          const ProfilePage(),
          // Tab 2: Driver-specific info
          _buildDriverInfoTab(),
        ],
      ),
    );
  }

  Widget _buildDriverInfoTab() {
    final driverData = ref.watch(myDriverProfileProvider);

    return driverData.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: _brandOrange),
      ),
      error: (err, stack) => Center(
        child: Text('Error: $err'),
      ),
      data: (driver) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Driver Status Card
              _buildDriverStatusCard(driver),
              const SizedBox(height: 20),

              // Verification Status
              _buildVerificationSection(driver),
              const SizedBox(height: 20),

              // Taxi Information
              _buildTaxiSection(driver),
              const SizedBox(height: 20),

              // Driver Stats
              _buildDriverStatsSection(driver),
              const SizedBox(height: 20),

              // Quick Actions
              _buildQuickActionsSection(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDriverStatusCard(Map<String, dynamic> driver) {
    final status = (driver['status'] ?? 'INACTIVE').toString();
    final totalRides = driver['totalRides'] ?? 0;
    final rating = (driver['rating'] ?? 0.0).toStringAsFixed(1);
    final isVerified = driver['verified'] ?? false;

    final statusColor = status == 'ACTIVE' ? Colors.green : Colors.orange;
    final statusLabel = status == 'ACTIVE' ? 'Online' : 'Offline';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Driver Status',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatItem('Rides', '$totalRides'),
              _buildStatItem('Rating', '$rating★'),
              _buildStatItem('Verified', isVerified ? '✓' : 'Pending'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _brandOrange,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildVerificationSection(Map<String, dynamic> driver) {
    final isVerified = driver['verified'] ?? false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isVerified ? Colors.green.withValues(alpha: 0.05) : Colors.amber.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isVerified ? Colors.green : Colors.amber,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isVerified ? Icons.verified : Icons.pending_actions,
                color: isVerified ? Colors.green : Colors.amber,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isVerified ? 'Verified Driver' : 'Verification Pending',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isVerified ? Colors.green : Colors.amber[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isVerified
                        ? 'Your profile has been verified'
                        : 'Submit documents to get verified',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTaxiSection(Map<String, dynamic> driver) {
    final taxis = (driver['taxis'] as List?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Registered Taxis',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        if (taxis.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Center(
              child: Text(
                'No taxis registered',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          )
        else
          ...taxis.map<Widget>((taxi) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${taxi['make']} ${taxi['model']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: (taxi['isAvailable'] ?? false)
                              ? Colors.green.withValues(alpha: 0.2)
                              : Colors.grey.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          (taxi['isAvailable'] ?? false) ? 'Available' : 'Unavailable',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: (taxi['isAvailable'] ?? false)
                                ? Colors.green
                                : Colors.grey[600],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildTaxiDetailRow('License Plate', taxi['licensePlate']),
                  _buildTaxiDetailRow('Year', '${taxi['year']}'),
                  _buildTaxiDetailRow('Seats', '${taxi['seats']}'),
                  _buildTaxiDetailRow('Class', taxi['taxiClass']),
                ],
              ),
            );
          }).toList(),
      ],
    );
  }

  Widget _buildTaxiDetailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          Text(
            value.toString(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDriverStatsSection(Map<String, dynamic> driver) {
    final totalEarnings = driver['totalEarnings'] ?? 0.0;
    final completedRides = driver['completedRides'] ?? 0;
    final cancelledRides = driver['cancelledRides'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Driver Statistics',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatCard('Total Earnings', 'MWK ${totalEarnings.toStringAsFixed(0)}'),
              _buildStatCard('Completed', '$completedRides'),
              _buildStatCard('Cancelled', '$cancelledRides'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: _brandOrange,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Wallet feature coming soon'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.wallet),
              label: const Text('View Wallet & Earnings'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandOrange,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
