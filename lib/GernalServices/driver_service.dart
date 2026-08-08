import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vero360_app/config/api_config.dart';

class DriverService {
  late Dio _dio;

  DriverService() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // ✅ Get fresh Firebase ID token (auto-refreshed if expired)
        final firebaseUser = FirebaseAuth.instance.currentUser;
        if (firebaseUser != null) {
          try {
            final freshToken = await firebaseUser.getIdToken();
            if (freshToken != null && freshToken.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $freshToken';
              return handler.next(options);
            }
          } catch (e) {
            print('[DriverService] Error getting fresh Firebase token: $e');
          }
        }
        
        // Fallback: If Firebase token not available, log warning
        print('[DriverService] No Firebase user or token available');
        return handler.next(options);
      },
    ));
  }

  // ==================== DRIVER PROFILE ====================
  
  /// Get current authenticated driver profile using Firebase token
  Future<Map<String, dynamic>> getMyDriverProfile() async {
    try {
      final response = await _dio.get('/vero/drivers/me');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Get driver by database user ID (legacy method, use getMyDriverProfile instead)
  Future<Map<String, dynamic>> getDriverByUserId(int userId) async {
    try {
      final response = await _dio.get('/vero/drivers/user/$userId');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> createDriver(
      Map<String, dynamic> driverData) async {
    try {
      final response = await _dio.post(
        '/vero/drivers',
        data: driverData,
      );
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> updateDriver(
    int driverId,
    Map<String, dynamic> updateData,
  ) async {
    try {
      final response = await _dio.put(
        '/vero/drivers/$driverId',
        data: updateData,
      );
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Upload a driver/vehicle document. [type]: license|national_id|vehicle|registration|insurance|cof
  Future<String> uploadDriverDocument(String filePath, String type) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
        'type': type,
      });
      final response = await _dio.post(
        '/vero/drivers/docs',
        queryParameters: {'type': type},
        data: formData,
        options: Options(
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final data = response.data;
      final url = data is Map ? data['url']?.toString() : null;
      if (url == null || url.isEmpty) {
        throw 'Upload succeeded but no URL was returned';
      }
      return url;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Submit driver identity documents for operator review.
  Future<Map<String, dynamic>> applyAsDriver(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post(
        '/vero/drivers/apply',
        data: data,
      );
      final body = response.data;
      if (body is Map && body['driver'] is Map) {
        return Map<String, dynamic>.from(body['driver'] as Map);
      }
      if (body is Map) return Map<String, dynamic>.from(body);
      return await getMyDriverProfile();
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Update my profile (doc changes demote verified drivers for re-review).
  Future<Map<String, dynamic>> updateMyDriver(
    Map<String, dynamic> updateData,
  ) async {
    try {
      final response = await _dio.put('/vero/drivers/me', data: updateData);
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Submit vehicle + compliance docs for operator review.
  Future<Map<String, dynamic>> submitVehicleProposal(
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _dio.post(
        '/vero/drivers/me/vehicle-proposal',
        data: data,
      );
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ==================== TAXI MANAGEMENT ====================
  Future<List<Map<String, dynamic>>> getTaxisByDriver(int driverId) async {
    try {
      final response = await _dio.get('/vero/taxis/driver/$driverId');
      final data = response.data;
      if (data is List) {
        return List<Map<String, dynamic>>.from(data);
      } else if (data is Map && data.containsKey('taxis')) {
        return List<Map<String, dynamic>>.from(data['taxis']);
      }
      return [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> createTaxi(Map<String, dynamic> taxiData) async {
    try {
      final response = await _dio.post(
        '/vero/taxis',
        data: taxiData,
      );
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> updateTaxi(
    int taxiId,
    Map<String, dynamic> updateData,
  ) async {
    try {
      final response = await _dio.put(
        '/vero/taxis/$taxiId',
        data: updateData,
      );
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> updateTaxiLocation(
    int taxiId,
    double latitude,
    double longitude,
  ) async {
    try {
      final response = await _dio.put(
        '/vero/taxis/$taxiId/location',
        data: {
          'latitude': latitude,
          'longitude': longitude,
        },
        options: Options(
          // Increase timeout for location updates since backend may be slow
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 30),
        ),
      );
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> setTaxiAvailability(
    int taxiId,
    bool isAvailable,
  ) async {
    try {
      final response = await _dio.put(
        '/vero/taxis/$taxiId/availability',
        data: {'isAvailable': isAvailable},
      );
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> deleteTaxi(int taxiId) async {
    try {
      final response = await _dio.delete('/vero/taxis/$taxiId');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> verifyTaxiDetails(int taxiId) async {
    try {
      final response = await _dio.put('/vero/taxis/$taxiId/verify');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ==================== DRIVER DISCOVERY ====================
  Future<List<Map<String, dynamic>>> getNearbyDrivers(
    double latitude,
    double longitude,
    double radiusInKm,
  ) async {
    try {
      final response = await _dio.get(
        '/vero/drivers/nearby/search',
        queryParameters: {
          'lat': latitude,
          'lng': longitude,
          'radius': radiusInKm,
        },
      );
      final data = response.data;
      if (data is List) {
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<Map<String, dynamic>>> getVerifiedDrivers({
    int skip = 0,
    int take = 10,
  }) async {
    try {
      final response = await _dio.get(
        '/vero/drivers/verified/list',
        queryParameters: {
          'skip': skip,
          'take': take,
        },
      );
      final data = response.data;
      if (data is Map && data.containsKey('drivers')) {
        return List<Map<String, dynamic>>.from(data['drivers']);
      } else if (data is List) {
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<List<Map<String, dynamic>>> getTaxisByClass(String taxiClass) async {
    try {
      final response = await _dio.get('/vero/taxis/class/$taxiClass');
      final data = response.data;
      if (data is List) {
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ==================== DRIVER VERIFICATION ====================
  Future<Map<String, dynamic>> verifyDriver(int driverId) async {
    try {
      final response = await _dio.post('/vero/drivers/$driverId/verify');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> suspendDriver(int driverId) async {
    try {
      final response = await _dio.post('/vero/drivers/$driverId/suspend');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Map<String, dynamic>> activateDriver(int driverId) async {
    try {
      final response = await _dio.post('/vero/drivers/$driverId/activate');
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ==================== ERROR HANDLING ====================
  String _handleError(dynamic error) {
    final errorType = error.runtimeType.toString();
    if (errorType.contains('DioException') || errorType.contains('DioError')) {
      if (error.response != null) {
        final data = error.response?.data;
        if (data is Map) {
          final message = data['message'];
          if (message is List && message.isNotEmpty) {
            return message.first.toString();
          }
          if (message != null) return message.toString();
        }
        return error.message ?? 'An error occurred';
      }
      return error.message ?? 'Network error';
    }
    return error.toString();
  }
}
