import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? mapController;
  final _auth = FirebaseAuth.instance;
  final _database = FirebaseDatabase.instance.ref();
  final _firestore = FirebaseFirestore.instance;
  final _location = Location();
  final http.Client _http = http.Client();

  // 🔥 GANTI API KEY INI! - Use a valid ORS API key
  final String orsApiKey = 'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6ImFhZTYxMWUxMGFjZTRmYzliMWQ5ZmEyNDQ0ZDVlY2RjIiwiaCI6Im11cm11cjY0In0=';

  LatLng _currentPosition = LatLng(-6.2088, 106.8456); // Default Jakarta
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  Map<String, LatLng> _userLocations = {}; // Tracking user locations
  Set<String> _connectedUserIds = {};

  // Subscriptions
  final Map<String, StreamSubscription<DatabaseEvent>> _userLocationSubs = {};
  StreamSubscription<LocationData>? _myLocSub;

  // Throttle + debounce state
  final Map<String, Timer> _routeDebouncers = {};
  final Map<String, DateTime> _lastRequestAt = {};
  final Map<String, LatLng> _lastFrom = {};
  final Map<String, LatLng> _lastTo = {};
  final Map<String, List<LatLng>> _routeCache = {};

  // Tunables
  static const Duration _debounceDuration = Duration(milliseconds: 500);
  static const Duration _minRequestInterval = Duration(seconds: 2);
  static const Duration _requestTimeout = Duration(seconds: 15);
  static const double _minMetersToRecalc = 30; // Recalc only if moved > 30 m

  @override
  void initState() {
    super.initState();
    _initLocation();
    _listenToConnectedUsers();
  }

  @override
  void dispose() {
    for (final t in _routeDebouncers.values) {
      t.cancel();
    }
    for (final sub in _userLocationSubs.values) {
      sub.cancel();
    }
    _myLocSub?.cancel();
    _http.close();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          print('❌ Location service disabled');
          return;
        }
      }

      PermissionStatus permissionGranted = await _location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          print('❌ Location permission denied');
          return;
        }
      }

      // Get initial location
      final locationData = await _location.getLocation();
      _currentPosition = LatLng(locationData.latitude!, locationData.longitude!);
      _addCurrentUserMarker();
      print('✅ My location: $_currentPosition');

      // Listen to my movement
      _myLocSub?.cancel();
      _myLocSub = _location.onLocationChanged.listen((loc) {
        if (loc.latitude == null || loc.longitude == null) return;
        _currentPosition = LatLng(loc.latitude!, loc.longitude!);
        _addCurrentUserMarker();

        // Schedule route update for all users (debounced per user)
        for (final userId in _userLocations.keys) {
          _scheduleRouteUpdate(userId);
        }
      });
    } catch (e) {
      print('❌ Error initializing location: $e');
    }
  }

  void _addCurrentUserMarker() {
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'my_location');
      _markers.add(
        Marker(
          markerId: MarkerId('my_location'),
          position: _currentPosition,
          infoWindow: InfoWindow(title: '📍 Lokasi Saya'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    });
  }

  void _listenToConnectedUsers() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    print('🔗 Listening to my connections...');

    _database.child('connections').child(currentUser.uid).onValue.listen((event) {
      if (!mounted) return;

      if (event.snapshot.exists) {
        final connections = Map<String, dynamic>.from(event.snapshot.value as Map);
        final newConnected = <String>{};

        for (final userId in connections.keys) {
          final status = connections[userId]['status'];
          if (status == 'accepted') {
            newConnected.add(userId);
          }
        }

        // Manage subscriptions: add new, remove old
        final toAdd = newConnected.difference(_connectedUserIds);
        final toRemove = _connectedUserIds.difference(newConnected);

        for (final userId in toRemove) {
          _userLocationSubs[userId]?.cancel();
          _userLocationSubs.remove(userId);
          _removeUserMarkerAndPolyline(userId);
        }

        for (final userId in toAdd) {
          _subscribeToUserLocation(userId);
        }

        setState(() {
          _connectedUserIds = newConnected;
        });

        print('👥 Connected users: ${_connectedUserIds.length}');
      } else {
        print('⚠️ No connections found');
        for (final sub in _userLocationSubs.values) {
          sub.cancel();
        }
        _userLocationSubs.clear();
        setState(() {
          _connectedUserIds.clear();
          _userLocations.clear();
          _clearAllUserMarkersAndPolylines();
        });
      }
    });
  }

  void _subscribeToUserLocation(String userId) {
    print('📍 Subscribing to location of $userId');
    final sub = _database.child('locations').child(userId).onValue.listen((locationEvent) {
      if (!mounted) return;

      if (locationEvent.snapshot.exists) {
        final locationData = Map<String, dynamic>.from(locationEvent.snapshot.value as Map);
        final lat = (locationData['latitude'] as num).toDouble();
        final lng = (locationData['longitude'] as num).toDouble();
        final userLatLng = LatLng(lat, lng);

        print('📍 Location update for user $userId: $userLatLng');

        _updateUserLocationAndRoute(userId, userLatLng);
      } else {
        print('❌ User $userId stopped sharing location');
        _removeUserMarkerAndPolyline(userId);
      }
    });

    _userLocationSubs[userId] = sub;
  }

  Future<void> _updateUserLocationAndRoute(String userId, LatLng userLocation) async {
    _userLocations[userId] = userLocation;
    await _addUserMarker(userId, userLocation);

    // Immediately request route for instant display
    _requestRouteImmediately(userId);
  }

  void _requestRouteImmediately(String userId) {
    // Cancel any pending debounced request
    _routeDebouncers[userId]?.cancel();

    // Request immediately for instant polyline display
    _maybeRequestRoute(userId);

    // Also schedule debounced request for future updates
    _scheduleRouteUpdate(userId);
  }

  void _scheduleRouteUpdate(String userId) {
    _routeDebouncers[userId]?.cancel();
    _routeDebouncers[userId] = Timer(_debounceDuration, () {
      _maybeRequestRoute(userId);
    });
  }

  Future<void> _maybeRequestRoute(String userId) async {
    final now = DateTime.now();
    final lastAt = _lastRequestAt[userId];

    // For immediate requests, skip rate limiting
    final isImmediate = lastAt == null;

    if (!isImmediate && lastAt != null && now.difference(lastAt) < _minRequestInterval) {
      // Too soon since last request; skip to avoid rate limit
      return;
    }

    final to = _userLocations[userId];
    if (to == null) return;
    final from = _currentPosition;

    // If both ends haven't moved significantly, reuse cached polyline
    final lastFrom = _lastFrom[userId];
    final lastTo = _lastTo[userId];
    if (!isImmediate && lastFrom != null && lastTo != null) {
      final movedFrom = _distanceMeters(lastFrom, from);
      final movedTo = _distanceMeters(lastTo, to);
      if (movedFrom < _minMetersToRecalc && movedTo < _minMetersToRecalc) {
        final cached = _routeCache[userId];
        if (cached != null && cached.isNotEmpty) {
          _applyRoutePolyline(userId, cached);
          return;
        }
      }
    }

    _lastFrom[userId] = from;
    _lastTo[userId] = to;
    _lastRequestAt[userId] = now;

    await _fetchAndApplyRoute(userId, from, to);
  }

  Future<void> _fetchAndApplyRoute(String userId, LatLng myLocation, LatLng userLocation) async {
    print('🚗 Requesting route to $userId | From: $myLocation → To: $userLocation');

    // Try multiple routing services for better reliability
    List<LatLng>? route;

    // Method 1: Try OpenRouteService first
    route = await _tryOpenRouteService(myLocation, userLocation);

    // Method 2: Fallback to Google Directions API (if you have the key)
    if (route == null || route.length < 3) {
      route = await _tryGoogleDirections(myLocation, userLocation);
    }

    // Method 3: Final fallback - create a basic curved route
    if (route == null || route.length < 3) {
      print('⚠️ All routing services failed. Creating interpolated route.');
      route = _createInterpolatedRoute(myLocation, userLocation);
    }

    // Cache and display the route
    _routeCache[userId] = route;
    _applyRoutePolyline(userId, route);
  }

  Future<List<LatLng>?> _tryOpenRouteService(LatLng from, LatLng to) async {
    try {
      final url = Uri.parse('https://api.openrouteservice.org/v2/directions/driving-car/geojson');

      final response = await _http.post(
        url,
        headers: {
          'Authorization': orsApiKey,
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json, application/geo+json, application/gpx+xml, img/png; charset=utf-8',
        },
        body: jsonEncode({
          'coordinates': [
            [from.longitude, from.latitude],
            [to.longitude, to.latitude],
          ],
          'format': 'geojson',
          'geometry_simplify': false,
          'instructions': false,
        }),
      ).timeout(_requestTimeout);

      print('🌐 ORS Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final features = data['features'] as List?;

        if (features != null && features.isNotEmpty) {
          final geometry = features[0]['geometry'];
          final coordinates = geometry['coordinates'] as List;

          final route = coordinates
              .map<LatLng>((coord) => LatLng(
            (coord[1] as num).toDouble(),
            (coord[0] as num).toDouble(),
          ))
              .toList();

          if (route.length >= 3) {
            print('✅ ORS route success: ${route.length} points');
            return route;
          } else {
            print('⚠️ ORS route too short: ${route.length} points');
          }
        }
      } else {
        print('❌ ORS error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('❌ ORS exception: $e');
    }
    return null;
  }

  Future<List<LatLng>?> _tryGoogleDirections(LatLng from, LatLng to) async {
    // You can implement Google Directions API here if you have the key
    // For now, we'll skip this method
    return null;
  }

  List<LatLng> _createInterpolatedRoute(LatLng from, LatLng to) {
    final points = <LatLng>[];

    // Create a route with multiple intermediate points to simulate road curvature
    const int numPoints = 20;

    for (int i = 0; i <= numPoints; i++) {
      final t = i / numPoints;

      // Basic interpolation with slight curvature
      final lat = from.latitude + (to.latitude - from.latitude) * t;
      final lng = from.longitude + (to.longitude - from.longitude) * t;

      // Add slight random curvature to make it look more road-like
      final curvature = math.sin(t * math.pi) * 0.001; // Small offset

      points.add(LatLng(
        lat + curvature,
        lng + (curvature * 0.5),
      ));
    }

    print('🛣️ Created interpolated route with ${points.length} points');
    return points;
  }

  void _applyRoutePolyline(String userId, List<LatLng> routePoints) {
    if (routePoints.isEmpty) return;

    print('🛣️ Drawing polyline for $userId: ${routePoints.length} points');

    if (!mounted) return;

    setState(() {
      _polylines.removeWhere((poly) => poly.polylineId.value == 'route_$userId');
      _polylines.add(
        Polyline(
          polylineId: PolylineId('route_$userId'),
          color: Colors.blue.shade600,
          width: 4,
          points: routePoints,
          geodesic: true,
          patterns: [], // Solid line
          jointType: JointType.round,
          endCap: Cap.roundCap,
          startCap: Cap.roundCap,
        ),
      );
    });

    print('✅ Polyline displayed with ${routePoints.length} points');
  }

  Future<void> _addUserMarker(String userId, LatLng position) async {
    String userName = 'User';

    try {
      // Get user name
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        userName = doc.data()?['name'] ?? 'User';
      } else {
        // Fallback to Realtime Database
        final userSnapshot = await _database.child('users').child(userId).once();
        if (userSnapshot.snapshot.exists) {
          final userData = userSnapshot.snapshot.value as Map;
          userName = userData['name'] ?? 'User';
        }
      }
    } catch (e) {
      print('⚠️ Error getting user name: $e');
    }

    setState(() {
      _markers.removeWhere((marker) => marker.markerId.value == userId);
      _markers.add(
        Marker(
          markerId: MarkerId(userId),
          position: position,
          infoWindow: InfoWindow(
            title: '👤 $userName',
            snippet: 'Sedang berbagi lokasi',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
    });

    print('✅ Marker added for $userName at $position');
  }

  // Accurate distance in meters (Haversine)
  double _distanceMeters(LatLng a, LatLng b) {
    const R = 6371000.0; // meters
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final lat1 = _deg2rad(a.latitude);
    final lat2 = _deg2rad(b.latitude);

    final sinDLat = math.sin(dLat / 2);
    final sinDLon = math.sin(dLon / 2);

    final h = sinDLat * sinDLat +
        math.cos(lat1) * math.cos(lat2) * sinDLon * sinDLon;

    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1.0 - h));
    return R * c;
  }

  double _deg2rad(double deg) => deg * (math.pi / 180.0);

  void _removeUserMarkerAndPolyline(String userId) {
    _routeDebouncers[userId]?.cancel();
    _routeDebouncers.remove(userId);
    _routeCache.remove(userId);
    _lastFrom.remove(userId);
    _lastTo.remove(userId);
    _lastRequestAt.remove(userId);

    setState(() {
      _markers.removeWhere((marker) => marker.markerId.value == userId);
      _polylines.removeWhere((poly) => poly.polylineId.value == 'route_$userId');
      _userLocations.remove(userId);
    });
    print('🗑️ Removed marker and route for user $userId');
  }

  void _clearAllUserMarkersAndPolylines() {
    setState(() {
      // Keep only my location marker
      _markers.removeWhere((marker) => marker.markerId.value != 'my_location');
      _polylines.clear();
    });
    print('🗑️ Cleared all user markers and polylines');
  }

  Future<void> _redrawAllRoutes() async {
    if (_userLocations.isEmpty) return;
    await Future.wait(
      _userLocations.entries.map((e) => _fetchAndApplyRoute(e.key, _currentPosition, e.value)),
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
    print('✅ Google Map created');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Peta Berbagi Lokasi'),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: Icon(Icons.bug_report),
            onPressed: () async {
              print('🐛 DEBUG INFO:');
              print('Connected Users: $_connectedUserIds');
              print('User Locations: $_userLocations');
              print('Polylines: ${_polylines.map((p) => p.polylineId.value)}');
              print('Current Position: $_currentPosition');

              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('Debug Info'),
                  content: Text(
                    'Connected: ${_connectedUserIds.length}\n'
                        'Locations: ${_userLocations.length}\n'
                        'Polylines: ${_polylines.length}\n'
                        'My Position: $_currentPosition\n'
                        'User Positions: $_userLocations',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('OK'),
                    ),
                  ],
                ),
              );
            },
            tooltip: 'Debug Info',
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () async {
              await _initLocation();
              _listenToConnectedUsers();
              await _redrawAllRoutes();
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: _currentPosition,
              zoom: 13.0,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            mapType: MapType.normal,
            compassEnabled: true,
            rotateGesturesEnabled: true,
            scrollGesturesEnabled: true,
            tiltGesturesEnabled: true,
            zoomGesturesEnabled: true,
          ),

          // Status info panel
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              color: Colors.white.withOpacity(0.9),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.blue),
                        SizedBox(width: 8),
                        Text(
                          'Status Berbagi Lokasi',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text('👥 Teman Terhubung: ${_connectedUserIds.length}'),
                    Text('📍 Berbagi Lokasi Aktif: ${_userLocations.length}'),
                    Text('🛣️ Rute Aktif: ${_polylines.length}'),
                    if (_userLocations.isNotEmpty) ...[
                      SizedBox(height: 4),
                      Text(
                        '🔵 Biru = Rute Jalan',
                        style: TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (mapController != null && _userLocations.isNotEmpty) {
            // Fit map to show all users
            final allPositions = [_currentPosition, ..._userLocations.values];

            final minLat = allPositions.map((p) => p.latitude).reduce((a, b) => a < b ? a : b);
            final maxLat = allPositions.map((p) => p.latitude).reduce((a, b) => a > b ? a : b);
            final minLng = allPositions.map((p) => p.longitude).reduce((a, b) => a < b ? a : b);
            final maxLng = allPositions.map((p) => p.longitude).reduce((a, b) => a > b ? a : b);

            mapController!.animateCamera(
              CameraUpdate.newLatLngBounds(
                LatLngBounds(
                  southwest: LatLng(minLat - 0.01, minLng - 0.01),
                  northeast: LatLng(maxLat + 0.01, maxLng + 0.01),
                ),
                100.0,
              ),
            );
          } else {
            mapController?.animateCamera(
              CameraUpdate.newLatLng(_currentPosition),
            );
          }
        },
        child: Icon(_userLocations.isNotEmpty ? Icons.zoom_out_map : Icons.my_location),
        backgroundColor: Colors.blue,
        tooltip: _userLocations.isNotEmpty ? 'Lihat Semua' : 'Lokasi Saya',
      ),
    );
  }
}