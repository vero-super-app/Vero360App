// lib/Pages/MerchantDashboards/taxi_merchant_dashboard.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:vero360_app/Pages/BottomNavbar.dart';
import 'package:vero360_app/Pages/MerchantDashboards/merchant_wallet.dart';
import 'package:vero360_app/services/merchant_service_helper.dart';

class TaxiMerchantDashboard extends StatefulWidget {
  final String email;
  const TaxiMerchantDashboard({super.key, required this.email});

  @override
  State<TaxiMerchantDashboard> createState() => _TaxiMerchantDashboardState();
}

class _TaxiMerchantDashboardState extends State<TaxiMerchantDashboard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final MerchantServiceHelper _helper = MerchantServiceHelper();
  
  Map<String, dynamic>? _merchantData;
  List<dynamic> _recentRides = [];
  List<dynamic> _vehicles = [];
  List<dynamic> _drivers = [];
  bool _isLoading = true;
  String _uid = '';
  String _businessName = '';
  double _walletBalance = 0;
  
  // Stats
  int _totalRides = 0;
  int _completedRides = 0;
  int _activeRides = 0;
  double _totalEarnings = 0;
  double _rating = 0.0;
  String _status = 'pending';

  @override
  void initState() {
    super.initState();
    _loadMerchantData();
    _startPeriodicUpdates();
  }

  void _startPeriodicUpdates() {
    Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _loadMerchantData();
      }
    });
  }

  Future<void> _loadMerchantData() async {
    setState(() => _isLoading = true);
    
    final prefs = await SharedPreferences.getInstance();
    _uid = _auth.currentUser?.uid ?? prefs.getString('uid') ?? '';
    _businessName = prefs.getString('business_name') ?? 'Taxi Service';
    
    if (_uid.isNotEmpty) {
      try {
        final dashboardData = await _helper.getMerchantDashboardData(_uid, 'taxi');
        
        if (!dashboardData.containsKey('error')) {
          setState(() {
            _merchantData = dashboardData['merchant'];
            _recentRides = dashboardData['recentOrders'] ?? [];
            _totalRides = dashboardData['totalOrders'] ?? 0;
            _completedRides = dashboardData['completedOrders'] ?? 0;
            _totalEarnings = dashboardData['totalRevenue'] ?? 0;
            _rating = dashboardData['merchant']?['rating'] ?? 0.0;
            _status = dashboardData['merchant']?['status'] ?? 'pending';
          });
        }

        await _loadVehicles();
        await _loadDrivers();
        await _loadWalletBalance();
        await _calculateActiveRides();

      } catch (e) {
        print('Error loading taxi merchant data: $e');
      }
    }
    
    setState(() => _isLoading = false);
  }

  Future<void> _loadVehicles() async {
    try {
      final snapshot = await _firestore
          .collection('taxi_vehicles')
          .where('merchantId', isEqualTo: _uid)
          .get();
      
      _vehicles = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          ...data,
        };
      }).toList();
      
      if (mounted) setState(() {});
    } catch (e) {
      print('Error loading vehicles: $e');
    }
  }

  Future<void> _loadDrivers() async {
    try {
      final snapshot = await _firestore
          .collection('taxi_drivers')
          .where('merchantId', isEqualTo: _uid)
          .get();
      
      _drivers = snapshot.docs.map((doc) => doc.data()).toList();
      if (mounted) setState(() {});
    } catch (e) {
      print('Error loading drivers: $e');
    }
  }

  Future<void> _loadWalletBalance() async {
    try {
      final walletDoc = await _firestore
          .collection('merchant_wallets')
          .doc(_uid)
          .get();
      
      if (walletDoc.exists) {
        setState(() {
          _walletBalance = (walletDoc.data()?['balance'] ?? 0).toDouble();
        });
      }
    } catch (e) {
      print('Error loading wallet: $e');
    }
  }

  Future<void> _calculateActiveRides() async {
    try {
      final snapshot = await _firestore
          .collection('taxi_rides')
          .where('merchantId', isEqualTo: _uid)
          .where('status', whereIn: ['requested', 'accepted', 'in_progress'])
          .get();
      
      setState(() {
        _activeRides = snapshot.size;
      });
    } catch (e) {
      print('Error calculating active rides: $e');
    }
  }

  Future<void> _updateRideStatus(String rideId, String status) async {
    try {
      await _firestore
          .collection('taxi_rides')
          .doc(rideId)
          .update({
            'status': status,
            'updatedAt': FieldValue.serverTimestamp(),
          });
      
      _loadMerchantData();
    } catch (e) {
      print('Error updating ride: $e');
    }
  }

  // ADD THIS METHOD TO FIX THE _StatCard ERROR
  Widget _StatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Taxi Merchant Dashboard'),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.directions_car),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => Bottomnavbar(email: widget.email),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MerchantWalletPage(
                    merchantId: _uid, 
                    merchantName: _businessName, 
                    serviceType: 'taxi',
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome Section
                  _buildWelcomeSection(),
                  
                  // Stats Overview
                  _buildStatsSection(),
                  
                  // Quick Actions
                  _buildQuickActions(),
                  
                  // Wallet Summary
                  _buildWalletSummary(),
                  
                  // Recent Rides
                  _buildRecentRides(),
                  
                  // Vehicles
                  _buildVehiclesSection(),
                  
                  // Drivers
                  _buildDriversSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildWelcomeSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.local_taxi, size: 50, color: Colors.blue),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _businessName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text('Taxi Service Provider'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Chip(
                        label: Text(_status.toUpperCase()),
                        backgroundColor: _status == 'approved' 
                            ? Colors.green[100] 
                            : _status == 'pending'
                              ? Colors.orange[100]
                              : Colors.red[100],
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        label: Row(
                          children: [
                            const Icon(Icons.star, size: 14),
                            Text(' ${_rating.toStringAsFixed(1)}'),
                          ],
                        ),
                        backgroundColor: Colors.amber[100],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text(
          'Business Overview',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: [
            _StatCard(
              title: 'Total Rides',
              value: '$_totalRides',
              icon: Icons.directions_car,
              color: Colors.blue,
            ),
            _StatCard(
              title: 'Total Earnings',
              value: 'MWK ${_totalEarnings.toStringAsFixed(2)}',
              icon: Icons.attach_money,
              color: Colors.green,
            ),
            _StatCard(
              title: 'Active Rides',
              value: '$_activeRides',
              icon: Icons.timer,
              color: Colors.orange,
            ),
            _StatCard(
              title: 'Completed',
              value: '$_completedRides',
              icon: Icons.check_circle,
              color: Colors.purple,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text(
          'Quick Actions',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ActionChip(
              avatar: const Icon(Icons.add_circle, size: 20),
              label: const Text('Add Vehicle'),
              onPressed: () {
                // Add vehicle
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.person_add, size: 20),
              label: const Text('Add Driver'),
              onPressed: () {
                // Add driver
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.analytics, size: 20),
              label: const Text('Analytics'),
              onPressed: () {
                // Analytics
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.map, size: 20),
              label: const Text('Live Tracking'),
              onPressed: () {
                // Live tracking
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.settings, size: 20),
              label: const Text('Settings'),
              onPressed: () {
                // Settings
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWalletSummary() {
    return Card(
      margin: const EdgeInsets.only(top: 20),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Wallet Balance',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'MWK ${_walletBalance.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MerchantWalletPage(
                          merchantId: _uid,
                          merchantName: _businessName,
                          serviceType: 'taxi',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.account_balance_wallet),
                  label: const Text('View Wallet'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Earnings from completed rides',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentRides() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Rides',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {
                // View all rides
              },
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_recentRides.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No rides yet')),
            ),
          )
        else
          ..._recentRides.take(3).map((ride) {
            final rideMap = ride as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.local_taxi, color: Colors.blue),
                title: Text('Ride #${rideMap['rideId']?.toString().substring(0, 8) ?? 'N/A'}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('From: ${rideMap['pickupLocation'] ?? 'N/A'}'),
                    Text('To: ${rideMap['dropoffLocation'] ?? 'N/A'}'),
                    Text('Fare: MWK ${rideMap['fare'] ?? '0'}'),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Chip(
                      label: Text(rideMap['status'] ?? 'pending'),
                      backgroundColor: _getRideStatusColor(rideMap['status']),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_vert),
                      onPressed: () {
                        _showRideActions(rideMap);
                      },
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
      ],
    );
  }

  Widget _buildVehiclesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Vehicles',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            TextButton(
              onPressed: () {
                // Add vehicle
              },
              child: const Text('Add Vehicle'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_vehicles.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No vehicles yet')),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.9,
            ),
            itemCount: _vehicles.length,
            itemBuilder: (context, index) {
              final vehicle = _vehicles[index] as Map<String, dynamic>;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.directions_car,
                        size: 40,
                        color: Colors.blue,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${vehicle['make']} ${vehicle['model']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Plate: ${vehicle['licensePlate'] ?? 'N/A'}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Chip(
                            label: Text(
                              vehicle['type'] ?? 'Standard',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          const Spacer(),
                          Chip(
                            label: Text(
                              vehicle['isAvailable'] == true ? 'Available' : 'Busy',
                              style: TextStyle(
                                color: vehicle['isAvailable'] == true 
                                    ? Colors.green 
                                    : Colors.red,
                              ),
                            ),
                            backgroundColor: vehicle['isAvailable'] == true 
                                ? Colors.green[50] 
                                : Colors.red[50],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildDriversSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text(
          'Drivers',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        if (_drivers.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('No drivers yet')),
            ),
          )
        else
          ..._drivers.map((driver) {
            final driverMap = driver as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue[100],
                  child: Text(
                    driverMap['name']?.toString().substring(0, 1) ?? 'D',
                    style: const TextStyle(color: Colors.blue),
                  ),
                ),
                title: Text(driverMap['name'] ?? 'Unknown Driver'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Phone: ${driverMap['phone'] ?? 'N/A'}'),
                    Text('License: ${driverMap['licenseNumber'] ?? 'N/A'}'),
                  ],
                ),
                trailing: Chip(
                  label: Text(
                    driverMap['status'] ?? 'inactive',
                    style: TextStyle(
                      color: driverMap['status'] == 'active' 
                          ? Colors.green 
                          : Colors.red,
                    ),
                  ),
                  backgroundColor: driverMap['status'] == 'active' 
                      ? Colors.green[50] 
                      : Colors.red[50],
                ),
              ),
            );
          }).toList(),
      ],
    );
  }

  Color _getRideStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'completed':
        return Colors.green[100]!;
      case 'in_progress':
        return Colors.blue[100]!;
      case 'accepted':
        return Colors.orange[100]!;
      case 'requested':
        return Colors.yellow[100]!;
      case 'cancelled':
        return Colors.red[100]!;
      default:
        return Colors.grey[100]!;
    }
  }

  void _showRideActions(Map<String, dynamic> ride) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.visibility),
                title: const Text('View Details'),
                onTap: () {
                  Navigator.pop(context);
                  // View ride details
                },
              ),
              ListTile(
                leading: const Icon(Icons.check_circle),
                title: const Text('Accept Ride'),
                onTap: () {
                  Navigator.pop(context);
                  _updateRideStatus(ride['id'], 'accepted');
                },
              ),
              ListTile(
                leading: const Icon(Icons.directions_car),
                title: const Text('Start Ride'),
                onTap: () {
                  Navigator.pop(context);
                  _updateRideStatus(ride['id'], 'in_progress');
                },
              ),
              ListTile(
                leading: const Icon(Icons.done_all),
                title: const Text('Complete Ride'),
                onTap: () {
                  Navigator.pop(context);
                  _updateRideStatus(ride['id'], 'completed');
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel),
                title: const Text('Cancel Ride'),
                onTap: () {
                  Navigator.pop(context);
                  _updateRideStatus(ride['id'], 'cancelled');
                },
              ),
            ],
          ),
        );
      },
    );
  }
}