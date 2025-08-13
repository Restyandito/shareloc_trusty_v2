import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart';

import 'dart:math' as math;

/// Service untuk mengelola lokasi pengguna
class LocationService {
  final FirebaseAuth auth;
  final DatabaseReference database;
  final FirebaseFirestore firestore;
  final Location location;
  final Function(LatLng) onLocationUpdate;
  final Function(bool) onLocationStateChange;

  LocationService({
    required this.auth,
    required this.database,
    required this.firestore,
    required this.location,
    required this.onLocationUpdate,
    required this.onLocationStateChange,
  });

  LatLng? _currentPosition;
  StreamSubscription<LocationData>? _locationSubscription;
  bool _hasValidLocation = false;

  LatLng? get currentPosition => _currentPosition;
  bool get hasValidLocation => _hasValidLocation;

  /// Initialize location service
  Future<void> initialize() async {
    await _requestLocationPermission();
    await _setUserOnline();
  }

  /// Request location permission dan mulai tracking
  Future<void> _requestLocationPermission() async {
    try {
      // Check if location service is enabled
      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) {
          print('❌ GPS service not enabled');
          return;
        }
      }

      // Check location permission
      PermissionStatus permissionGranted = await location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          print('❌ Location permission denied');
          return;
        }
      }

      // Get initial location
      final locationData = await location.getLocation();
      if (locationData.latitude != null && locationData.longitude != null) {
        _updateLocation(LatLng(locationData.latitude!, locationData.longitude!));
      }

      _startLocationTracking();
      print('✅ Location service initialized');

    } catch (e) {
      print('❌ Error requesting location permission: $e');
    }
  }

  /// Start continuous location tracking
  void _startLocationTracking() {
    _locationSubscription = location.onLocationChanged.listen((loc) {
      if (loc.latitude == null || loc.longitude == null) return;

      final newPosition = LatLng(loc.latitude!, loc.longitude!);

      // Only update if position changed significantly (10+ meters)
      if (_currentPosition != null &&
          _calculateDistance(_currentPosition!, newPosition) < 10) {
        return;
      }

      _updateLocation(newPosition);
    });
  }

  /// Update location dan share ke Firebase
  void _updateLocation(LatLng position) {
    _currentPosition = position;

    if (!_hasValidLocation) {
      _hasValidLocation = true;
      onLocationStateChange(true);
    }

    onLocationUpdate(position);
    _shareLocationToFirebase(position);
  }

  /// Share location ke Firebase
  Future<void> _shareLocationToFirebase(LatLng position) async {
    final user = auth.currentUser;
    if (user == null) return;

    try {
      final locationData = {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'userId': user.uid,
      };

      // Update in Realtime Database (primary for locations)
      await database.child('locations').child(user.uid).set(locationData);

      // Also update in Firestore for consistency
      try {
        await firestore.collection('locations').doc(user.uid).set({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': FieldValue.serverTimestamp(),
          'userId': user.uid,
        });
      } catch (firestoreError) {
        print('⚠️ Firestore location update failed: $firestoreError');
      }

    } catch (e) {
      print('❌ Error sharing location: $e');
    }
  }

  /// Set user status online
  Future<void> _setUserOnline() async {
    final user = auth.currentUser;
    if (user == null) return;

    try {
      // Update in Firestore
      await firestore.collection('users').doc(user.uid).update({
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
      });

      // Update in Realtime Database
      await database.child('users').child(user.uid).update({
        'isOnline': true,
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
      });

      print('✅ User status set to online');
    } catch (e) {
      print('❌ Error setting user online: $e');
    }
  }

  /// Set user status offline
  Future<void> _setUserOffline() async {
    final user = auth.currentUser;
    if (user == null) return;

    try {
      // Update in Firestore
      await firestore.collection('users').doc(user.uid).update({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      });

      // Update in Realtime Database
      await database.child('users').child(user.uid).update({
        'isOnline': false,
        'lastSeen': DateTime.now().millisecondsSinceEpoch,
      });

      // Remove location data
      await database.child('locations').child(user.uid).remove();
      await firestore.collection('locations').doc(user.uid).delete();

      print('✅ User status set to offline');
    } catch (e) {
      print('❌ Error setting user offline: $e');
    }
  }

  /// Refresh location manually
  Future<void> refreshLocation() async {
    try {
      final locationData = await location.getLocation();
      if (locationData.latitude != null && locationData.longitude != null) {
        _updateLocation(LatLng(locationData.latitude!, locationData.longitude!));
      }
    } catch (e) {
      print('❌ Error refreshing location: $e');
    }
  }

  /// Calculate distance between two points
  double _calculateDistance(LatLng a, LatLng b) {
    const R = 6371000.0;
    final dLat = (b.latitude - a.latitude) * (3.14159 / 180);
    final dLon = (b.longitude - a.longitude) * (3.14159 / 180);
    final lat1 = a.latitude * (3.14159 / 180);
    final lat2 = b.latitude * (3.14159 / 180);

    final sinDLat = (dLat / 2).sin();
    final sinDLon = (dLon / 2).sin();
    final h = sinDLat * sinDLat + lat1.cos() * lat2.cos() * sinDLon * sinDLon;
    return R * 2 * (h.sqrt().atan2((1.0 - h).sqrt()));
  }

  /// Dispose resources
  void dispose() {
    _locationSubscription?.cancel();
    _setUserOffline();
  }
}

extension MathExtensions on double {
  double sin() => math.sin(this);
  double cos() => math.cos(this);
  double sqrt() => math.sqrt(this);
  double atan2(double other) => math.atan2(this, other);
}

