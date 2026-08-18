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
    required List<Map<String, String>> emergencyContacts, // exactly 2: {name, phone, relation?}
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
        'emergency_contacts': emergencyContacts,
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

  static Future<Map<String, dynamic>> updateProfile({
    String? name,
    String? profilePhotoUrl,
    String? dateOfBirth, // 'YYYY-MM-DD'
    String? gender,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/me'),
      headers: _authHeaders,
      body: jsonEncode({
        if (name != null) 'name': name,
        if (profilePhotoUrl != null) 'profile_photo_url': profilePhotoUrl,
        if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
        if (gender != null) 'gender': gender,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': data['user']};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not update profile'};
  }

  static Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/change-password'),
      headers: _authHeaders,
      body: jsonEncode({'current_password': currentPassword, 'new_password': newPassword}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not change password'};
  }

  static Future<Map<String, dynamic>> forgotPassword({String? phone, String? email}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({if (phone != null) 'phone': phone, if (email != null) 'email': email}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'devCode': data['dev_code']};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not request reset code'};
  }

  static Future<Map<String, dynamic>> resetPassword({
    String? phone,
    String? email,
    required String code,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        'code': code,
        'new_password': newPassword,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not reset password'};
  }

  // ------------------------------------------------------------
  // Saved places
  // ------------------------------------------------------------

  static Future<Map<String, dynamic>> getSavedPlaces() async {
    final response = await http.get(Uri.parse('$baseUrl/api/saved-places'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': List<Map<String, dynamic>>.from(data['places'])};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not load saved places'};
  }

  static Future<Map<String, dynamic>> addSavedPlace({
    required String label,
    required String address,
    required double lat,
    required double lng,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/saved-places'),
      headers: _authHeaders,
      body: jsonEncode({'label': label, 'address': address, 'lat': lat, 'lng': lng}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 201) {
      return {'success': true, 'data': data['place']};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not save place'};
  }

  static Future<Map<String, dynamic>> deleteSavedPlace(String placeId) async {
    final response = await http.delete(Uri.parse('$baseUrl/api/saved-places/$placeId'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not remove saved place'};
  }

  // ------------------------------------------------------------
  // Vehicles
  // ------------------------------------------------------------

  static Future<Map<String, dynamic>> registerVehicle({
    required String vehicleTypeId,
    required String plate,
    required String makeModel,
    String? color,
    int? year,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/vehicles'),
      headers: _authHeaders,
      body: jsonEncode({
        'vehicle_type_id': vehicleTypeId,
        'plate': plate,
        'make_model': makeModel,
        if (color != null && color.isNotEmpty) 'color': color,
        if (year != null) 'year': year,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 201) {
      return {'success': true, 'data': data['vehicle']};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not register vehicle'};
  }

  static Future<Map<String, dynamic>> getMyVehicles() async {
    final response = await http.get(Uri.parse('$baseUrl/api/vehicles/my'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': List<Map<String, dynamic>>.from(data['vehicles'])};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not load vehicles'};
  }

  static Future<Map<String, dynamic>> activateVehicle(String vehicleId) async {
    final response = await http.post(Uri.parse('$baseUrl/api/vehicles/$vehicleId/activate'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': data['vehicle']};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not activate vehicle'};
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

  static Future<Map<String, dynamic>> getRideMessages(String rideId) async {
    final response = await http.get(Uri.parse('$baseUrl/api/rides/$rideId/messages'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': List<Map<String, dynamic>>.from(data['messages'])};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not load messages'};
  }

  static Future<Map<String, dynamic>> sendRideMessage(String rideId, String message) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/rides/$rideId/messages'),
      headers: _authHeaders,
      body: jsonEncode({'message': message}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 201) {
      return {'success': true, 'data': data['message']};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not send message'};
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

  // ------------------------------------------------------------
  // Safety
  // ------------------------------------------------------------

  static Future<Map<String, dynamic>> triggerSos({String? rideId, double? lat, double? lng, String? notes}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/sos'),
      headers: _authHeaders,
      body: jsonEncode({
        if (rideId != null) 'ride_id': rideId,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 201) {
      return {'success': true, 'data': data['sos_event']};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not trigger SOS'};
  }

  static Future<Map<String, dynamic>> getEmergencyContacts() async {
    final response = await http.get(Uri.parse('$baseUrl/api/emergency-contacts'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': List<Map<String, dynamic>>.from(data['contacts'])};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not load emergency contacts'};
  }

  static Future<Map<String, dynamic>> addEmergencyContact({
    required String name,
    required String phone,
    String? relation,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/emergency-contacts'),
      headers: _authHeaders,
      body: jsonEncode({
        'name': name,
        'phone': phone,
        if (relation != null && relation.isNotEmpty) 'relation': relation,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 201) {
      return {'success': true, 'data': data['contact']};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not add emergency contact'};
  }

  static Future<Map<String, dynamic>> deleteEmergencyContact(String contactId) async {
    final response = await http.delete(Uri.parse('$baseUrl/api/emergency-contacts/$contactId'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not remove emergency contact'};
  }

  // ------------------------------------------------------------
  // Notifications
  // ------------------------------------------------------------

  static Future<Map<String, dynamic>> getNotifications() async {
    final response = await http.get(Uri.parse('$baseUrl/api/notifications'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {
        'success': true,
        'notifications': List<Map<String, dynamic>>.from(data['notifications']),
        'unreadCount': data['unread_count'] as int,
      };
    }
    return {'success': false, 'error': data['error'] ?? 'Could not load notifications'};
  }

  static Future<Map<String, dynamic>> markNotificationRead(String notificationId) async {
    final response = await http.post(Uri.parse('$baseUrl/api/notifications/$notificationId/read'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not update notification'};
  }

  static Future<Map<String, dynamic>> getNotificationPreferences() async {
    final response = await http.get(Uri.parse('$baseUrl/api/notification-preferences'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': List<Map<String, dynamic>>.from(data['preferences'])};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not load notification preferences'};
  }

  static Future<Map<String, dynamic>> updateNotificationPreferences(List<Map<String, dynamic>> preferences) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/notification-preferences'),
      headers: _authHeaders,
      body: jsonEncode({'preferences': preferences}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': List<Map<String, dynamic>>.from(data['preferences'])};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not update notification preferences'};
  }

  // ------------------------------------------------------------
  // Driver earnings: bank accounts, payouts, incentives, KYC documents
  // ------------------------------------------------------------

  static Future<Map<String, dynamic>> getBankAccounts() async {
    final response = await http.get(Uri.parse('$baseUrl/api/driver/bank-accounts'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': List<Map<String, dynamic>>.from(data['bank_accounts'])};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not load bank accounts'};
  }

  static Future<Map<String, dynamic>> addBankAccount({
    required String accountHolderName,
    required String bankName,
    required String accountNumber,
    required String countryId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/driver/bank-accounts'),
      headers: _authHeaders,
      body: jsonEncode({
        'account_holder_name': accountHolderName,
        'bank_name': bankName,
        'account_number': accountNumber,
        'country_id': countryId,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 201) {
      return {'success': true, 'data': data['bank_account']};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not add bank account'};
  }

  static Future<Map<String, dynamic>> setDefaultBankAccount(String bankAccountId) async {
    final response = await http.post(Uri.parse('$baseUrl/api/driver/bank-accounts/$bankAccountId/default'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not set default bank account'};
  }

  static Future<Map<String, dynamic>> deleteBankAccount(String bankAccountId) async {
    final response = await http.delete(Uri.parse('$baseUrl/api/driver/bank-accounts/$bankAccountId'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not remove bank account'};
  }

  static Future<Map<String, dynamic>> getPayouts() async {
    final response = await http.get(Uri.parse('$baseUrl/api/driver/payouts'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': List<Map<String, dynamic>>.from(data['payouts'])};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not load payouts'};
  }

  static Future<Map<String, dynamic>> requestPayout({String? bankAccountId, double? amount}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/driver/payouts'),
      headers: _authHeaders,
      body: jsonEncode({
        if (bankAccountId != null) 'bank_account_id': bankAccountId,
        if (amount != null) 'amount': amount,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 201) {
      return {'success': true, 'data': data['payout']};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not request payout'};
  }

  static Future<Map<String, dynamic>> getIncentives() async {
    final response = await http.get(Uri.parse('$baseUrl/api/driver/incentives'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': List<Map<String, dynamic>>.from(data['incentives'])};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not load incentives'};
  }

  static Future<Map<String, dynamic>> getDriverDocuments() async {
    final response = await http.get(Uri.parse('$baseUrl/api/driver/documents'), headers: _authHeaders);
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {
        'success': true,
        'documents': List<Map<String, dynamic>>.from(data['documents']),
        'requiredDocTypes': List<String>.from(data['required_doc_types']),
        'kycStatus': data['kyc_status'] as String?,
      };
    }
    return {'success': false, 'error': data['error'] ?? 'Could not load documents'};
  }

  static Future<Map<String, dynamic>> submitDriverDocument({
    required String docType,
    required String url,
    String? expiresAt, // 'YYYY-MM-DD'
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/driver/documents'),
      headers: _authHeaders,
      body: jsonEncode({
        'doc_type': docType,
        'url': url,
        if (expiresAt != null && expiresAt.isNotEmpty) 'expires_at': expiresAt,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 201) {
      return {'success': true, 'data': data['document']};
    }
    return {'success': false, 'error': data['error'] ?? 'Could not submit document'};
  }

  // Address autocomplete. biasLat/biasLng (e.g. the rider's current
  // location) nudge results toward nearby matches without excluding others.
  static Future<Map<String, dynamic>> searchAddress({
    required String query,
    double? biasLat,
    double? biasLng,
  }) async {
    final uri = Uri.parse('$baseUrl/api/geocode/search').replace(queryParameters: {
      'q': query,
      if (biasLat != null) 'lat': biasLat.toString(),
      if (biasLng != null) 'lng': biasLng.toString(),
    });
    try {
      final response = await http.get(uri, headers: _authHeaders).timeout(const Duration(seconds: 8));
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': List<Map<String, dynamic>>.from(data['suggestions'])};
      }
      return {'success': false, 'error': data['error'] ?? 'Could not search addresses'};
    } catch (_) {
      return {'success': false, 'error': 'Could not search addresses — check your connection'};
    }
  }
}
