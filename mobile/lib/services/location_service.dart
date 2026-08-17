import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  // Throws on failure (no permission, service disabled) — callers should
  // catch and show a message rather than silently defaulting somewhere.
  static Future<Position> getCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Location services are disabled. Please enable them to book a ride.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permission permanently denied. Enable it from app settings.');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  // Best-effort reverse geocode; falls back to raw coordinates so the UI
  // always has something to show even when the platform geocoder fails.
  static Future<String> addressFromCoordinates(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
      final p = placemarks.first;
      final parts = [p.street, p.locality, p.administrativeArea]
          .where((s) => s != null && s.isNotEmpty)
          .toList();
      return parts.isEmpty ? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}' : parts.join(', ');
    } catch (_) {
      return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    }
  }
}
