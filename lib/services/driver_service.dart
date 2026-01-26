import 'package:dio/dio.dart';
import 'package:vero360_app/services/auth_storage.dart';
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
        final token = await AuthStorage.readToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
    ));
  }

  // ==================== DRIVER PROFILE ====================
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

  Future<Map<String, dynamic>> getTaxisByClass(String taxiClass) async {
    try {
      final response = await _dio.get('/vero/taxis/class/$taxiClass');
      return response.data as Map<String, dynamic>;
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

  // ==================== ERROR HANDLING ====================
  String _handleError(dynamic error) {
    final errorType = error.runtimeType.toString();
    if (errorType.contains('DioException') || errorType.contains('DioError')) {
      if (error.response != null) {
        final message = error.response?.data['message'] ?? error.message;
        return message ?? 'An error occurred';
      }
      return error.message ?? 'Network error';
    }
    return error.toString();
  }
}
