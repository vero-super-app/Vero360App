enum BookingStatus { pending, confirmed, active, completed }

class CarBookingModel {
  final int id;
  final int carId;
  final int userId;
  final DateTime startDate;
  final DateTime endDate;
  final double totalCost;
  final BookingStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Optional: car details for convenience
  final String? carBrand;
  final String? carModel;
  final String? carImage;

  CarBookingModel({
    required this.id,
    required this.carId,
    required this.userId,
    required this.startDate,
    required this.endDate,
    required this.totalCost,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.carBrand,
    this.carModel,
    this.carImage,
  });

  bool get isActive => status == BookingStatus.active;
  bool get isPending => status == BookingStatus.pending;
  bool get isConfirmed => status == BookingStatus.confirmed;
  bool get isCompleted => status == BookingStatus.completed;

  String get statusString {
    switch (status) {
      case BookingStatus.pending:
        return 'Pending';
      case BookingStatus.confirmed:
        return 'Confirmed';
      case BookingStatus.active:
        return 'Active';
      case BookingStatus.completed:
        return 'Completed';
    }
  }

  factory CarBookingModel.fromJson(Map<String, dynamic> json) {
    final statusStr = (json['status'] ?? 'PENDING').toString().toUpperCase();

    return CarBookingModel(
      id: json['id'] ?? 0,
      carId: json['carId'] ?? json['car_id'] ?? 0,
      userId: json['userId'] ?? json['user_id'] ?? 0,
      startDate: json['startDate'] != null
          ? DateTime.parse(json['startDate'].toString())
          : DateTime.now(),
      endDate: json['endDate'] != null
          ? DateTime.parse(json['endDate'].toString())
          : DateTime.now(),
      totalCost: (json['totalCost'] ?? json['total_cost'] ?? 0).toDouble(),
      status: _parseStatus(statusStr),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'].toString())
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'].toString())
          : DateTime.now(),
      carBrand: json['car']?['brand'] ?? json['carBrand'],
      carModel: json['car']?['model'] ?? json['carModel'],
      carImage: json['car']?['imageUrl'] ?? json['carImage'],
    );
  }

  static BookingStatus _parseStatus(String status) {
    switch (status) {
      case 'CONFIRMED':
        return BookingStatus.confirmed;
      case 'ACTIVE':
        return BookingStatus.active;
      case 'COMPLETED':
        return BookingStatus.completed;
      default:
        return BookingStatus.pending;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'carId': carId,
        'userId': userId,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'totalCost': totalCost,
        'status': status.name.toUpperCase(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  CarBookingModel copyWith({
    int? id,
    int? carId,
    int? userId,
    DateTime? startDate,
    DateTime? endDate,
    double? totalCost,
    BookingStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? carBrand,
    String? carModel,
    String? carImage,
  }) {
    return CarBookingModel(
      id: id ?? this.id,
      carId: carId ?? this.carId,
      userId: userId ?? this.userId,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      totalCost: totalCost ?? this.totalCost,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      carBrand: carBrand ?? this.carBrand,
      carModel: carModel ?? this.carModel,
      carImage: carImage ?? this.carImage,
    );
  }
}
