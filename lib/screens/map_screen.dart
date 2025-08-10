import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Untuk HapticFeedback
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;
import 'package:vibration/vibration.dart'; // Tambahkan dependency ini di pubspec.yaml

// 🔥 PRIORITY QUEUE UNTUK A*
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

// 🔥 A* NODE CLASS
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

// 🔥 ROAD-BASED A* PATHFINDER YANG MENGGUNAKAN DATA JALAN SEBENARNYA
class RoadBasedAStarPathfinder {
  static final Map<String, List<LatLng>> _roadNetworkCache = {};
  static final http.Client _httpClient = http.Client();

  // 🔥 MAIN A* DENGAN ROAD DATA
  static Future<List<LatLng>?> findPath(
      LatLng start,
      LatLng goal,
      String apiKey,
      {int maxNodes = 2000}
      ) async {
    print('🔥 Starting Road-Based A* pathfinding: $start → $goal');
    final stopwatch = Stopwatch()..start();

    // 1. Dapatkan referensi rute dari ORS terlebih dahulu
    final referenceRoute = await _getORSRoute(start, goal, apiKey);
    if (referenceRoute == null) {
      print('❌ Failed to get reference route from ORS');
      return _createDirectRoute(start, goal);
    }

    // 2. Buat road network dari referensi route
    final roadNetwork = _createRoadNetwork(referenceRoute);

    // 3. Jalankan A* pada road network
    final astarPath = await _runAStarOnRoadNetwork(
        start, goal, roadNetwork, maxNodes
    );

    stopwatch.stop();

    if (astarPath != null && astarPath.length >= 2) {
      print('✅ Road-Based A* completed in ${stopwatch.elapsedMilliseconds}ms');
      return _optimizeAndSmoothPath(astarPath, referenceRoute);
    } else {
      print('❌ Road-Based A* failed, using reference route');
      return referenceRoute;
    }
  }

  // 🔥 DAPATKAN RUTE REFERENSI DARI ORS
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

  // 🔥 BUAT ROAD NETWORK DARI RUTE REFERENSI
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

  // 🔥 TAMBAHKAN CONNECTING POINTS
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
          final exists = network[key]!.any((p) =>
          _calculateDistance(p, point) < 20); // 20m threshold

          if (!exists) {
            network[key]!.add(point);
          }
        }
      }
    }
  }

  // 🔥 JALANKAN A* PADA ROAD NETWORK
  static Future<List<LatLng>?> _runAStarOnRoadNetwork(
      LatLng start,
      LatLng goal,
      Map<String, List<LatLng>> roadNetwork,
      int maxNodes
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

  // 🔥 CARI NEIGHBORS DARI ROAD NETWORK
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
    neighbors.sort((a, b) =>
        _calculateDistance(position, a).compareTo(_calculateDistance(position, b)));

    // Ambil maksimal 12 neighbors terdekat
    return neighbors.take(12).toList();
  }

  // 🔥 CARI ROAD POINT TERDEKAT
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

  // 🔥 RECONSTRUCT PATH
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

  // 🔥 OPTIMIZE DAN SMOOTH PATH
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

  // 🔥 SMOOTH INTERPOLATION
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

  // 🔥 UTILITY FUNCTIONS
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

  // 🔥 FALLBACK DIRECT ROUTE
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
}

// 🔥 SMART ROUTING SYSTEM (Updated)
class SmartRouting {
  static final http.Client _http = http.Client();

  static Future<List<LatLng>?> getOptimizedRoute(
      LatLng start,
      LatLng end,
      String apiKey,
      {bool useAStar = true}
      ) async {
    if (useAStar) {
      print('🔥 Using Road-Based A* Algorithm');

      final astarPath = await RoadBasedAStarPathfinder.findPath(start, end, apiKey);
      if (astarPath != null && astarPath.length >= 2) {
        return astarPath;
      }

      print('⚠️ Road-Based A* failed, falling back to ORS');
    }

    final orsRoute = await _getORSRoute(start, end, apiKey);
    return orsRoute ?? RoadBasedAStarPathfinder._createDirectRoute(start, end);
  }

  static Future<List<LatLng>?> _getORSRoute(LatLng start, LatLng end, String apiKey) async {
    try {
      final response = await _http.post(
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
}

// 🔥 VIBRATION PATTERN ENUM
enum VibrationPattern {
  warning,  // Pattern untuk warning jarak jauh
  alert,    // Pattern untuk alert multiple users
  gentle,   // Pattern untuk notifikasi biasa
}

// 🔥 DISTANCE NOTIFICATION CLASS
class DistanceNotification {
  final String userId;
  final String userName;
  final double distance;
  final DateTime timestamp;

  DistanceNotification({
    required this.userId,
    required this.userName,
    required this.distance,
    required this.timestamp,
  });
}

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  // Core components
  GoogleMapController? mapController;
  final _auth = FirebaseAuth.instance;
  final _database = FirebaseDatabase.instance.ref();
  final _firestore = FirebaseFirestore.instance;
  final _location = Location();
  final _http = http.Client();

  // API Key
  final String orsApiKey = 'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6ImFhZTYxMWUxMGFjZTRmYzliMWQ5ZmEyNDQ0ZDVlY2RjIiwiaCI6Im11cm11cjY0In0=';

  // State variables
  LatLng? _currentPosition;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  Map<String, LatLng> _userLocations = {};
  Map<String, String> _userNames = {};
  Set<String> _connectedUserIds = {};

  // Settings
  bool _hasValidLocation = false;
  bool _useAStarRouting = true;
  bool _autoFollowEnabled = true;
  bool _isManuallyControlled = false;
  bool _vibrationEnabled = true; // 🔥 VIBRATION SETTING

  // 🔥 DISTANCE NOTIFICATION VARIABLES
  List<DistanceNotification> _distanceNotifications = [];
  Timer? _notificationTimer;
  AnimationController? _notificationAnimController;
  Animation<double>? _notificationAnimation;
  final double _maxDistance = 1000.0; // 1km maksimal distance
  final Duration _notificationInterval = Duration(seconds: 15); // interval 15 detik
  Map<String, DateTime> _lastNotificationTime = {};
  Map<String, DateTime> _lastVibrationTime = {}; // 🔥 VIBRATION COOLDOWN

  // Subscriptions & Timers
  final Map<String, StreamSubscription<DatabaseEvent>> _userLocationSubs = {};
  StreamSubscription<LocationData>? _myLocSub;
  final Map<String, Timer> _routeDebouncers = {};
  Timer? _autoFollowTimer;

  // Cache
  final Map<String, List<LatLng>> _routeCache = {};

  @override
  void initState() {
    super.initState();
    _setupNotificationAnimation();
    _initLocation();
    _listenToConnectedUsers();
    _startDistanceNotificationTimer();
  }

  @override
  void dispose() {
    _routeDebouncers.values.forEach((t) => t.cancel());
    _userLocationSubs.values.forEach((sub) => sub.cancel());
    _myLocSub?.cancel();
    _autoFollowTimer?.cancel();
    _notificationTimer?.cancel();

    // Dispose animation controller with safety check
    if (_notificationAnimController != null) {
      _notificationAnimController!.dispose();
      _notificationAnimController = null;
    }

    _http.close();
    super.dispose();
  }

  // 🔥 VIBRATION FUNCTIONS
  Future<void> _triggerVibration(VibrationPattern pattern) async {
    if (!_vibrationEnabled) return;

    try {
      // Cek apakah device support vibration
      bool? hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator != true) return;

      switch (pattern) {
        case VibrationPattern.warning:
        // Pattern: short-pause-short-pause-long untuk warning
          await Vibration.vibrate(duration: 200);
          await Future.delayed(Duration(milliseconds: 100));
          await Vibration.vibrate(duration: 200);
          await Future.delayed(Duration(milliseconds: 100));
          await Vibration.vibrate(duration: 500);
          break;

        case VibrationPattern.alert:
        // Pattern: short bursts untuk alert
          for (int i = 0; i < 3; i++) {
            await Vibration.vibrate(duration: 150);
            if (i < 2) await Future.delayed(Duration(milliseconds: 100));
          }
          break;

        case VibrationPattern.gentle:
        // Pattern: single gentle vibration
          await Vibration.vibrate(duration: 300);
          break;
      }

      // Haptic feedback sebagai fallback
      HapticFeedback.heavyImpact();
    } catch (e) {
      print('❌ Vibration error: $e');
      // Fallback ke haptic feedback jika vibration gagal
      HapticFeedback.heavyImpact();
    }
  }

  bool _shouldVibrate(String userId) {
    final now = DateTime.now();
    final lastVibration = _lastVibrationTime[userId];

    // Vibration cooldown 30 detik per user untuk menghindari spam
    if (lastVibration != null &&
        now.difference(lastVibration) < Duration(seconds: 30)) {
      return false;
    }

    return true;
  }
  void _setupNotificationAnimation() {
    _notificationAnimController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );

    _notificationAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _notificationAnimController!,
      curve: Curves.easeOutBack,
    ));
  }

  // 🔥 START DISTANCE NOTIFICATION TIMER
  void _startDistanceNotificationTimer() {
    _notificationTimer?.cancel();
    _notificationTimer = Timer.periodic(_notificationInterval, (timer) {
      _checkDistanceNotifications();
    });
  }

  // 🔥 CHECK DISTANCE NOTIFICATIONS
  void _checkDistanceNotifications() {
    if (!_hasValidLocation || _currentPosition == null) return;

    final now = DateTime.now();
    final farUsers = <DistanceNotification>[];
    bool shouldVibrate = false;

    for (final userId in _userLocations.keys) {
      final userLocation = _userLocations[userId];
      if (userLocation == null) continue;

      final distance = _distanceMeters(_currentPosition!, userLocation);

      // Cek apakah jarak terlalu jauh (lebih dari 1km)
      if (distance > _maxDistance) {
        final lastNotified = _lastNotificationTime[userId];

        // Cek apakah sudah saatnya untuk notifikasi lagi
        if (lastNotified == null || now.difference(lastNotified) >= _notificationInterval) {
          final userName = _userNames[userId] ?? 'User';
          farUsers.add(DistanceNotification(
            userId: userId,
            userName: userName,
            distance: distance,
            timestamp: now,
          ));

          _lastNotificationTime[userId] = now;

          // 🔥 CEK APAKAH PERLU VIBRATION
          if (_shouldVibrate(userId)) {
            shouldVibrate = true;
            _lastVibrationTime[userId] = now;
          }
        }
      } else {
        // Reset timer jika user sudah dekat lagi
        _lastNotificationTime.remove(userId);
        _lastVibrationTime.remove(userId);
      }
    }

    if (farUsers.isNotEmpty && mounted) {
      setState(() {
        _distanceNotifications = farUsers;
      });

      // 🔥 TRIGGER VIBRATION BERDASARKAN JUMLAH USER
      if (shouldVibrate) {
        if (farUsers.length == 1) {
          _triggerVibration(VibrationPattern.warning);
        } else if (farUsers.length <= 3) {
          _triggerVibration(VibrationPattern.alert);
        } else {
          // Untuk banyak user, gunakan pattern yang lebih intense
          _triggerVibration(VibrationPattern.alert);
          Future.delayed(Duration(milliseconds: 800), () {
            _triggerVibration(VibrationPattern.gentle);
          });
        }
      }

      _notificationAnimController?.reset();
      _notificationAnimController?.forward().then((_) {
        // Auto hide setelah 5 detik
        Timer(Duration(seconds: 5), () {
          if (mounted) {
            _hideDistanceNotifications();
          }
        });
      });
    }
  }

  // 🔥 HIDE DISTANCE NOTIFICATIONS
  void _hideDistanceNotifications() {
    if (!mounted || _notificationAnimController == null) return;

    _notificationAnimController?.reverse().then((_) {
      if (mounted) {
        setState(() {
          _distanceNotifications.clear();
        });
      }
    });
  }

  // 🔥 LOCATION MANAGEMENT
  Future<void> _initLocation() async {
    try {
      if (!await _location.serviceEnabled() &&
          !await _location.requestService()) return;

      var permission = await _location.hasPermission();
      if (permission == PermissionStatus.denied) {
        permission = await _location.requestPermission();
        if (permission != PermissionStatus.granted) return;
      }

      final locationData = await _location.getLocation();
      if (locationData.latitude != null && locationData.longitude != null) {
        _currentPosition =
            LatLng(locationData.latitude!, locationData.longitude!);
        _hasValidLocation = true;
        _updateMyLocationMarker();
        _shareMyLocation();
        _moveCameraToMyLocation();
      }

      _myLocSub = _location.onLocationChanged.listen((loc) {
        if (loc.latitude == null || loc.longitude == null) return;

        final newPosition = LatLng(loc.latitude!, loc.longitude!);
        if (_currentPosition != null &&
            _distanceMeters(_currentPosition!, newPosition) < 10) return;

        _currentPosition = newPosition;
        _hasValidLocation = true;
        _updateMyLocationMarker();
        _shareMyLocation();

        if (_autoFollowEnabled &&
            !_isManuallyControlled) _moveCameraToMyLocation();

        _userLocations.keys.forEach(_scheduleRouteUpdate);
      });
    } catch (e) {
      print('❌ Location error: $e');
    }
  }

  void _updateMyLocationMarker() {
    if (!_hasValidLocation || _currentPosition == null) return;

    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'my_location');
      _markers.add(Marker(
        markerId: MarkerId('my_location'),
        position: _currentPosition!,
        infoWindow: InfoWindow(title: '📍 Lokasi Saya'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      ));
    });
  }

  Future<void> _shareMyLocation() async {
    final user = _auth.currentUser;
    if (user == null || !_hasValidLocation || _currentPosition == null) return;

    try {
      await _database.child('locations').child(user.uid).set({
        'latitude': _currentPosition!.latitude,
        'longitude': _currentPosition!.longitude,
        'timestamp': ServerValue.timestamp,
      });
    } catch (e) {
      print('❌ Share location error: $e');
    }
  }

  // 🔥 USER TRACKING
  void _listenToConnectedUsers() {
    final user = _auth.currentUser;
    if (user == null) return;

    _database
        .child('connections')
        .child(user.uid)
        .onValue
        .listen((event) {
      if (!mounted) return;

      if (event.snapshot.exists) {
        final connections = Map<String, dynamic>.from(
            event.snapshot.value as Map);
        final newConnected = connections.keys
            .where((userId) => connections[userId]['status'] == 'accepted')
            .toSet();

        final toRemove = _connectedUserIds.difference(newConnected);
        final toAdd = newConnected.difference(_connectedUserIds);

        toRemove.forEach((userId) {
          _userLocationSubs[userId]?.cancel();
          _userLocationSubs.remove(userId);
          _removeUserData(userId);
        });

        toAdd.forEach(_subscribeToUserLocation);

        setState(() => _connectedUserIds = newConnected);
      } else {
        _userLocationSubs.values.forEach((sub) => sub.cancel());
        _userLocationSubs.clear();
        setState(() {
          _connectedUserIds.clear();
          _userLocations.clear();
          _clearAllUserData();
        });
      }
    });
  }

  void _subscribeToUserLocation(String userId) {
    final sub = _database
        .child('locations')
        .child(userId)
        .onValue
        .listen((event) {
      if (!mounted) return;

      if (event.snapshot.exists) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        final userLatLng = LatLng(
            data['latitude'].toDouble(), data['longitude'].toDouble());

        _userLocations[userId] = userLatLng;
        _addUserMarker(userId, userLatLng);
        _requestRouteImmediately(userId);
      } else {
        _removeUserData(userId);
      }
    });

    _userLocationSubs[userId] = sub;
  }

  Future<void> _addUserMarker(String userId, LatLng position) async {
    String userName = 'User';

    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        userName = doc.data()?['name'] ?? 'User';
      } else {
        final snapshot = await _database.child('users').child(userId).once();
        if (snapshot.snapshot.exists) {
          final userData = snapshot.snapshot.value as Map;
          userName = userData['name'] ?? 'User';
        }
      }
    } catch (e) {
      print('⚠️ Error getting user name: $e');
    }

    _userNames[userId] = userName;

    setState(() {
      _markers.removeWhere((marker) => marker.markerId.value == userId);
      _markers.add(Marker(
        markerId: MarkerId(userId),
        position: position,
        infoWindow: InfoWindow(
            title: '👤 $userName', snippet: 'Sedang berbagi lokasi'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ));
    });
  }

  // 🔥 ROUTING SYSTEM
  void _requestRouteImmediately(String userId) {
    _routeDebouncers[userId]?.cancel();
    _requestRoute(userId);
    _scheduleRouteUpdate(userId);
  }

  void _scheduleRouteUpdate(String userId) {
    _routeDebouncers[userId]?.cancel();
    _routeDebouncers[userId] =
        Timer(Duration(milliseconds: 400), () => _requestRoute(userId));
  }

  Future<void> _requestRoute(String userId) async {
    if (!_hasValidLocation || _currentPosition == null) return;

    final userLocation = _userLocations[userId];
    if (userLocation == null) return;

    final cacheKey = '${_currentPosition!.latitude.toStringAsFixed(
        4)}-${userLocation.latitude.toStringAsFixed(4)}';
    if (_routeCache.containsKey(cacheKey)) {
      _displayRoute(userId, _routeCache[cacheKey]!);
      return;
    }

    final route = await SmartRouting.getOptimizedRoute(
      _currentPosition!,
      userLocation,
      orsApiKey,
      useAStar: _useAStarRouting,
    );

    if (route != null) {
      _routeCache[cacheKey] = route;
      _displayRoute(userId, route);
    }
  }

  void _displayRoute(String userId, List<LatLng> route) {
    if (!mounted) return;

    setState(() {
      _polylines.removeWhere((poly) =>
      poly.polylineId.value == 'route_$userId');
      _polylines.add(Polyline(
        polylineId: PolylineId('route_$userId'),
        color: _useAStarRouting ? Colors.green.shade600 : Colors.blue.shade600,
        width: 5,
        points: route,
        geodesic: true,
        jointType: JointType.round,
        endCap: Cap.roundCap,
        startCap: Cap.roundCap,
      ));
    });
  }

  // 🔥 CAMERA MANAGEMENT
  void _moveCameraToMyLocation() {
    if (mapController != null && _currentPosition != null) {
      mapController!.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: _currentPosition!, zoom: 16.0),
      ));
    }
  }

  void _onCameraMove(CameraPosition position) {
    if (_autoFollowEnabled && _currentPosition != null) {
      final distance = _distanceMeters(_currentPosition!, position.target);

      if (distance > 100) {
        setState(() => _isManuallyControlled = true);
        _autoFollowTimer?.cancel();
        _autoFollowTimer = Timer(Duration(seconds: 3), () {
          setState(() => _isManuallyControlled = false);
        });
      }
    }
  }

  void _focusOnUser(String userId) {
    final userLocation = _userLocations[userId];
    if (userLocation != null && mapController != null) {
      setState(() => _isManuallyControlled = true);

      mapController!.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: userLocation, zoom: 15.0),
      ));

      _autoFollowTimer?.cancel();
      _autoFollowTimer = Timer(Duration(seconds: 3), () {
        setState(() => _isManuallyControlled = false);
      });
    }
  }

  // 🔥 UTILITY FUNCTIONS
  double _distanceMeters(LatLng a, LatLng b) {
    const R = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;

    final sinDLat = math.sin(dLat / 2);
    final sinDLon = math.sin(dLon / 2);
    final h = sinDLat * sinDLat +
        math.cos(lat1) * math.cos(lat2) * sinDLon * sinDLon;
    return R * 2 * math.atan2(math.sqrt(h), math.sqrt(1.0 - h));
  }

  String _getDistanceText(String userId) {
    if (!_hasValidLocation || _currentPosition == null) return '- km';

    final userLocation = _userLocations[userId];
    if (userLocation == null) return '- km';

    final distance = _distanceMeters(_currentPosition!, userLocation);
    return distance < 1000 ? '${distance.round()}m' : '${(distance / 1000)
        .toStringAsFixed(1)}km';
  }

  void _removeUserData(String userId) {
    _routeDebouncers[userId]?.cancel();
    _routeDebouncers.remove(userId);
    _routeCache.removeWhere((key, value) => key.contains(userId));
    _lastNotificationTime.remove(userId);
    _lastVibrationTime.remove(userId); // 🔥 CLEANUP VIBRATION DATA

    setState(() {
      _markers.removeWhere((marker) => marker.markerId.value == userId);
      _polylines.removeWhere((poly) =>
      poly.polylineId.value == 'route_$userId');
      _userLocations.remove(userId);
      _userNames.remove(userId);
    });
  }

  void _clearAllUserData() {
    setState(() {
      _markers.removeWhere((marker) => marker.markerId.value != 'my_location');
      _polylines.clear();
    });
    _routeCache.clear();
    _lastNotificationTime.clear();
    _lastVibrationTime.clear(); // 🔥 CLEANUP VIBRATION DATA
  }

  // 🔥 BUILD DISTANCE NOTIFICATION
  Widget _buildDistanceNotifications() {
    if (_distanceNotifications.isEmpty ||
        _notificationAnimation == null ||
        _notificationAnimController == null) {
      return SizedBox.shrink();
    }

    return Positioned(
      top: MediaQuery.of(context).padding.top + 72, // Dibawah control bar
      left: 16,
      right: 16,
      child: AnimatedBuilder(
        animation: _notificationAnimation!,
        builder: (context, child) {
          final animValue = _notificationAnimation!.value.clamp(0.0, 1.0);

          return Transform.scale(
            scale: animValue,
            child: Opacity(
              opacity: animValue,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.3,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.orange.shade50,
                      Colors.red.shade50,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.orange.shade200,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.2),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildNotificationHeader(),
                    if (_distanceNotifications.length == 1)
                      _buildSingleNotification(_distanceNotifications.first)
                    else
                      _buildMultipleNotifications(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotificationHeader() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.warning_rounded,
              color: Colors.orange.shade800,
              size: 20,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Jarak Terlalu Jauh!',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800,
                      ),
                    ),
                    if (_vibrationEnabled) ...[
                      SizedBox(width: 8),
                      Icon(
                        Icons.vibration,
                        color: Colors.purple.shade600,
                        size: 16,
                      ),
                    ],
                  ],
                ),
                Text(
                  _distanceNotifications.length == 1
                      ? 'Teman Anda berada lebih dari 1km'
                      : '${_distanceNotifications.length} teman berada lebih dari 1km',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _hideDistanceNotifications,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.close_rounded,
                  color: Colors.orange.shade600,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleNotification(DistanceNotification notification) {
    final distanceKm = (notification.distance / 1000).toStringAsFixed(1);

    return Container(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.red.shade400, Colors.red.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Center(
              child: Text(
                notification.userName.isNotEmpty
                    ? notification.userName[0].toUpperCase()
                    : 'U',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification.userName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Colors.grey.shade800,
                  ),
                ),
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      color: Colors.red.shade500,
                      size: 14,
                    ),
                    SizedBox(width: 4),
                    Text(
                      '$distanceKm km dari Anda',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                _focusOnUser(notification.userId);
                _hideDistanceNotifications();
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Lihat',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultipleNotifications() {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.2,
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.symmetric(vertical: 8),
        itemCount: _distanceNotifications.length,
        itemBuilder: (context, index) {
          final notification = _distanceNotifications[index];
          final distanceKm = (notification.distance / 1000).toStringAsFixed(1);

          return Container(
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade100),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.red.shade500,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      notification.userName.isNotEmpty
                          ? notification.userName[0].toUpperCase()
                          : 'U',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.userName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      Text(
                        '$distanceKm km',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.red.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      _focusOnUser(notification.userId);
                      _hideDistanceNotifications();
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.visibility_rounded,
                        color: Colors.orange.shade600,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // 🔥 UI BUILDERS
  Widget _buildTopControlBar() {
    return Positioned(
      top: MediaQuery
          .of(context)
          .padding
          .top + 8,
      left: 16,
      right: 16,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildControlButton(
                icon: _autoFollowEnabled
                    ? (_isManuallyControlled ? Icons.pause_circle_filled : Icons
                    .my_location)
                    : Icons.location_disabled,
                label: _autoFollowEnabled
                    ? (_isManuallyControlled ? 'Pause' : 'Follow')
                    : 'Manual',
                color: _autoFollowEnabled
                    ? (_isManuallyControlled ? Colors.orange : Colors.green)
                    : Colors.grey,
                onTap: () {
                  setState(() {
                    _autoFollowEnabled = !_autoFollowEnabled;
                    if (_autoFollowEnabled) {
                      _isManuallyControlled = false;
                      _moveCameraToMyLocation();
                    }
                  });
                },
              ),
            ),
            Container(width: 1, height: 24, color: Colors.grey.shade200),
            Expanded(
              child: _buildControlButton(
                icon: _vibrationEnabled ? Icons.vibration : Icons.phone_android,
                label: _vibrationEnabled ? 'Vibrate' : 'Silent',
                color: _vibrationEnabled ? Colors.purple.shade600 : Colors.grey,
                onTap: () {
                  setState(() => _vibrationEnabled = !_vibrationEnabled);
                  // Test vibration saat toggle
                  if (_vibrationEnabled) {
                    _triggerVibration(VibrationPattern.gentle);
                  }
                },
              ),
            ),
            Container(width: 1, height: 24, color: Colors.grey.shade200),
            Expanded(
              child: _buildControlButton(
                icon: _useAStarRouting ? Icons.route : Icons.timeline,
                label: _useAStarRouting ? 'Smart' : 'Basic',
                color: _useAStarRouting ? Colors.green.shade600 : Colors.blue,
                onTap: () {
                  setState(() => _useAStarRouting = !_useAStarRouting);
                  _routeCache.clear();
                  _userLocations.keys.forEach(_requestRoute);
                },
              ),
            ),
            Container(width: 1, height: 24, color: Colors.grey.shade200),
            Expanded(
              child: _buildControlButton(
                icon: Icons.refresh,
                label: 'Refresh',
                color: Colors.blue.shade600,
                onTap: () {
                  _initLocation();
                  _listenToConnectedUsers();
                  _routeCache.clear();
                  _userLocations.keys.forEach(_requestRoute);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackingList() {
    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery
              .of(context)
              .size
              .height * 0.4,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 12,
              offset: Offset(0, -3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildListHeader(),
            if (_userLocations.isEmpty)
              _buildEmptyState()
            else
              _buildUserList(),
          ],
        ),
      ),
    );
  }

  Widget _buildListHeader() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade100, width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _useAStarRouting ? Colors.green.shade50 : Colors.blue
                  .shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.people_rounded,
              color: _useAStarRouting ? Colors.green.shade600 : Colors.blue
                  .shade600,
              size: 20,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _useAStarRouting ? 'Rute Pintar' : 'Orang yang Dilacak',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
                if (_userLocations.isNotEmpty)
                  Text(
                    _useAStarRouting
                        ? '${_userLocations.length} rute optimal'
                        : '${_userLocations.length} teman aktif',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
              ],
            ),
          ),
          if (_userLocations.isNotEmpty)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _useAStarRouting ? Colors.green.shade600 : Colors.blue
                    .shade600,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                '${_userLocations.length}',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUserList() {
    return Flexible(
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.symmetric(vertical: 8),
        itemCount: _userLocations.length,
        itemBuilder: (context, index) {
          final userId = _userLocations.keys.elementAt(index);
          return _buildUserCard(userId);
        },
      ),
    );
  }

  Widget _buildUserCard(String userId) {
    final userName = _userNames[userId] ?? 'User';
    final distance = _getDistanceText(userId);
    final userLocation = _userLocations[userId];
    final isFarAway = userLocation != null && _currentPosition != null
        ? _distanceMeters(_currentPosition!, userLocation) > _maxDistance
        : false;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _focusOnUser(userId),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isFarAway ? Colors.red.shade50 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isFarAway ? Colors.red.shade200 : Colors.grey.shade100,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isFarAway
                          ? [Colors.red.shade400, Colors.red.shade600]
                          : _useAStarRouting
                          ? [Colors.green.shade400, Colors.green.shade600]
                          : [Colors.blue.shade400, Colors.blue.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Center(
                    child: Text(
                      userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isFarAway
                                  ? Colors.red
                                  : _useAStarRouting ? Colors.green : Colors.blue,
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              isFarAway
                                  ? 'Jarak terlalu jauh!'
                                  : _useAStarRouting
                                  ? 'Rute optimal aktif'
                                  : 'Berbagi lokasi aktif',
                              style: TextStyle(
                                fontSize: 12,
                                color: isFarAway
                                    ? Colors.red.shade600
                                    : Colors.grey.shade600,
                                fontWeight: isFarAway ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isFarAway
                            ? Colors.red.shade50
                            : _useAStarRouting ? Colors.green.shade50 : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        distance,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isFarAway
                              ? Colors.red.shade700
                              : _useAStarRouting
                              ? Colors.green.shade700
                              : Colors.blue.shade700,
                        ),
                      ),
                    ),
                    SizedBox(height: 4),
                    Icon(
                      isFarAway ? Icons.warning_rounded : Icons.touch_app,
                      size: 14,
                      color: isFarAway ? Colors.red.shade400 : Colors.grey.shade400,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.location_off_rounded,
              size: 32,
              color: Colors.grey.shade400,
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Belum ada teman yang berbagi lokasi',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 4),
          Text(
            'Ajak teman untuk berbagi lokasi',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade400,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingButtons() {
    return Positioned(
      bottom: _userLocations.isNotEmpty ?
      (MediaQuery
          .of(context)
          .size
          .height * 0.4 + 32) : 32,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_currentPosition != null)
            Container(
              margin: EdgeInsets.only(bottom: 12),
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _autoFollowEnabled && !_isManuallyControlled
                          ? [Colors.green.shade400, Colors.green.shade600]
                          : [Colors.grey.shade400, Colors.grey.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() => _isManuallyControlled = false);
                        _moveCameraToMyLocation();
                      },
                      borderRadius: BorderRadius.circular(28),
                      child: Icon(
                        Icons.my_location_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Container(
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(28),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _useAStarRouting
                        ? [Colors.green.shade500, Colors.green.shade700]
                        : [Colors.blue.shade500, Colors.blue.shade700],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (mapController != null && _userLocations.isNotEmpty &&
                          _currentPosition != null) {
                        setState(() => _isManuallyControlled = true);

                        final allPositions = [
                          _currentPosition!,
                          ..._userLocations.values
                        ];
                        final minLat = allPositions.map((p) => p.latitude)
                            .reduce((a, b) => a < b ? a : b);
                        final maxLat = allPositions.map((p) => p.latitude)
                            .reduce((a, b) => a > b ? a : b);
                        final minLng = allPositions.map((p) => p.longitude)
                            .reduce((a, b) => a < b ? a : b);
                        final maxLng = allPositions.map((p) => p.longitude)
                            .reduce((a, b) => a > b ? a : b);

                        mapController!.animateCamera(
                            CameraUpdate.newLatLngBounds(
                              LatLngBounds(
                                southwest: LatLng(minLat - 0.01, minLng - 0.01),
                                northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
                              ),
                              100.0,
                            ));

                        _autoFollowTimer?.cancel();
                        _autoFollowTimer = Timer(Duration(seconds: 3), () {
                          setState(() => _isManuallyControlled = false);
                        });
                      } else if (_currentPosition != null) {
                        setState(() => _isManuallyControlled = false);
                        _moveCameraToMyLocation();
                      }
                    },
                    borderRadius: BorderRadius.circular(28),
                    child: Icon(
                      _userLocations.isNotEmpty
                          ? Icons.zoom_out_map_rounded
                          : Icons.location_searching_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) => mapController = controller,
            onCameraMove: _onCameraMove,
            initialCameraPosition: CameraPosition(
              target: _currentPosition ?? LatLng(-6.2088, 106.8456),
              zoom: 13.0,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            mapType: MapType.normal,
            compassEnabled: true,
            rotateGesturesEnabled: true,
            scrollGesturesEnabled: true,
            tiltGesturesEnabled: true,
            zoomGesturesEnabled: true,
          ),
          _buildTopControlBar(),
          _buildDistanceNotifications(), // 🔥 DISTANCE NOTIFICATION WIDGET
          _buildFloatingButtons(),
          if (_userLocations.isNotEmpty) _buildTrackingList(),
        ],
      ),
    );
  }
}