import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../utils/astar_pathfinder.dart';

/// Service untuk mengelola routing dan path finding
class RoutingService {
  static final http.Client _httpClient = http.Client();
  static const String orsApiKey = 'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6ImFhZTYxMWUxMGFjZTRmYzliMWQ5ZmEyNDQ0ZDVlY2RjIiwiaCI6Im11cm11cjY0In0=';

  /// Get optimized route menggunakan A* atau ORS
  static Future<List<LatLng>?> getOptimizedRoute(
      LatLng start,
      LatLng end, {
        bool useAStar = true,
      }) async {
    if (useAStar) {
      print('🔥 Using Road-Based A* Algorithm');
      final astarPath = await RoadBasedAStarPathfinder.findPath(start, end, orsApiKey);
      if (astarPath != null && astarPath.length >= 2) {
        return astarPath;
      }
      print('⚠️ Road-Based A* failed, falling back to ORS');
    }

    final orsRoute = await _getORSRoute(start, end);
    return orsRoute ?? _createDirectRoute(start, end);
  }

  /// Get route dari OpenRouteService
  static Future<List<LatLng>?> _getORSRoute(LatLng start, LatLng end) async {
    try {
      final response = await _httpClient.post(
        Uri.parse('https://api.openrouteservice.org/v2/directions/driving-car/geojson'),
        headers: {
          'Authorization': orsApiKey,
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode({
          'coordinates': [[start.longitude, start.latitude], [end.longitude, end.latitude]],
          'format': 'geojson',
          'geometry_simplify': false,
        }),
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final coordinates = data['features'][0]['geometry']['coordinates'] as List;
        return coordinates.map<LatLng>((coord) =>
            LatLng(coord[1].toDouble(), coord[0].toDouble())).toList();
      }
    } catch (e) {
      print('❌ ORS error: $e');
    }
    return null;
  }

  /// Create direct route sebagai fallback
  static List<LatLng> _createDirectRoute(LatLng start, LatLng goal) {
    final points = <LatLng>[];
    const distance = 111000.0; // Approximate meters per degree
    final actualDistance = _calculateDistance(start, goal) * distance;
    final segments = math.max(8, (actualDistance / 300).round());

    for (int i = 0; i <= segments; i++) {
      final t = i / segments;
      final lat = start.latitude + (goal.latitude - start.latitude) * t;
      final lng = start.longitude + (goal.longitude - start.longitude) * t;

      final curve = math.sin(t * math.pi) * 0.0001;
      final bearing = _calculateBearing(start, goal);

      final curveLat = lat + curve * math.cos(bearing + math.pi / 2);
      final curveLng = lng + curve * math.sin(bearing + math.pi / 2);

      points.add(LatLng(curveLat, curveLng));
    }

    return points;
  }

  static double _calculateDistance(LatLng a, LatLng b) {
    const R = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;

    final sinDLat = math.sin(dLat / 2);
    final sinDLon = math.sin(dLon / 2);
    final h = sinDLat * sinDLat + math.cos(lat1) * math.cos(lat2) * sinDLon * sinDLon;
    return R * 2 * math.atan2(math.sqrt(h), math.sqrt(1.0 - h));
  }

  static double _calculateBearing(LatLng from, LatLng to) {
    final dLng = (to.longitude - from.longitude) * math.pi / 180;
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;

    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLng);

    return math.atan2(y, x);
  }

  static void dispose() {
    _httpClient.close();
  }
}

/// Utility functions untuk Map
class MapUtils {
  /// Calculate distance between two points in meters
  static double calculateDistance(LatLng a, LatLng b) {
    const R = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;

    final sinDLat = math.sin(dLat / 2);
    final sinDLon = math.sin(dLon / 2);
    final h = sinDLat * sinDLat + math.cos(lat1) * math.cos(lat2) * sinDLon * sinDLon;
    return R * 2 * math.atan2(math.sqrt(h), math.sqrt(1.0 - h));
  }

  /// Format distance to readable string
  static String formatDistance(double distanceInMeters) {
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.round()}m';
    } else {
      return '${(distanceInMeters / 1000).toStringAsFixed(1)}km';
    }
  }

  /// Fit all markers dalam camera view
  static void fitAllMarkers(GoogleMapController controller, LatLng center, List<LatLng> points) {
    final allPositions = [center, ...points];

    final minLat = allPositions.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
    final maxLat = allPositions.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
    final minLng = allPositions.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
    final maxLng = allPositions.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);

    controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat - 0.01, minLng - 0.01),
          northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
        ),
        100.0,
      ),
    );
  }

  /// Generate consistent avatar colors berdasarkan nama
  static List<Color> getUserAvatarColors(String name) {
    final colorPalettes = [
      [Colors.blue.shade300, Colors.blue.shade600],
      [Colors.purple.shade300, Colors.purple.shade600],
      [Colors.green.shade300, Colors.green.shade600],
      [Colors.orange.shade300, Colors.orange.shade600],
      [Colors.pink.shade300, Colors.pink.shade600],
      [Colors.teal.shade300, Colors.teal.shade600],
      [Colors.indigo.shade300, Colors.indigo.shade600],
      [Colors.red.shade300, Colors.red.shade600],
    ];

    int hash = 0;
    for (int i = 0; i < name.length; i++) {
      hash = hash + name.codeUnitAt(i);
    }
    hash = hash + (name.length * 17) + (name.isNotEmpty ? name.codeUnitAt(0) * 31 : 0);

    final colorIndex = hash.abs() % colorPalettes.length;
    return colorPalettes[colorIndex];
  }
}