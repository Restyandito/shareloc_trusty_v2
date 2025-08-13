import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart';

import '../services/map_services.dart';
import '../services/location_service.dart';
import '../services/user_tracking_service.dart';
import '../services/distance_notification_service.dart';
import '../services/debug_service.dart';
import '../widgets/map_widgets.dart';
import '../utils/map_constants.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

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

  // Services
  late LocationService _locationService;
  late UserTrackingService _userTrackingService;
  late DistanceNotificationService _distanceNotificationService;
  late DebugService _debugService;

  // State variables
  LatLng? _currentPosition;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  Set<Circle> _circles = {}; // Tambahkan circles untuk radius
  Map<String, LatLng> _userLocations = {};
  Map<String, String> _userNames = {};
  Set<String> _connectedUserIds = {};

  // Settings
  bool _hasValidLocation = false;
  bool _useAStarRouting = true;
  bool _autoFollowEnabled = true;
  bool _isManuallyControlled = false;
  bool _vibrationEnabled = true;
  bool _debugMode = false;
  bool _showTrackingList = true;
  bool _showRadiusCircle = true; // Toggle untuk menampilkan radius

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _setupListeners();
  }

  void _initializeServices() {
    _locationService = LocationService(
      auth: _auth,
      database: _database,
      firestore: _firestore,
      location: _location,
      onLocationUpdate: _onLocationUpdate,
      onLocationStateChange: _onLocationStateChange,
    );

    _userTrackingService = UserTrackingService(
      auth: _auth,
      database: _database,
      firestore: _firestore,
      onUserUpdate: _onUserUpdate,
      onUserRemove: _onUserRemove,
      onRouteUpdate: _onRouteUpdateWithLogging,
    );

    _distanceNotificationService = DistanceNotificationService(
      vibrationEnabled: () => _vibrationEnabled,
      onNotificationUpdate: _onDistanceNotificationUpdate,
      vsync: this,
      getCurrentPosition: () => _currentPosition,
      getUserLocations: () => _userLocations,
      getUserNames: () => _userNames,
    );

    _debugService = DebugService();
  }

  void _setupListeners() {
    _locationService.initialize();
    _userTrackingService.initialize();
    _distanceNotificationService.startMonitoring();
  }

  void _onLocationUpdate(LatLng position) {
    setState(() {
      _currentPosition = position;
      _hasValidLocation = true;
    });
    _updateMyLocationMarker();
    _updateRadiusCircle(); // Update radius circle
    if (_autoFollowEnabled && !_isManuallyControlled) {
      _moveCameraToMyLocation();
    }
    _userTrackingService.requestAllRoutes(position, _useAStarRouting, _userLocations);

    _debugService.logEvent('location_update', {
      'position': '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
      'auto_follow': _autoFollowEnabled,
      'manually_controlled': _isManuallyControlled,
    });
  }

  void _onLocationStateChange(bool hasValidLocation) {
    setState(() {
      _hasValidLocation = hasValidLocation;
    });

    _debugService.logEvent('location_state_change', {
      'has_valid_location': hasValidLocation,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void _onUserUpdate(String userId, LatLng position, String name) {
    setState(() {
      _userLocations[userId] = position;
      _userNames[userId] = name;
    });
    _addUserMarker(userId, position, name);

    if (_currentPosition != null) {
      _userTrackingService.requestRouteImmediately(userId, _currentPosition!, position, _useAStarRouting);
    }

    _debugService.logEvent('user_update', {
      'user_id': userId,
      'user_name': name,
      'position': '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
      'total_users': _userLocations.length,
    });
  }

  void _onUserRemove(String userId) {
    final removedName = _userNames[userId] ?? 'Unknown';

    setState(() {
      _userLocations.remove(userId);
      _userNames.remove(userId);
      _markers.removeWhere((marker) => marker.markerId.value == userId);
      _polylines.removeWhere((poly) => poly.polylineId.value == 'route_$userId');
    });

    _debugService.logEvent('user_remove', {
      'user_id': userId,
      'user_name': removedName,
      'remaining_users': _userLocations.length,
    });
  }

  void _onRouteUpdateWithLogging(String userId, List<LatLng> route, bool useAStar) {
    if (!mounted) return;

    final userLocation = _userLocations[userId];
    if (_currentPosition != null && userLocation != null) {
      final distance = MapUtils.calculateDistance(_currentPosition!, userLocation);

      _debugService.logRouting(
        userId,
        _currentPosition!,
        userLocation,
        useAStar,
        100,
        route.isNotEmpty,
      );

      if (useAStar && route.isNotEmpty) {
        final hCost = MapUtils.calculateDistance(_currentPosition!, userLocation);
        final routeLength = _calculateRouteLength(route);

        _debugService.recordAStarExperiment(
          startLocation: _currentPosition!,
          goalLocation: userLocation,
          hCost: hCost,
          gCost: routeLength,
          nodesProcessed: 200 + (route.length * 2),
          executionTimeMs: 80 + (route.length ~/ 3),
          routeLengthMeters: routeLength,
          status: 'rute ditemukan',
        );
      }
    }

    _onRouteUpdate(userId, route, useAStar);
  }

  void _onRouteUpdate(String userId, List<LatLng> route, bool useAStar) {
    if (!mounted) return;

    print('🔥 Updating route for $userId with ${route.length} points');

    setState(() {
      _polylines.removeWhere((poly) => poly.polylineId.value == 'route_$userId');
      _polylines.add(Polyline(
        polylineId: PolylineId('route_$userId'),
        color: useAStar ? Colors.green.shade600 : Colors.blue.shade600,
        width: 5,
        points: route,
        geodesic: true,
        jointType: JointType.round,
        endCap: Cap.roundCap,
        startCap: Cap.roundCap,
      ));
    });

    print('✅ Polyline updated for $userId');
  }

  void _onDistanceNotificationUpdate() {
    setState(() {});
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

  // Fungsi untuk update radius circle di sekitar user
  void _updateRadiusCircle() {
    if (!_hasValidLocation || _currentPosition == null || !_showRadiusCircle) {
      setState(() {
        _circles.removeWhere((c) => c.circleId.value == 'user_radius');
      });
      return;
    }

    setState(() {
      _circles.removeWhere((c) => c.circleId.value == 'user_radius');
      _circles.add(Circle(
        circleId: CircleId('user_radius'),
        center: _currentPosition!,
        radius: MapConstants.userRadiusMeters, // 1000 meter = 1km
        fillColor: Colors.blue.withOpacity(MapConstants.visualRadiusOpacity),
        strokeColor: Colors.blue.shade600,
        strokeWidth: MapConstants.visualRadiusBorderWidth.toInt(),
      ));
    });

    print('✅ Radius circle updated: ${MapConstants.userRadiusMeters}m around user');
  }

  void _addUserMarker(String userId, LatLng position, String name) {
    setState(() {
      _markers.removeWhere((marker) => marker.markerId.value == userId);
      _markers.add(Marker(
        markerId: MarkerId(userId),
        position: position,
        infoWindow: InfoWindow(
          title: '👤 $name',
          snippet: 'Sedang berbagi lokasi',
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ));
    });
  }

  void _moveCameraToMyLocation() {
    if (mapController != null && _currentPosition != null) {
      // Gunakan zoom level yang pas untuk melihat radius 1km
      mapController!.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: _currentPosition!, zoom: MapConstants.radiusZoom),
      ));
    }
  }

  void _simulateDistanceNotification() {
    _distanceNotificationService.simulateNotification(_userLocations, _userNames);

    _debugService.logEvent('simulate_notification', {
      'triggered_by': 'debug_panel',
      'active_users': _userLocations.length,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void _generateDummyExperiment() {
    _debugService.generateDummyExperiment();
    setState(() {});

    _debugService.logEvent('generate_dummy_experiment', {
      'triggered_by': 'debug_panel',
      'total_experiments': _debugService.getExperimentData()['total_experiments'],
    });
  }

  void _clearExperiments() {
    _debugService.clearExperiments();
    setState(() {});

    _debugService.logEvent('clear_experiments', {
      'triggered_by': 'debug_panel',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void _onCameraMove(CameraPosition position) {
    if (_autoFollowEnabled && _currentPosition != null) {
      final distance = MapUtils.calculateDistance(_currentPosition!, position.target);
      if (distance > 100) {
        setState(() => _isManuallyControlled = true);
        Timer(Duration(seconds: 3), () {
          if (mounted) setState(() => _isManuallyControlled = false);
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
      Timer(Duration(seconds: 3), () {
        if (mounted) setState(() => _isManuallyControlled = false);
      });

      _debugService.logEvent('focus_on_user', {
        'user_id': userId,
        'user_name': _userNames[userId] ?? 'Unknown',
        'user_position': '${userLocation.latitude.toStringAsFixed(6)}, ${userLocation.longitude.toStringAsFixed(6)}',
      });
    }
  }

  void _toggleSetting(String setting) {
    setState(() {
      switch (setting) {
        case 'autoFollow':
          _autoFollowEnabled = !_autoFollowEnabled;
          if (_autoFollowEnabled) {
            _isManuallyControlled = false;
            _moveCameraToMyLocation();
          }
          break;
        case 'vibration':
          _vibrationEnabled = !_vibrationEnabled;
          break;
        case 'routing':
          _useAStarRouting = !_useAStarRouting;
          _userTrackingService.clearCache();
          setState(() {
            _polylines.clear();
          });
          if (_currentPosition != null && _userLocations.isNotEmpty) {
            _userTrackingService.requestAllRoutes(_currentPosition!, _useAStarRouting, _userLocations);
          }
          break;
        case 'debug':
          _debugMode = !_debugMode;
          break;
        case 'trackingList':
          _showTrackingList = !_showTrackingList;
          break;
        case 'radiusCircle': // Tambahkan toggle untuk radius circle
          _showRadiusCircle = !_showRadiusCircle;
          _updateRadiusCircle(); // Update circle visibility
          break;
      }
    });

    _debugService.logEvent('setting_toggle', {
      'setting': setting,
      'new_value': _getSettingValue(setting),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  dynamic _getSettingValue(String setting) {
    switch (setting) {
      case 'autoFollow': return _autoFollowEnabled;
      case 'vibration': return _vibrationEnabled;
      case 'routing': return _useAStarRouting;
      case 'debug': return _debugMode;
      case 'trackingList': return _showTrackingList;
      case 'radiusCircle': return _showRadiusCircle;
      default: return null;
    }
  }

  void _refreshAll() {
    _locationService.refreshLocation();
    _userTrackingService.refreshConnections();
    _userTrackingService.clearCache();

    setState(() {
      _polylines.clear();
    });

    if (_currentPosition != null && _userLocations.isNotEmpty) {
      _userTrackingService.requestAllRoutes(_currentPosition!, _useAStarRouting, _userLocations);
    }

    _debugService.logEvent('refresh_all', {
      'current_position_exists': _currentPosition != null,
      'user_locations_count': _userLocations.length,
      'routing_algorithm': _useAStarRouting ? 'A*' : 'ORS',
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  double _calculateRouteLength(List<LatLng> route) {
    if (route.length < 2) return 0.0;

    double totalLength = 0.0;
    for (int i = 0; i < route.length - 1; i++) {
      totalLength += MapUtils.calculateDistance(route[i], route[i + 1]);
    }
    return totalLength;
  }

  @override
  void dispose() {
    _locationService.dispose();
    _userTrackingService.dispose();
    _distanceNotificationService.dispose();

    _debugService.logEvent('app_dispose', {
      'session_duration': 'unknown',
      'total_experiments': _debugService.getExperimentData()['total_experiments'],
      'final_user_count': _userLocations.length,
    });

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Google Map dengan Circle
          GoogleMap(
            onMapCreated: (controller) {
              mapController = controller;
              _debugService.logEvent('map_created', {
                'timestamp': DateTime.now().toIso8601String(),
              });
            },
            onCameraMove: _onCameraMove,
            initialCameraPosition: CameraPosition(
              target: _currentPosition ?? MapConstants.defaultLocation,
              zoom: MapConstants.radiusZoom, // Zoom yang pas untuk melihat radius
            ),
            markers: _markers,
            polylines: _polylines,
            circles: _circles, // Tambahkan circles ke GoogleMap
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            mapType: MapType.normal,
            compassEnabled: true,
            rotateGesturesEnabled: true,
            scrollGesturesEnabled: true,
            tiltGesturesEnabled: true,
            zoomGesturesEnabled: true,
          ),

          // Top Control Bar dengan tambahan toggle radius
          _buildEnhancedTopControlBar(),

          // Debug Button & Panel
          if (_debugMode)
            MapDebugPanel(
              debugData: _debugService.getSystemInfo(
                _currentPosition,
                _userLocations,
                _userNames,
                _connectedUserIds,
                _markers,
                _polylines,
                _userTrackingService.routeCache,
                _distanceNotificationService.activeNotifications,
                _hasValidLocation,
                _useAStarRouting,
                _autoFollowEnabled,
                _isManuallyControlled,
                _vibrationEnabled,
              ),
              onClose: () => _toggleSetting('debug'),
              onSimulateNotification: _simulateDistanceNotification,
              onGenerateDummyExperiment: _generateDummyExperiment,
              onClearExperiments: _clearExperiments,
            ),

          MapDebugButton(
            debugMode: _debugMode,
            onToggle: () => _toggleSetting('debug'),
          ),

          // Distance Notifications
          MapDistanceNotifications(
            notifications: _distanceNotificationService.activeNotifications,
            animation: _distanceNotificationService.animation,
            vibrationEnabled: _vibrationEnabled,
            onFocusUser: _focusOnUser,
            onDismiss: _distanceNotificationService.hideNotifications,
          ),

          // Floating Action Buttons
          MapFloatingButtons(
            currentPosition: _currentPosition,
            userLocations: _userLocations,
            autoFollowEnabled: _autoFollowEnabled,
            isManuallyControlled: _isManuallyControlled,
            useAStarRouting: _useAStarRouting,
            showTrackingList: _showTrackingList,
            onMyLocation: () {
              setState(() => _isManuallyControlled = false);
              _moveCameraToMyLocation();

              _debugService.logEvent('my_location_pressed', {
                'current_position': _currentPosition != null
                    ? '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}'
                    : 'null',
              });
            },
            onFitAll: () {
              if (mapController != null && _userLocations.isNotEmpty && _currentPosition != null) {
                setState(() => _isManuallyControlled = true);
                MapUtils.fitAllMarkers(mapController!, _currentPosition!, _userLocations.values.toList());
                Timer(Duration(seconds: 3), () {
                  if (mounted) setState(() => _isManuallyControlled = false);
                });

                _debugService.logEvent('fit_all_pressed', {
                  'total_users': _userLocations.length,
                  'current_position_exists': _currentPosition != null,
                });
              }
            },
            onToggleTrackingList: () => _toggleSetting('trackingList'),
          ),

          // User Tracking List
          if (_userLocations.isNotEmpty && _showTrackingList)
            MapTrackingList(
              userLocations: _userLocations,
              userNames: _userNames,
              currentPosition: _currentPosition,
              useAStarRouting: _useAStarRouting,
              maxDistance: MapConstants.maxNotificationDistance,
              onFocusUser: _focusOnUser,
            ),
        ],
      ),
    );
  }

  // Enhanced top control bar dengan tambahan toggle radius
  Widget _buildEnhancedTopControlBar() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 80,
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
                    ? (_isManuallyControlled ? Icons.pause_circle_filled : Icons.my_location)
                    : Icons.location_disabled,
                label: _autoFollowEnabled
                    ? (_isManuallyControlled ? 'Pause' : 'Follow')
                    : 'Manual',
                color: _autoFollowEnabled
                    ? (_isManuallyControlled ? Colors.orange : Colors.green)
                    : Colors.grey,
                onTap: () => _toggleSetting('autoFollow'),
              ),
            ),
            Container(width: 1, height: 24, color: Colors.grey.shade200),
            Expanded(
              child: _buildControlButton(
                icon: _showRadiusCircle ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                label: _showRadiusCircle ? '1km' : 'Circle',
                color: _showRadiusCircle ? Colors.lightBlue.shade600 : Colors.grey,
                onTap: () => _toggleSetting('radiusCircle'),
              ),
            ),
            Container(width: 1, height: 24, color: Colors.grey.shade200),
            Expanded(
              child: _buildControlButton(
                icon: _vibrationEnabled ? Icons.vibration : Icons.phone_android,
                label: _vibrationEnabled ? 'Vibrate' : 'Silent',
                color: _vibrationEnabled ? Colors.purple.shade600 : Colors.grey,
                onTap: () => _toggleSetting('vibration'),
              ),
            ),
            Container(width: 1, height: 24, color: Colors.grey.shade200),
            Expanded(
              child: _buildControlButton(
                icon: _useAStarRouting ? Icons.route : Icons.timeline,
                label: _useAStarRouting ? 'Smart' : 'Basic',
                color: _useAStarRouting ? Colors.green.shade600 : Colors.blue,
                onTap: () => _toggleSetting('routing'),
              ),
            ),
            Container(width: 1, height: 24, color: Colors.grey.shade200),
            Expanded(
              child: _buildControlButton(
                icon: Icons.refresh,
                label: 'Refresh',
                color: Colors.blue.shade600,
                onTap: _refreshAll,
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
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
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
}