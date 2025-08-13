import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:collection';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// Priority Queue untuk A* algorithm
class PriorityQueue<T> {
  final List<T> _items = [];
  final int Function(T a, T b) _compare;

  PriorityQueue(this._compare);

  void add(T item) {
    _items.add(item);
    _bubbleUp(_items.length - 1);
  }

  T removeFirst() {
    if (_items.isEmpty) throw StateError('Queue is empty');
    final result = _items[0];
    final last = _items.removeLast();
    if (_items.isNotEmpty) {
      _items[0] = last;
      _bubbleDown(0);
    }
    return result;
  }

  bool get isNotEmpty => _items.isNotEmpty;
  bool get isEmpty => _items.isEmpty;

  void _bubbleUp(int index) {
    while (index > 0) {
      final parentIndex = (index - 1) ~/ 2;
      if (_compare(_items[index], _items[parentIndex]) >= 0) break;
      _swap(index, parentIndex);
      index = parentIndex;
    }
  }

  void _bubbleDown(int index) {
    while (true) {
      int minIndex = index;
      final leftChild = 2 * index + 1;
      final rightChild = 2 * index + 2;

      if (leftChild < _items.length && _compare(_items[leftChild], _items[minIndex]) < 0) {
        minIndex = leftChild;
      }
      if (rightChild < _items.length && _compare(_items[rightChild], _items[minIndex]) < 0) {
        minIndex = rightChild;
      }
      if (minIndex == index) break;

      _swap(index, minIndex);
      index = minIndex;
    }
  }

  void _swap(int i, int j) {
    final temp = _items[i];
    _items[i] = _items[j];
    _items[j] = temp;
  }

  void clear() => _items.clear();
}

/// A* Node class
class AStarNode {
  final LatLng position;
  final double gCost;
  final double hCost;
  final AStarNode? parent;

  AStarNode({
    required this.position,
    required this.gCost,
    required this.hCost,
    this.parent,
  });

  double get fCost => gCost + hCost;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is AStarNode &&
              runtimeType == other.runtimeType &&
              position.latitude == other.position.latitude &&
              position.longitude == other.position.longitude;

  @override
  int get hashCode => position.latitude.hashCode ^ position.longitude.hashCode;
}

/// Road-based A* Pathfinder yang menggunakan data jalan sebenarnya
class RoadBasedAStarPathfinder {
  static final Map<String, List<LatLng>> _roadNetworkCache = {};
  static final http.Client _httpClient = http.Client();

  /// Main A* dengan road data
  static Future<List<LatLng>?> findPath(
      LatLng start,
      LatLng goal,
      String apiKey, {
        int maxNodes = 2000,
      }) async {
    print('🔥 Starting Road-Based A* pathfinding: $start → $goal');
    final stopwatch = Stopwatch()..start();

    try {
      // 1. Dapatkan referensi rute dari ORS terlebih dahulu
      final referenceRoute = await _getORSRoute(start, goal, apiKey);
      if (referenceRoute == null) {
        print('❌ Failed to get reference route from ORS');
        return _createDirectRoute(start, goal);
      }

      // 2. Buat road network dari referensi route
      final roadNetwork = _createRoadNetwork(referenceRoute);

      // 3. Jalankan A* pada road network
      final astarPath = await _runAStarOnRoadNetwork(start, goal, roadNetwork, maxNodes);

      stopwatch.stop();

      if (astarPath != null && astarPath.length >= 2) {
        print('✅ Road-Based A* completed in ${stopwatch.elapsedMilliseconds}ms');
        return _optimizeAndSmoothPath(astarPath, referenceRoute);
      } else {
        print('❌ Road-Based A* failed, using reference route');
        return referenceRoute;
      }
    } catch (e) {
      print('❌ Error in A* pathfinding: $e');
      return _createDirectRoute(start, goal);
    }
  }

  /// Dapatkan rute referensi dari ORS
  static Future<List<LatLng>?> _getORSRoute(LatLng start, LatLng end, String apiKey) async {
    try {
      final response = await _httpClient.post(
        Uri.parse('https://api.openrouteservice.org/v2/directions/driving-car/geojson'),
        headers: {
          'Authorization': apiKey,
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode({
          'coordinates': [[start.longitude, start.latitude], [end.longitude, end.latitude]],
          'format': 'geojson',
          'geometry_simplify': false,
        }),
      ).timeout(Duration(seconds: 8));

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

  /// Buat road network dari rute referensi
  static Map<String, List<LatLng>> _createRoadNetwork(List<LatLng> referenceRoute) {
    final network = <String, List<LatLng>>{};
    const double snapDistance = 0.0005; // ~55m radius untuk snap ke road

    // Buat grid road network berdasarkan referensi route
    for (int i = 0; i < referenceRoute.length; i++) {
      final point = referenceRoute[i];
      final key = _getGridKey(point);

      if (!network.containsKey(key)) {
        network[key] = [];
      }

      // Tambahkan point dan neighbors di sekitarnya
      network[key]!.add(point);

      // Tambahkan connecting points ke grid neighbors
      _addConnectingPoints(network, point, snapDistance);
    }

    return network;
  }

  /// Tambahkan connecting points
  static void _addConnectingPoints(Map<String, List<LatLng>> network, LatLng center, double radius) {
    const step = 0.0001; // Grid step

    for (double lat = center.latitude - radius; lat <= center.latitude + radius; lat += step) {
      for (double lng = center.longitude - radius; lng <= center.longitude + radius; lng += step) {
        final point = LatLng(lat, lng);
        final distance = _calculateDistance(center, point);

        if (distance <= radius) {
          final key = _getGridKey(point);
          if (!network.containsKey(key)) {
            network[key] = [];
          }

          // Cek jika point belum ada di grid ini
          final exists = network[key]!.any((p) => _calculateDistance(p, point) < 20); // 20m threshold

          if (!exists) {
            network[key]!.add(point);
          }
        }
      }
    }
  }

  /// Jalankan A* pada road network
  static Future<List<LatLng>?> _runAStarOnRoadNetwork(
      LatLng start,
      LatLng goal,
      Map<String, List<LatLng>> roadNetwork,
      int maxNodes,
      ) async {
    final openSet = PriorityQueue<AStarNode>((a, b) => a.fCost.compareTo(b.fCost));
    final closedSet = <String>{};
    final gScores = <String, double>{};

    // Cari starting point terdekat di road network
    final startRoadPoint = _findNearestRoadPoint(start, roadNetwork) ?? start;
    final goalRoadPoint = _findNearestRoadPoint(goal, roadNetwork) ?? goal;

    final startNode = AStarNode(
      position: startRoadPoint,
      gCost: 0.0,
      hCost: _calculateDistance(startRoadPoint, goalRoadPoint),
    );

    openSet.add(startNode);
    gScores[_getNodeKey(startRoadPoint)] = 0.0;

    int nodesProcessed = 0;

    while (openSet.isNotEmpty && nodesProcessed < maxNodes) {
      final current = openSet.removeFirst();
      final currentKey = _getNodeKey(current.position);

      if (closedSet.contains(currentKey)) continue;
      closedSet.add(currentKey);
      nodesProcessed++;

      // Goal test
      if (_calculateDistance(current.position, goalRoadPoint) < 50) {
        return _reconstructPath(current, start, goal);
      }

      // Get neighbors dari road network
      final neighbors = _getRoadNetworkNeighbors(current.position, roadNetwork);

      for (final neighborPos in neighbors) {
        final neighborKey = _getNodeKey(neighborPos);

        if (closedSet.contains(neighborKey)) continue;

        final moveCost = _calculateDistance(current.position, neighborPos);
        final tentativeGCost = current.gCost + moveCost;

        if (gScores.containsKey(neighborKey) && tentativeGCost >= gScores[neighborKey]!) {
          continue;
        }

        gScores[neighborKey] = tentativeGCost;

        final neighbor = AStarNode(
          position: neighborPos,
          gCost: tentativeGCost,
          hCost: _calculateDistance(neighborPos, goalRoadPoint),
          parent: current,
        );

        openSet.add(neighbor);
      }
    }

    return null; // Path not found
  }

  /// Cari neighbors dari road network
  static List<LatLng> _getRoadNetworkNeighbors(LatLng position, Map<String, List<LatLng>> network) {
    final neighbors = <LatLng>[];
    const double searchRadius = 0.0008; // ~88m search radius

    // Cari di grid sekitar
    for (double lat = position.latitude - searchRadius;
    lat <= position.latitude + searchRadius;
    lat += 0.0002) {
      for (double lng = position.longitude - searchRadius;
      lng <= position.longitude + searchRadius;
      lng += 0.0002) {

        final gridKey = _getGridKey(LatLng(lat, lng));
        final gridPoints = network[gridKey];

        if (gridPoints != null) {
          for (final point in gridPoints) {
            final distance = _calculateDistance(position, point);
            if (distance > 5 && distance <= searchRadius * 111000) { // 5m minimum, convert to meters
              neighbors.add(point);
            }
          }
        }
      }
    }

    // Sort by distance untuk prioritas terdekat
    neighbors.sort((a, b) => _calculateDistance(position, a).compareTo(_calculateDistance(position, b)));

    // Ambil maksimal 12 neighbors terdekat
    return neighbors.take(12).toList();
  }

  /// Cari road point terdekat
  static LatLng? _findNearestRoadPoint(LatLng target, Map<String, List<LatLng>> network) {
    LatLng? nearest;
    double minDistance = double.infinity;

    for (final gridPoints in network.values) {
      for (final point in gridPoints) {
        final distance = _calculateDistance(target, point);
        if (distance < minDistance) {
          minDistance = distance;
          nearest = point;
        }
      }
    }

    return nearest;
  }

  /// Reconstruct path
  static List<LatLng> _reconstructPath(AStarNode goalNode, LatLng originalStart, LatLng originalGoal) {
    final path = <LatLng>[];
    AStarNode? current = goalNode;

    while (current != null) {
      path.insert(0, current.position);
      current = current.parent;
    }

    // Tambahkan start dan goal asli jika perlu
    if (path.isNotEmpty) {
      if (_calculateDistance(path.first, originalStart) > 25) {
        path.insert(0, originalStart);
      }
      if (_calculateDistance(path.last, originalGoal) > 25) {
        path.add(originalGoal);
      }
    }

    return path;
  }

  /// Optimize dan smooth path
  static List<LatLng> _optimizeAndSmoothPath(List<LatLng> astarPath, List<LatLng> referenceRoute) {
    if (astarPath.length <= 2) return astarPath;

    // 1. Optimize dengan menghapus node redundant
    final optimized = <LatLng>[astarPath.first];

    for (int i = 1; i < astarPath.length - 1; i++) {
      final prev = optimized.last;
      final current = astarPath[i];
      final next = astarPath[i + 1];

      // Hitung angle change
      final bearing1 = _calculateBearing(prev, current);
      final bearing2 = _calculateBearing(current, next);
      double angleDiff = (bearing2 - bearing1).abs();
      if (angleDiff > math.pi) angleDiff = 2 * math.pi - angleDiff;

      // Keep point jika ada perubahan signifikan atau jarak cukup jauh
      if (angleDiff > 0.1 || _calculateDistance(prev, current) > 100) {
        optimized.add(current);
      }
    }

    optimized.add(astarPath.last);

    // 2. Smooth dengan interpolasi
    return _applySmoothInterpolation(optimized);
  }

  /// Smooth interpolation
  static List<LatLng> _applySmoothInterpolation(List<LatLng> points) {
    if (points.length <= 2) return points;

    final smoothed = <LatLng>[points.first];

    for (int i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];
      final distance = _calculateDistance(start, end);

      // Tambahkan intermediate points untuk curves yang smooth
      if (distance > 150) {
        final segments = math.min((distance / 80).round(), 4);
        for (int j = 1; j < segments; j++) {
          final t = j / segments;
          final lat = start.latitude + (end.latitude - start.latitude) * t;
          final lng = start.longitude + (end.longitude - start.longitude) * t;

          // Tambahkan slight curve
          final curve = math.sin(t * math.pi) * 0.00003;
          final bearing = _calculateBearing(start, end);

          final curveLat = lat + curve * math.cos(bearing + math.pi / 2);
          final curveLng = lng + curve * math.sin(bearing + math.pi / 2);

          smoothed.add(LatLng(curveLat, curveLng));
        }
      }

      smoothed.add(end);
    }

    return smoothed;
  }

  /// Utility functions
  static String _getGridKey(LatLng position) {
    final lat = (position.latitude * 10000).round();
    final lng = (position.longitude * 10000).round();
    return '$lat,$lng';
  }

  static String _getNodeKey(LatLng position) {
    return '${position.latitude.toStringAsFixed(6)},${position.longitude.toStringAsFixed(6)}';
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

  /// Fallback direct route
  static List<LatLng> _createDirectRoute(LatLng start, LatLng goal) {
    final points = <LatLng>[];
    final distance = _calculateDistance(start, goal);
    final segments = math.max(8, (distance / 300).round());

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

  /// Dispose resources
  static void dispose() {
    _httpClient.close();
    _roadNetworkCache.clear();
  }
}