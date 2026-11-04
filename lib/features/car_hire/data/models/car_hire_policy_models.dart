class CarHirePolicyChip {
  const CarHirePolicyChip({
    required this.id,
    required this.label,
    this.allowed,
    this.value,
  });

  final String id;
  final String label;
  final bool? allowed;
  final String? value;

  factory CarHirePolicyChip.fromJson(dynamic raw) {
    final json = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return CarHirePolicyChip(
      id: (json['id'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      allowed: json['allowed'] is bool ? json['allowed'] as bool : null,
      value: json['value']?.toString(),
    );
  }
}

class CarHireListingPolicies {
  const CarHireListingPolicies({
    this.rentalModes = const <String>['SELF_DRIVE'],
    this.extraDriversAllowed = false,
    this.extraDriversMax = 0,
    this.smokingAllowed = false,
    this.petsAllowed = false,
    this.crossBorderAllowed = false,
    this.offRoadAllowed = false,
    this.mileageAllowanceKm,
    this.extraKmRate,
    this.fuelPolicy = 'SAME_LEVEL',
    this.deliveryOffered = false,
    this.travelAreaMode = 'NATIONWIDE',
    this.hireAreaRadiusKm = 25,
    this.allowedDistricts = const <String>[],
    this.geofenceAlerts = true,
    this.immobilizeAvailable = false,
    this.houseNotes = '',
    this.chips = const <CarHirePolicyChip>[],
    this.policyVersion = '1.0',
  });

  final List<String> rentalModes;
  final bool extraDriversAllowed;
  final int extraDriversMax;
  final bool smokingAllowed;
  final bool petsAllowed;
  final bool crossBorderAllowed;
  final bool offRoadAllowed;
  final double? mileageAllowanceKm;
  final double? extraKmRate;
  final String fuelPolicy;
  final bool deliveryOffered;
  final String travelAreaMode;
  final int hireAreaRadiusKm;
  final List<String> allowedDistricts;
  final bool geofenceAlerts;
  final bool immobilizeAvailable;
  final String houseNotes;
  final List<CarHirePolicyChip> chips;
  final String policyVersion;

  bool get offersSelfDrive => rentalModes.contains('SELF_DRIVE');
  bool get offersWithDriver => rentalModes.contains('WITH_DRIVER');
  bool get offersBoth => offersSelfDrive && offersWithDriver;

  factory CarHireListingPolicies.fromJson(dynamic raw) {
    final json = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final modes = (json['rentalModes'] is List)
        ? (json['rentalModes'] as List)
            .map((item) => item.toString().toUpperCase())
            .where((item) => item == 'SELF_DRIVE' || item == 'WITH_DRIVER')
            .toList()
        : <String>['SELF_DRIVE'];
    final chips = (json['chips'] is List)
        ? (json['chips'] as List)
            .map(CarHirePolicyChip.fromJson)
            .where((chip) => chip.label.isNotEmpty)
            .toList()
        : const <CarHirePolicyChip>[];
    final platform = json['platformPolicy'];
    final version = platform is Map
        ? (platform['version'] ?? '1.0').toString()
        : (json['version'] ?? '1.0').toString();
    return CarHireListingPolicies(
      rentalModes: modes.isEmpty ? const <String>['SELF_DRIVE'] : modes,
      extraDriversAllowed: json['extraDriversAllowed'] == true,
      extraDriversMax: int.tryParse('${json['extraDriversMax'] ?? 0}') ?? 0,
      smokingAllowed: json['smokingAllowed'] == true,
      petsAllowed: json['petsAllowed'] == true,
      crossBorderAllowed: json['crossBorderAllowed'] == true,
      offRoadAllowed: json['offRoadAllowed'] == true,
      mileageAllowanceKm: double.tryParse('${json['mileageAllowanceKm'] ?? ''}'),
      extraKmRate: double.tryParse('${json['extraKmRate'] ?? ''}'),
      fuelPolicy: (json['fuelPolicy'] ?? 'SAME_LEVEL').toString(),
      deliveryOffered: json['deliveryOffered'] == true,
      travelAreaMode: (json['travelAreaMode'] ?? 'NATIONWIDE').toString(),
      hireAreaRadiusKm: int.tryParse('${json['hireAreaRadiusKm'] ?? 25}') ?? 25,
      allowedDistricts: (json['allowedDistricts'] is List)
          ? (json['allowedDistricts'] as List).map((item) => item.toString()).toList()
          : const <String>[],
      geofenceAlerts: json['geofenceAlerts'] != false,
      immobilizeAvailable: json['immobilizeAvailable'] == true,
      houseNotes: (json['houseNotes'] ?? '').toString(),
      chips: chips,
      policyVersion: version,
    );
  }

  Map<String, dynamic> toPayload() {
    return <String, dynamic>{
      'rentalModes': rentalModes,
      'extraDriversAllowed': extraDriversAllowed,
      'extraDriversMax': extraDriversMax,
      'smokingAllowed': smokingAllowed,
      'petsAllowed': petsAllowed,
      'crossBorderAllowed': crossBorderAllowed,
      'offRoadAllowed': offRoadAllowed,
      'mileageAllowanceKm': mileageAllowanceKm,
      'extraKmRate': extraKmRate,
      'fuelPolicy': fuelPolicy,
      'deliveryOffered': deliveryOffered,
      'travelAreaMode': travelAreaMode,
      'hireAreaRadiusKm': hireAreaRadiusKm,
      'allowedDistricts': allowedDistricts,
      'geofenceAlerts': geofenceAlerts,
      'immobilizeAvailable': immobilizeAvailable,
      'houseNotes': houseNotes,
    };
  }

  CarHireListingPolicies copyWith({
    List<String>? rentalModes,
    bool? extraDriversAllowed,
    int? extraDriversMax,
    bool? smokingAllowed,
    bool? petsAllowed,
    bool? crossBorderAllowed,
    bool? offRoadAllowed,
    double? mileageAllowanceKm,
    double? extraKmRate,
    String? fuelPolicy,
    bool? deliveryOffered,
    String? travelAreaMode,
    int? hireAreaRadiusKm,
    List<String>? allowedDistricts,
    bool? geofenceAlerts,
    bool? immobilizeAvailable,
    String? houseNotes,
  }) {
    return CarHireListingPolicies(
      rentalModes: rentalModes ?? this.rentalModes,
      extraDriversAllowed: extraDriversAllowed ?? this.extraDriversAllowed,
      extraDriversMax: extraDriversMax ?? this.extraDriversMax,
      smokingAllowed: smokingAllowed ?? this.smokingAllowed,
      petsAllowed: petsAllowed ?? this.petsAllowed,
      crossBorderAllowed: crossBorderAllowed ?? this.crossBorderAllowed,
      offRoadAllowed: offRoadAllowed ?? this.offRoadAllowed,
      mileageAllowanceKm: mileageAllowanceKm ?? this.mileageAllowanceKm,
      extraKmRate: extraKmRate ?? this.extraKmRate,
      fuelPolicy: fuelPolicy ?? this.fuelPolicy,
      deliveryOffered: deliveryOffered ?? this.deliveryOffered,
      travelAreaMode: travelAreaMode ?? this.travelAreaMode,
      hireAreaRadiusKm: hireAreaRadiusKm ?? this.hireAreaRadiusKm,
      allowedDistricts: allowedDistricts ?? this.allowedDistricts,
      geofenceAlerts: geofenceAlerts ?? this.geofenceAlerts,
      immobilizeAvailable: immobilizeAvailable ?? this.immobilizeAvailable,
      houseNotes: houseNotes ?? this.houseNotes,
      chips: chips,
      policyVersion: policyVersion,
    );
  }
}
