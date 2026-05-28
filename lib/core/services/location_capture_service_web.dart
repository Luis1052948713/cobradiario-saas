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
  return LocationCapture(
    latitude: coords.latitude.toDouble(),
    longitude: coords.longitude.toDouble(),
  );
}
