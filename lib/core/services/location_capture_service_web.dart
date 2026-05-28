import 'dart:html' as html;

class LocationCapture {
  const LocationCapture({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

Future<LocationCapture?> captureCurrentLocation() async {
  final position = await html.window.navigator.geolocation.getCurrentPosition(
    enableHighAccuracy: true,
  );
  final coords = position.coords;
  final latitude = coords?.latitude;
  final longitude = coords?.longitude;
  if (latitude == null || longitude == null) return null;

  return LocationCapture(
    latitude: latitude.toDouble(),
    longitude: longitude.toDouble(),
  );
}
