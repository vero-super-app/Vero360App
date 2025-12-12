class CarHireValidators {
  /// Validate car make/brand
  static String? validateMake(String? value) {
    if (value == null || value.isEmpty) {
      return 'Car make is required';
    }
    if (value.length < 2) {
      return 'Car make must be at least 2 characters';
    }
    if (value.length > 50) {
      return 'Car make must be less than 50 characters';
    }
    return null;
  }

  /// Validate car model
  static String? validateModel(String? value) {
    if (value == null || value.isEmpty) {
      return 'Car model is required';
    }
    if (value.length < 2) {
      return 'Car model must be at least 2 characters';
    }
    if (value.length > 50) {
      return 'Car model must be less than 50 characters';
    }
    return null;
  }

  /// Validate license plate
  static String? validateLicensePlate(String? value) {
    if (value == null || value.isEmpty) {
      return 'License plate is required';
    }
    if (value.length < 5) {
      return 'Invalid license plate format';
    }
    if (value.length > 15) {
      return 'License plate is too long';
    }
    return null;
  }

  /// Validate color
  static String? validateColor(String? value) {
    if (value == null || value.isEmpty) {
      return 'Color is required';
    }
    return null;
  }

  /// Validate year
  static String? validateYear(int? value) {
    if (value == null || value == 0) {
      return 'Manufacturing year is required';
    }
    final currentYear = DateTime.now().year;
    if (value < 1900) {
      return 'Invalid year';
    }
    if (value > currentYear) {
      return 'Year cannot be in the future';
    }
    return null;
  }

  /// Validate daily rate
  static String? validateDailyRate(String? value) {
    if (value == null || value.isEmpty) {
      return 'Daily rate is required';
    }
    final amount = double.tryParse(value);
    if (amount == null) {
      return 'Please enter a valid amount';
    }
    if (amount < 1000) {
      return 'Daily rate must be at least 1,000 MWK';
    }
    if (amount > 1000000) {
      return 'Daily rate is too high';
    }
    return null;
  }

  /// Validate description
  static String? validateDescription(String? value) {
    if (value == null || value.isEmpty) {
      return 'Description is required';
    }
    if (value.length < 10) {
      return 'Description must be at least 10 characters';
    }
    if (value.length > 500) {
      return 'Description must be less than 500 characters';
    }
    return null;
  }

  /// Validate seats
  static String? validateSeats(int? value) {
    if (value == null || value == 0) {
      return 'Number of seats is required';
    }
    if (value < 2 || value > 8) {
      return 'Seats must be between 2 and 8';
    }
    return null;
  }

  /// Validate start date
  static String? validateStartDate(DateTime? value) {
    if (value == null) {
      return 'Start date is required';
    }
    if (value.isBefore(DateTime.now())) {
      return 'Start date cannot be in the past';
    }
    return null;
  }

  /// Validate end date
  static String? validateEndDate(DateTime? endDate, DateTime? startDate) {
    if (endDate == null) {
      return 'End date is required';
    }
    if (startDate == null) {
      return 'Please select start date first';
    }
    if (endDate.isBefore(startDate)) {
      return 'End date must be after start date';
    }
    return null;
  }

  /// Validate location
  static String? validateLocation(String? value) {
    if (value == null || value.isEmpty) {
      return 'Location is required';
    }
    if (value.length < 3) {
      return 'Location must be at least 3 characters';
    }
    if (value.length > 100) {
      return 'Location is too long';
    }
    return null;
  }

  /// Validate phone number
  static String? validatePhoneNumber(String? value) {
    if (value == null || value.isEmpty) {
      return 'Phone number is required';
    }
    final cleaned = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.length < 10) {
      return 'Phone number must be at least 10 digits';
    }
    if (cleaned.length > 15) {
      return 'Phone number is too long';
    }
    return null;
  }

  /// Validate payment amount
  static String? validatePaymentAmount(String? value) {
    if (value == null || value.isEmpty) {
      return 'Amount is required';
    }
    final amount = double.tryParse(value);
    if (amount == null) {
      return 'Please enter a valid amount';
    }
    if (amount <= 0) {
      return 'Amount must be greater than 0';
    }
    return null;
  }

  /// Validate promo code
  static String? validatePromoCode(String? value) {
    if (value == null || value.isEmpty) {
      return null; // Promo code is optional
    }
    if (value.length < 3) {
      return 'Promo code must be at least 3 characters';
    }
    if (value.length > 20) {
      return 'Promo code is too long';
    }
    return null;
  }

  /// Validate business license
  static String? validateBusinessLicense(String? value) {
    if (value == null || value.isEmpty) {
      return 'Business license is required';
    }
    if (value.length < 5) {
      return 'Invalid business license format';
    }
    return null;
  }

  /// Validate geofence radius
  static String? validateGeofenceRadius(String? value) {
    if (value == null || value.isEmpty) {
      return 'Radius is required';
    }
    final radius = double.tryParse(value);
    if (radius == null) {
      return 'Please enter a valid radius';
    }
    if (radius < 100) {
      return 'Radius must be at least 100 meters';
    }
    if (radius > 50000) {
      return 'Radius must be less than 50 km';
    }
    return null;
  }
}
