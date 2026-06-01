/// GPS coordinates captured at the moment of a check-in or check-out.
///
/// Re-exported from this layer so domain code never imports core directly.
/// [accuracy] is in metres (>= 0), nullable when the platform doesn't provide it.
class GpsPosition {
  const GpsPosition({
    required this.latitude,
    required this.longitude,
    this.accuracy,
  });

  final double latitude;
  final double longitude;
  final double? accuracy;
}
