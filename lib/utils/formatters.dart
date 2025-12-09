import 'package:intl/intl.dart';

class CarHireFormatters {
  static final _currencyFormatter = NumberFormat.currency(
    symbol: 'MWK ',
    decimalDigits: 2,
  );

  static final _dateFormatter = DateFormat('MMM dd, yyyy');
  static final _timeFormatter = DateFormat('HH:mm');
  static final _dateTimeFormatter = DateFormat('MMM dd, yyyy HH:mm');

  /// Format currency amounts (MWK)
  static String formatCurrency(double amount) {
    return _currencyFormatter.format(amount);
  }

  /// Format date only
  static String formatDate(DateTime date) {
    return _dateFormatter.format(date);
  }

  /// Format time only
  static String formatTime(DateTime dateTime) {
    return _timeFormatter.format(dateTime);
  }

  /// Format date and time
  static String formatDateTime(DateTime dateTime) {
    return _dateTimeFormatter.format(dateTime);
  }

  /// Format distance in km
  static String formatDistance(double km) {
    return '${km.toStringAsFixed(1)} km';
  }

  /// Format speed in km/h
  static String formatSpeed(double kmh) {
    return '${kmh.toStringAsFixed(1)} km/h';
  }

  /// Format duration
  static String formatDuration(Duration duration) {
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;

    if (days > 0) {
      return '$days day${days > 1 ? 's' : ''} $hours hour${hours != 1 ? 's' : ''}';
    } else if (hours > 0) {
      return '$hours hour${hours > 1 ? 's' : ''} $minutes minute${minutes != 1 ? 's' : ''}';
    } else {
      return '$minutes minute${minutes != 1 ? 's' : ''}';
    }
  }

  /// Format booking status
  static String formatBookingStatus(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return 'Awaiting Confirmation';
      case 'CONFIRMED':
        return 'Confirmed';
      case 'ACTIVE':
        return 'In Progress';
      case 'COMPLETED':
        return 'Completed';
      case 'CANCELLED':
        return 'Cancelled';
      default:
        return status;
    }
  }

  /// Format payment status
  static String formatPaymentStatus(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
        return 'Pending';
      case 'PROCESSING':
        return 'Processing';
      case 'SUCCESS':
        return 'Successful';
      case 'FAILED':
        return 'Failed';
      case 'REFUNDED':
        return 'Refunded';
      default:
        return status;
    }
  }

  /// Format rating with stars
  static String formatRating(double rating) {
    if (rating >= 4.5) return '★★★★★ $rating';
    if (rating >= 3.5) return '★★★★☆ $rating';
    if (rating >= 2.5) return '★★★☆☆ $rating';
    if (rating >= 1.5) return '★★☆☆☆ $rating';
    return '★☆☆☆☆ $rating';
  }

  /// Format license plate
  static String formatLicensePlate(String plate) {
    return plate.toUpperCase();
  }

  /// Format phone number (Malawi format)
  static String formatPhoneNumber(String phone) {
    // Remove all non-digits
    final cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');
    
    if (cleaned.length == 10 && cleaned.startsWith('0')) {
      // Local format: 0123456789
      return '+265 ${cleaned.substring(1)}';
    } else if (cleaned.length == 12 && cleaned.startsWith('265')) {
      // International format: 265123456789
      return '+${cleaned.substring(0, 3)} ${cleaned.substring(3)}';
    }
    return phone;
  }

  /// Calculate rental days
  static int calculateRentalDays(DateTime startDate, DateTime endDate) {
    return endDate.difference(startDate).inDays + 1;
  }

  /// Format percentage
  static String formatPercentage(double value) {
    return '${(value * 100).toStringAsFixed(1)}%';
  }

  /// Format monthly earnings
  static String formatMonthYearPeriod(int year, int month) {
    final date = DateTime(year, month);
    return DateFormat('MMMM yyyy').format(date);
  }
}
