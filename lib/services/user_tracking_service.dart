import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'map_services.dart';

/// Service untuk mengelola tracking user dan routing
class UserTrackingService {
  final FirebaseAuth auth;
  final DatabaseReference database;
  final FirebaseFirestore firestore;
  final Function(String userId, LatLng position, String name) onUserUpdate;
  final Function(String userId) onUserRemove;
  final Function(String userId, List<LatLng> route, bool useAStar) onRouteUpdate; // Callback untuk polyline

  UserTrackingService({
    required this.auth,
    required this.database,
    required this.firestore,
    required this.onUserUpdate,
    required this.onUserRemove,
    required this.onRouteUpdate, // Tambahkan callback
  });

  // State
  Set<String> _connectedUserIds = {};
  final Map<String, StreamSubscription<DatabaseEvent>> _userLocationSubs = {};
  final Map<String, Timer> _routeDebouncers = {};
  final Map<String, List<LatLng>> _routeCache = {};

  Set<String> get connectedUserIds => _connectedUserIds;
  Map<String, List<LatLng>> get routeCache => _routeCache;

  /// Initialize user tracking
  void initialize() {
    _listenToConnectedUsers();
  }

  /// Listen to connected users changes
  void _listenToConnectedUsers() {
    final user = auth.currentUser;
    if (user == null) return;

    database
        .child('connections')
        .child(user.uid)
        .onValue
        .listen((event) {
      if (event.snapshot.exists) {
        final connections = Map<String, dynamic>.from(event.snapshot.value as Map);
        final newConnected = connections.keys
            .where((userId) => connections[userId]['status'] == 'accepted')
            .toSet();

        final toRemove = _connectedUserIds.difference(newConnected);
        final toAdd = newConnected.difference(_connectedUserIds);

        // Remove disconnected users
        toRemove.forEach((userId) {
          _userLocationSubs[userId]?.cancel();
          _userLocationSubs.remove(userId);
          _routeDebouncers[userId]?.cancel();
          _routeDebouncers.remove(userId);
          onUserRemove(userId);
        });

        // Add new connected users
        toAdd.forEach(_subscribeToUserLocation);

        _connectedUserIds = newConnected;
      } else {
        // No connections
        _clearAllSubscriptions();
        _connectedUserIds.clear();
      }
    });
  }

  /// Subscribe to specific user location
  void _subscribeToUserLocation(String userId) {
    final sub = database
        .child('locations')
        .child(userId)
        .onValue
        .listen((event) {
      if (event.snapshot.exists) {
        final data = Map<String, dynamic>.from(event.snapshot.value as Map);
        final userLatLng = LatLng(
          data['latitude'].toDouble(),
          data['longitude'].toDouble(),
        );

        _getUserNameAndUpdate(userId, userLatLng);
      } else {
        onUserRemove(userId);
      }
    });

    _userLocationSubs[userId] = sub;
  }

  /// Get user name and update location
  Future<void> _getUserNameAndUpdate(String userId, LatLng position) async {
    String userName = 'User';

    try {
      // Try Firestore first
      final doc = await firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        userName = doc.data()?['name'] ?? 'User';
      } else {
        // Fallback to Realtime Database
        final snapshot = await database.child('users').child(userId).once();
        if (snapshot.snapshot.exists) {
          final userData = snapshot.snapshot.value as Map;
          userName = userData['name'] ?? 'User';
        }
      }
    } catch (e) {
      print('⚠️ Error getting user name for $userId: $e');
    }

    onUserUpdate(userId, position, userName);
  }

  /// Request route for specific user
  void requestRoute(String userId, LatLng? currentPosition, LatLng userPosition, bool useAStar) {
    if (currentPosition == null) return;

    _routeDebouncers[userId]?.cancel();
    _routeDebouncers[userId] = Timer(Duration(milliseconds: 400), () {
      _calculateRoute(userId, currentPosition, userPosition, useAStar);
    });
  }

  /// Request routes for all users - dengan current position dan locations yang tersedia
  void requestAllRoutes(LatLng currentPosition, bool useAStar, Map<String, LatLng> userLocations) {
    userLocations.forEach((userId, userPosition) {
      _routeDebouncers[userId]?.cancel();
      _routeDebouncers[userId] = Timer(Duration(milliseconds: 200), () {
        _calculateRoute(userId, currentPosition, userPosition, useAStar);
      });
    });
  }

  /// Calculate route between two points
  Future<void> _calculateRoute(String userId, LatLng start, LatLng end, bool useAStar) async {
    final cacheKey = '${start.latitude.toStringAsFixed(4)}-${end.latitude.toStringAsFixed(4)}';

    // Check cache first
    if (_routeCache.containsKey(cacheKey)) {
      onRouteUpdate(userId, _routeCache[cacheKey]!, useAStar);
      return;
    }

    try {
      print('🔥 Calculating route for $userId from $start to $end (useAStar: $useAStar)');

      final route = await RoutingService.getOptimizedRoute(
        start,
        end,
        useAStar: useAStar,
      );

      if (route != null && route.isNotEmpty) {
        print('✅ Route calculated successfully for $userId: ${route.length} points');
        _routeCache[cacheKey] = route;
        onRouteUpdate(userId, route, useAStar);
      } else {
        print('❌ No route found for $userId');
      }
    } catch (e) {
      print('❌ Error calculating route for $userId: $e');
    }
  }

  /// Request immediate route calculation
  void requestRouteImmediately(String userId, LatLng currentPosition, LatLng userPosition, bool useAStar) {
    _routeDebouncers[userId]?.cancel();
    _calculateRoute(userId, currentPosition, userPosition, useAStar);
  }

  /// Refresh all connections
  void refreshConnections() {
    final user = auth.currentUser;
    if (user == null) return;

    // Trigger a refresh by re-listening
    _clearAllSubscriptions();
    _listenToConnectedUsers();
  }

  /// Clear all subscriptions
  void _clearAllSubscriptions() {
    _userLocationSubs.values.forEach((sub) => sub.cancel());
    _userLocationSubs.clear();
    _routeDebouncers.values.forEach((timer) => timer.cancel());
    _routeDebouncers.clear();
  }

  /// Clear route cache
  void clearCache() {
    _routeCache.clear();
  }

  /// Dispose all resources
  void dispose() {
    _clearAllSubscriptions();
    clearCache();
  }
}