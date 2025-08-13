import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Constants untuk Map Screen
class MapConstants {
  // Default location (Jakarta)
  static const LatLng defaultLocation = LatLng(-6.2088, 106.8456);

  // Distance settings - RADIUS DIPERBESAR MENJADI 1KM
  static const double maxNotificationDistance = 1000.0; // 1km dalam meter
  static const double userRadiusMeters = 1000.0; // Radius lingkaran di sekitar user (1km)
  static const double minimumLocationUpdateDistance = 10.0; // 10m minimum perubahan

  // Visual radius settings untuk tampilan di map
  static const double visualRadiusOpacity = 0.15; // Transparansi lingkaran
  static const double visualRadiusBorderWidth = 2.0; // Ketebalan border lingkaran

  // Timing settings
  static const Duration notificationInterval = Duration(seconds: 15);
  static const Duration vibrationCooldown = Duration(seconds: 30);
  static const Duration autoFollowDelay = Duration(seconds: 3);
  static const Duration routeDebounceDelay = Duration(milliseconds: 400);

  // API settings
  static const String orsApiKey = 'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6ImFhZTYxMWUxMGFjZTRmYzliMWQ5ZmEyNDQ0ZDVlY2RjIiwiaCI6Im11cm11cjY0In0=';
  static const Duration apiTimeout = Duration(seconds: 10);

  // Map settings
  static const double defaultZoom = 13.0;
  static const double focusZoom = 16.0;
  static const double userFocusZoom = 15.0;
  static const double radiusZoom = 14.0; // Zoom level yang pas untuk melihat radius 1km
  static const double mapPadding = 100.0;

  // UI settings
  static const double controlBarHeight = 56.0;
  static const double floatingButtonSize = 56.0;
  static const double markerIconSize = 24.0;

  // Cache settings
  static const int maxCacheSize = 100;
  static const Duration cacheExpiry = Duration(minutes: 30);

  // Animation settings
  static const Duration notificationAnimationDuration = Duration(milliseconds: 300);
  static const Duration autoHideNotificationDelay = Duration(seconds: 5);

  // Marker Colors (BitmapDescriptor hues)
  static const double blueHue = BitmapDescriptor.hueBlue;
  static const double greenHue = BitmapDescriptor.hueGreen;
  static const double redHue = BitmapDescriptor.hueRed;
  static const double orangeHue = BitmapDescriptor.hueOrange;
  static const double yellowHue = BitmapDescriptor.hueYellow;
  static const double violetHue = BitmapDescriptor.hueViolet;

  // Helper method untuk mengkonversi meter ke derajat latitude/longitude
  static double metersToLatitudeDegrees(double meters) {
    return meters / 111320.0; // 1 derajat latitude ≈ 111.32 km
  }

  static double metersToLongitudeDegrees(double meters, double latitude) {
    final latitudeRadians = latitude * (3.14159265359 / 180.0);
    final oneDegreeInMeters = 111320.0 * (1.0 / (1.0 / cos(latitudeRadians)));
    return meters / oneDegreeInMeters;
  }

  // Helper method untuk cos function
  static double cos(double radians) {
    // Simple cos approximation atau gunakan dart:math
    return 1.0 - (radians * radians) / 2.0 + (radians * radians * radians * radians) / 24.0;
  }
}

/// Vibration patterns enum
enum VibrationPattern {
  warning,  // Pattern untuk warning jarak jauh
  alert,    // Pattern untuk alert multiple users
  gentle,   // Pattern untuk notifikasi biasa
}