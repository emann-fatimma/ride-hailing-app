import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_state.dart';

class ApiService {
  // Chrome on the same machine as your backend can use localhost.
  // If you later test on a physical phone, replace this with your
  // computer's local IP, e.g. "http://192.168.1.5:3000"
  static const String baseUrl = 'http://localhost:3000';

  static Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        if (AuthState.token != null) 'Authorization': 'Bearer ${AuthState.token}',
      };

  static Future<Map<String, dynamic>> signup({
    required String name,
    required String phone,
    required String password,
    required String verifyChannel, // 'phone' or 'email'
    String? email, // required (real address) when verifyChannel is 'email'
  }) async {
    final effectiveEmail = email ?? '${phone.replaceAll('+', '')}@rideeasy.temp';

    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'email': effectiveEmail,
        'phone': phone,
        'password': password,
        'role': 'rider',
        'verify_channel': verifyChannel,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 201) {
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': data['error'] ?? 'Signup failed'};
    }
  }

  static Future<Map<String, dynamic>> sendCode({
    required String channel,
    required String destination,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/send-code'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'channel': channel, 'destination': destination}),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': data['error'] ?? 'Could not send code'};
    }
  }

  static Future<Map<String, dynamic>> verifyCode({
    required String channel,
    required String destination,
    required String code,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/verify-code'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'channel': channel, 'destination': destination, 'code': code}),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': data['error'] ?? 'Verification failed'};
    }
  }

  static Future<List<Map<String, dynamic>>> getCountries() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/countries'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['countries']);
      }
    } catch (_) {
      // fall through to empty list; caller falls back to a static list
    }
    return [];
  }

  static Future<Map<String, dynamic>> login({
    required String phone,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone, 'password': password}),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': data['error'] ?? 'Login failed'};
    }
  }

  static Future<Map<String, dynamic>> getMe() async {
    final response = await http.get(Uri.parse('$baseUrl/api/me'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': data['user']};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not load profile'};
  }

  // ------------------------------------------------------------
  // Driver signup
  // ------------------------------------------------------------

  static Future<Map<String, dynamic>> signupDriver({
    required String name,
    required String phone,
    required String email,
    required String password,
    required String licenseNumber,
    required String licenseExpiry, // 'YYYY-MM-DD'
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/signup/driver'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'phone': phone,
        'email': email,
        'password': password,
        'license_number': licenseNumber,
        'license_expiry': licenseExpiry,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 201) {
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': data['error'] ?? 'Driver signup failed'};
    }
  }

  // ------------------------------------------------------------
  // Rides
  // ------------------------------------------------------------

  static Future<Map<String, dynamic>> getVehicleTypes() async {
    final response = await http.get(Uri.parse('$baseUrl/api/vehicle-types'));
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': List<Map<String, dynamic>>.from(data['vehicle_types'])};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not load vehicle types'};
  }

  static Future<Map<String, dynamic>> estimateRide({
    required String vehicleTypeId,
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? cityId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/rides/estimate'),
      headers: _authHeaders,
      body: jsonEncode({
        'vehicle_type_id': vehicleTypeId,
        'pickup_lat': pickupLat,
        'pickup_lng': pickupLng,
        'dropoff_lat': dropoffLat,
        'dropoff_lng': dropoffLng,
        if (cityId != null) 'city_id': cityId,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 201) {
      return {'success': true, 'data': data['estimate']};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not get a fare estimate'};
  }

  static Future<Map<String, dynamic>> createRide({
    required String pickupAddress,
    required String dropoffAddress,
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? fareEstimateId,
    String? cityId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/rides'),
      headers: _authHeaders,
      body: jsonEncode({
        'pickup_address': pickupAddress,
        'dropoff_address': dropoffAddress,
        'pickup_lat': pickupLat,
        'pickup_lng': pickupLng,
        'dropoff_lat': dropoffLat,
        'dropoff_lng': dropoffLng,
        if (fareEstimateId != null) 'fare_estimate_id': fareEstimateId,
        if (cityId != null) 'city_id': cityId,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 201) {
      return {'success': true, 'data': data['ride']};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not request ride'};
  }

  static Future<Map<String, dynamic>> getRide(String rideId) async {
    final response = await http.get(Uri.parse('$baseUrl/api/rides/$rideId'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': data['ride']};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not load ride'};
  }

  static Future<Map<String, dynamic>> getMyRides() async {
    final response = await http.get(Uri.parse('$baseUrl/api/rides/my'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': List<Map<String, dynamic>>.from(data['rides'])};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not load rides'};
  }

  static Future<Map<String, dynamic>> cancelRide(String rideId, {String? reason}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/rides/$rideId/cancel'),
      headers: _authHeaders,
      body: jsonEncode({if (reason != null) 'reason': reason}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': data['ride']};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not cancel ride'};
  }

  static Future<Map<String, dynamic>> rateRide(String rideId, {required int stars, String? comment}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/rides/$rideId/rate'),
      headers: _authHeaders,
      body: jsonEncode({'stars': stars, if (comment != null && comment.isNotEmpty) 'comment': comment}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 201) {
      return {'success': true, 'data': data['rating']};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not submit rating'};
  }

  // ------------------------------------------------------------
  // Driver
  // ------------------------------------------------------------

  static Future<Map<String, dynamic>> setDriverOnline(String status) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/drivers/online'),
      headers: _authHeaders,
      body: jsonEncode({'status': status}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': data['driver']};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not update status'};
  }

  static Future<Map<String, dynamic>> updateDriverLocation({required double lat, required double lng}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/drivers/location'),
      headers: _authHeaders,
      body: jsonEncode({'lat': lat, 'lng': lng}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': data};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not update location'};
  }

  static Future<Map<String, dynamic>> getDispatches() async {
    final response = await http.get(Uri.parse('$baseUrl/api/drivers/dispatches'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': List<Map<String, dynamic>>.from(data['dispatches'])};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not load ride offers'};
  }

  static Future<Map<String, dynamic>> acceptRide(String rideId) async {
    final response = await http.post(Uri.parse('$baseUrl/api/rides/$rideId/accept'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': data['ride']};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not accept ride'};
  }

  static Future<Map<String, dynamic>> declineRide(String rideId) async {
    final response = await http.post(Uri.parse('$baseUrl/api/rides/$rideId/decline'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': data['dispatch']};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not decline ride'};
  }

  static Future<Map<String, dynamic>> startRide(String rideId) async {
    final response = await http.post(Uri.parse('$baseUrl/api/rides/$rideId/start'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': data['ride']};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not start ride'};
  }

  static Future<Map<String, dynamic>> completeRide(String rideId) async {
    final response = await http.post(Uri.parse('$baseUrl/api/rides/$rideId/complete'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': data['ride']};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not complete ride'};
  }
}
