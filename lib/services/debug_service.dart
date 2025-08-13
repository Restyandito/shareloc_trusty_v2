import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/distance_notification.dart';
import 'map_services.dart';
import 'dart:math' as Math;

/// Model untuk data eksperimen A*
class AStarExperiment {
  final int experimentNumber;
  final LatLng startLocation;
  final LatLng goalLocation;
  final double hCost; // Jarak garis lurus (Euclidean)
  final double gCost; // Jarak tempuh pada jalan
  final double fCost; // Total biaya (gCost + hCost)
  final int nodesProcessed;
  final int executionTimeMs;
  final double routeLengthMeters;
  final String status; // "rute ditemukan", "gagal", etc.
  final DateTime timestamp;

  AStarExperiment({
    required this.experimentNumber,
    required this.startLocation,
    required this.goalLocation,
    required this.hCost,
    required this.gCost,
    required this.fCost,
    required this.nodesProcessed,
    required this.executionTimeMs,
    required this.routeLengthMeters,
    required this.status,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'no_percobaan': experimentNumber,
      'lokasi_awal':
      '${startLocation.latitude.toStringAsFixed(6)}, ${startLocation.longitude.toStringAsFixed(6)}',
      'lokasi_tujuan':
      '${goalLocation.latitude.toStringAsFixed(6)}, ${goalLocation.longitude.toStringAsFixed(6)}',
      'jarak_garis_lurus_m': hCost.toStringAsFixed(1),
      'jarak_tempuh_jalan_m': gCost.toStringAsFixed(1),
      'total_biaya_f': fCost.toStringAsFixed(1),
      'jumlah_node_diproses': nodesProcessed,
      'waktu_eksekusi_ms': executionTimeMs,
      'panjang_rute_meter': routeLengthMeters.toStringAsFixed(1),
      'keterangan': status,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Service untuk debugging dan monitoring system
class DebugService {
  static final List<AStarExperiment> _experiments = [];
  static int _experimentCounter = 1;
  final Math.Random _random = Math.Random();

  /// Record experiment A* baru
  void recordAStarExperiment({
    required LatLng startLocation,
    required LatLng goalLocation,
    required double hCost,
    required double gCost,
    required int nodesProcessed,
    required int executionTimeMs,
    required double routeLengthMeters,
    required String status,
  }) {
    final experiment = AStarExperiment(
      experimentNumber: _experimentCounter++,
      startLocation: startLocation,
      goalLocation: goalLocation,
      hCost: hCost,
      gCost: gCost,
      fCost: gCost + hCost,
      nodesProcessed: nodesProcessed,
      executionTimeMs: executionTimeMs,
      routeLengthMeters: routeLengthMeters,
      status: status,
      timestamp: DateTime.now(),
    );

    _experiments.add(experiment);

    // Keep only last 20 experiments
    if (_experiments.length > 20) {
      _experiments.removeAt(0);
    }

    print('🧪 A* Experiment #${experiment.experimentNumber} recorded: $status');
  }

  /// Get experiment data for debug panel
  Map<String, dynamic> getExperimentData() {
    return {
      'total_experiments': _experiments.length,
      'latest_experiments':
      _experiments.reversed.take(10).map((e) => e.toJson()).toList(),
      'statistics': _calculateStatistics(),
    };
  }

  /// Calculate statistics from experiments
  Map<String, dynamic> _calculateStatistics() {
    if (_experiments.isEmpty) {
      return {
        'success_rate': '0%',
        'avg_execution_time': '0ms',
        'avg_nodes_processed': '0',
        'avg_route_length': '0m',
      };
    }

    final successfulExperiments =
    _experiments.where((e) => e.status.contains('ditemukan')).toList();
    final successRate = (successfulExperiments.length / _experiments.length * 100)
        .toStringAsFixed(1);

    final avgExecutionTime = successfulExperiments.isNotEmpty
        ? (successfulExperiments
        .map((e) => e.executionTimeMs)
        .reduce((a, b) => a + b) /
        successfulExperiments.length)
        .round()
        : 0;

    final avgNodesProcessed = successfulExperiments.isNotEmpty
        ? (successfulExperiments
        .map((e) => e.nodesProcessed)
        .reduce((a, b) => a + b) /
        successfulExperiments.length)
        .round()
        : 0;

    final avgRouteLength = successfulExperiments.isNotEmpty
        ? (successfulExperiments
        .map((e) => e.routeLengthMeters)
        .reduce((a, b) => a + b) /
        successfulExperiments.length)
        .round()
        : 0;

    return {
      'success_rate': '$successRate%',
      'avg_execution_time': '${avgExecutionTime}ms',
      'avg_nodes_processed': '$avgNodesProcessed',
      'avg_route_length': '${avgRouteLength}m',
      'total_successful':
      '${successfulExperiments.length}/${_experiments.length}',
    };
  }

  /// Export experiment data sebagai CSV format
  String exportExperimentsAsCSV() {
    if (_experiments.isEmpty) return 'No experiments recorded';

    final header =
        'No,Lokasi Awal,Lokasi Tujuan,Jarak Garis Lurus (m),Jarak Tempuh Jalan (m),Total Biaya,Jumlah Node,Waktu Eksekusi (ms),Panjang Rute (m),Keterangan,Timestamp';

    final rows = _experiments.map((e) {
      return '${e.experimentNumber},"${e.startLocation.latitude.toStringAsFixed(6)}, ${e.startLocation.longitude.toStringAsFixed(6)}","${e.goalLocation.latitude.toStringAsFixed(6)}, ${e.goalLocation.longitude.toStringAsFixed(6)}",${e.hCost.toStringAsFixed(1)},${e.gCost.toStringAsFixed(1)},${e.fCost.toStringAsFixed(1)},${e.nodesProcessed},${e.executionTimeMs},${e.routeLengthMeters.toStringAsFixed(1)},"${e.status}",${e.timestamp.toIso8601String()}';
    }).join('\n');

    return '$header\n$rows';
  }

  /// Clear all experiment data
  void clearExperiments() {
    _experiments.clear();
    _experimentCounter = 1;
    print('🧪 All experiment data cleared');
  }

  /// Generate dummy experiment for testing
  void generateDummyExperiment() {
    final startLat = -6.2088 + (_random.nextDouble() - 0.5) * 0.01;
    final startLng = 106.8456 + (_random.nextDouble() - 0.5) * 0.01;
    final goalLat = -6.2088 + (_random.nextDouble() - 0.5) * 0.01;
    final goalLng = 106.8456 + (_random.nextDouble() - 0.5) * 0.01;

    final start = LatLng(startLat, startLng);
    final goal = LatLng(goalLat, goalLng);
    final hCost = MapUtils.calculateDistance(start, goal);

    recordAStarExperiment(
      startLocation: start,
      goalLocation: goal,
      hCost: hCost,
      gCost: hCost * (1.2 + _random.nextDouble() * 0.3), // variasi
      nodesProcessed: 150 + (_random.nextDouble() * 300).round(),
      executionTimeMs: 50 + (_random.nextDouble() * 200).round(),
      routeLengthMeters: hCost * (1.15 + _random.nextDouble() * 0.2),
      status: _random.nextDouble() > 0.1
          ? 'rute ditemukan'
          : 'gagal - timeout',
    );
  }

  /// Get comprehensive system info untuk debug panel
  Map<String, dynamic> getSystemInfo(
      LatLng? currentPosition,
      Map<String, LatLng> userLocations,
      Map<String, String> userNames,
      Set<String> connectedUserIds,
      Set<Marker> markers,
      Set<Polyline> polylines,
      Map<String, List<LatLng>> routeCache,
      List<DistanceNotification> activeNotifications,
      bool hasValidLocation,
      bool useAStarRouting,
      bool autoFollowEnabled,
      bool isManuallyControlled,
      bool vibrationEnabled,
      ) {
    final now = DateTime.now();

    return {
      'system': {
        'timestamp': now.toIso8601String(),
        'uptime': '${now.millisecondsSinceEpoch}ms',
        'memory_usage': 'tracking...',
        'app_version': '1.0.0+debug',
        'platform': 'Flutter/Firebase',
      },

      'location': {
        'has_valid_location': hasValidLocation,
        'current_position': currentPosition != null
            ? '${currentPosition.latitude.toStringAsFixed(6)}, ${currentPosition.longitude.toStringAsFixed(6)}'
            : 'null',
        'last_update': hasValidLocation ? now.toIso8601String() : 'never',
        'accuracy': hasValidLocation ? 'high' : 'none',
        'provider': 'GPS + Network',
      },

      'users': {
        'connected_users': connectedUserIds.length,
        'active_locations': userLocations.length,
        'user_list': userLocations.keys.take(5).map((userId) {
          final position = userLocations[userId];
          final name = userNames[userId] ?? 'Unknown';
          return '$name: ${position?.latitude.toStringAsFixed(4)}, ${position?.longitude.toStringAsFixed(4)}';
        }).toList(),
        'total_tracked': userNames.length,
      },

      'routing': {
        'algorithm': useAStarRouting ? 'A* Road-Based' : 'OpenRouteService',
        'active_routes': polylines.length,
        'cache_size': routeCache.length,
        'cache_keys': routeCache.keys.take(3).toList(),
        'total_polyline_points': polylines.fold<int>(0, (sum, poly) => sum + poly.points.length),
        'routing_mode': useAStarRouting ? 'smart' : 'basic',
      },

      'notifications': {
        'active_notifications': activeNotifications.length,
        'vibration_enabled': vibrationEnabled,
        'notification_details': activeNotifications.map((notif) => {
          'user': notif.userName,
          'distance': '${(notif.distance / 1000).toStringAsFixed(1)}km',
          'timestamp': notif.timestamp.toIso8601String(),
        }).toList(),
        'max_distance_threshold': '1000m',
      },

      'ui_state': {
        'auto_follow_enabled': autoFollowEnabled,
        'manually_controlled': isManuallyControlled,
        'routing_algorithm': useAStarRouting ? 'A*' : 'ORS',
        'vibration_enabled': vibrationEnabled,
        'debug_mode': true,
        'map_markers': markers.length,
      },

      'performance': {
        'markers_count': markers.length,
        'polylines_count': polylines.length,
        'cache_efficiency': routeCache.isNotEmpty ? '${(routeCache.length / (userLocations.length + 1) * 100).toStringAsFixed(1)}%' : '0%',
        'memory_markers': '${markers.length * 50}KB',
        'memory_polylines': '${polylines.fold<int>(0, (sum, poly) => sum + poly.points.length) * 20}KB',
      },

      'experiments': getExperimentData(),

      'network': {
        'firebase_connected': true,
        'realtime_db_status': 'connected',
        'firestore_status': 'connected',
        'api_calls_count': 'tracking...',
        'last_sync': now.toIso8601String(),
      },

      'firebase': {
        'auth_status': 'authenticated',
        'user_uid': 'hidden_for_privacy',
        'connection_state': 'online',
        'last_write': 'tracking...',
        'database_size': 'unknown',
      },
    };
  }

  /// Log system event
  void logEvent(String event, Map<String, dynamic> data) {
    final logEntry = {
      'timestamp': DateTime.now().toIso8601String(),
      'event': event,
      'data': data,
    };

    print('🔥 DEBUG LOG: ${JsonEncoder.withIndent('  ').convert(logEntry)}');
  }

  /// Log performance metrics
  void logPerformance(String operation, int durationMs, Map<String, dynamic>? metadata) {
    final perfLog = {
      'timestamp': DateTime.now().toIso8601String(),
      'operation': operation,
      'duration_ms': durationMs,
      'metadata': metadata ?? {},
    };

    print('⚡ PERFORMANCE: ${JsonEncoder.withIndent('  ').convert(perfLog)}');
  }

  /// Log routing operation
  void logRouting(String userId, LatLng start, LatLng goal, bool useAStar, int durationMs, bool success) {
    final routingLog = {
      'timestamp': DateTime.now().toIso8601String(),
      'user_id': userId,
      'start_location': '${start.latitude.toStringAsFixed(6)}, ${start.longitude.toStringAsFixed(6)}',
      'goal_location': '${goal.latitude.toStringAsFixed(6)}, ${goal.longitude.toStringAsFixed(6)}',
      'algorithm': useAStar ? 'A*' : 'ORS',
      'duration_ms': durationMs,
      'success': success,
      'distance_straight': MapUtils.calculateDistance(start, goal),
    };

    print('🗺️ ROUTING: ${JsonEncoder.withIndent('  ').convert(routingLog)}');
  }

  /// Get memory usage estimate
  Map<String, dynamic> getMemoryUsage(
      Set<Marker> markers,
      Set<Polyline> polylines,
      Map<String, List<LatLng>> routeCache,
      ) {
    final markerMemory = markers.length * 50; // Estimate: 50KB per marker
    final polylineMemory = polylines.fold<int>(0, (sum, poly) => sum + poly.points.length) * 20; // 20 bytes per point
    final cacheMemory = routeCache.values.fold<int>(0, (sum, route) => sum + route.length) * 20;

    return {
      'markers_kb': markerMemory,
      'polylines_kb': polylineMemory,
      'cache_kb': cacheMemory,
      'total_estimated_kb': markerMemory + polylineMemory + cacheMemory,
      'markers_count': markers.length,
      'polylines_count': polylines.length,
      'cache_routes': routeCache.length,
    };
  }
}