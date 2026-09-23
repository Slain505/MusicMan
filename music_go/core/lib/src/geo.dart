import 'dart:math' as math;

const double _earthRadiusM = 6371008.8;
const double metersPerDegreeLat = 111320.0;

class GeoPoint {
  const GeoPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  /// Great-circle distance in meters (haversine).
  double distanceTo(GeoPoint other) {
    final dLat = _rad(other.lat - lat);
    final dLng = _rad(other.lng - lng);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(lat)) *
            math.cos(_rad(other.lat)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * _earthRadiusM * math.asin(math.min(1.0, math.sqrt(a)));
  }

  /// Moves this point by [northM] / [eastM] meters (fine for short hops).
  GeoPoint offsetMeters(double northM, double eastM) => GeoPoint(
        lat + northM / metersPerDegreeLat,
        lng + eastM / metersPerDegreeLng(lat),
      );

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  factory GeoPoint.fromJson(Map<String, dynamic> json) =>
      GeoPoint((json['lat'] as num).toDouble(), (json['lng'] as num).toDouble());

  @override
  String toString() => 'GeoPoint(${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)})';
}

double metersPerDegreeLng(double lat) =>
    metersPerDegreeLat * math.max(0.01, math.cos(_rad(lat)));

double _rad(double deg) => deg * math.pi / 180.0;
