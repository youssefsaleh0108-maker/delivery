import '../models/checkout_tracking_models.dart';

/// Decodes an encoded polyline at 1e6 precision — the `geometries=polyline6` format OSRM and
/// Mapbox both return — into its points.
///
/// Returns null, never a partial line, for anything that is not a well-formed polyline: a
/// character outside the format's range, a truncated final number, a value too large to be a
/// coordinate, or a point off the globe. A road half-drawn from a corrupt string is a road the
/// provider never returned.
///
/// The arithmetic stays inside 32 bits, so it decodes identically on the web, where bitwise
/// operators work on 32-bit integers.
List<GeoPin>? decodePolyline6(String encoded) => decodePolyline(encoded, precision: 6);

/// [decodePolyline6] at any precision; 5 is the classic Google format.
List<GeoPin>? decodePolyline(String encoded, {required int precision}) {
  double factor = 1;
  for (int i = 0; i < precision; i++) {
    factor *= 10;
  }
  final List<GeoPin> points = <GeoPin>[];
  int index = 0;
  int lat = 0;
  int lng = 0;
  while (index < encoded.length) {
    final List<int> deltas = <int>[0, 0];
    for (int axis = 0; axis < 2; axis++) {
      int result = 0;
      int shift = 0;
      int chunk;
      do {
        if (index >= encoded.length || shift > 25) return null;
        chunk = encoded.codeUnitAt(index++) - 63;
        if (chunk < 0 || chunk > 63) return null;
        result |= (chunk & 0x1f) << shift;
        shift += 5;
      } while (chunk >= 0x20);
      deltas[axis] = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    }
    lat += deltas[0];
    lng += deltas[1];
    final double pointLat = lat / factor;
    final double pointLng = lng / factor;
    if (pointLat < -90 || pointLat > 90 || pointLng < -180 || pointLng > 180) return null;
    points.add(GeoPin(pointLat, pointLng));
  }
  return points;
}
