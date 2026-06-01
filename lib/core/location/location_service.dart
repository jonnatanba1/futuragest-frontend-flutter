import 'package:geolocator/geolocator.dart';

/// Value object returned by [LocationService.getCurrentPosition].
class GpsPosition {
  const GpsPosition({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });

  final double latitude;
  final double longitude;

  /// Horizontal accuracy in metres.
  final double accuracy;
}

/// Domain exception for location errors.
class LocationException implements Exception {
  const LocationException(this.message);

  final String message;

  @override
  String toString() => 'LocationException: $message';
}

/// Service that wraps [Geolocator] for requesting permissions and fetching
/// the current device position.
///
/// Usage:
///   final pos = await LocationService.getCurrentPosition();
class LocationService {
  LocationService._();

  /// Requests location permission (if not already granted) and returns the
  /// current position.
  ///
  /// Throws [LocationException] with a Spanish message when:
  ///  - Location services are disabled on the device.
  ///  - The user denies the permission.
  ///  - The permission is permanently denied.
  static Future<GpsPosition> getCurrentPosition() async {
    // 1. Check if location services are enabled.
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationException(
        'El GPS está desactivado. Activá los servicios de ubicación para continuar.',
      );
    }

    // 2. Check / request runtime permission.
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const LocationException(
          'Permiso de ubicación denegado. Concedé el permiso para registrar la asistencia.',
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'Permiso de ubicación denegado permanentemente. Habilitalo en la configuración del dispositivo.',
      );
    }

    // 3. Fetch position with best accuracy.
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 20),
        ),
      );

      return GpsPosition(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
    } catch (e) {
      throw LocationException('No se pudo obtener la ubicación: $e');
    }
  }
}
