import 'dart:async';
import 'dart:convert';

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

  LatLng _currentPosition = LatLng(-6.2088, 106.8456); // Default Jakarta
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  StreamSubscription? _locationsSubscription;

  final String orsApiKey = 'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6ImFhZTYxMWUxMGFjZTRmYzliMWQ5ZmEyNDQ0ZDVlY2RjIiwiaCI6Im11cm11cjY0In0='; // GANTI DENGAN API KEY ORS KAMU

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _listenToConnectedUsersLocations();
  }

  @override
  void dispose() {
    _locationsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationData locationData = await _location.getLocation();
      setState(() {
        _currentPosition = LatLng(locationData.latitude!, locationData.longitude!);
      });
      _addCurrentUserMarker();
    } catch (e) {
      print('Error getting current location: $e');
    }
  }

  void _addCurrentUserMarker() {
    setState(() {
      _markers.add(
        Marker(
          markerId: MarkerId('current_user'),
          position: _currentPosition,
          infoWindow: InfoWindow(title: 'Lokasi Saya'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    });
  }

  void _listenToConnectedUsersLocations() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    _database.child('connections').child(currentUser.uid).onValue.listen((event) {
      if (event.snapshot.exists) {
        final connections = Map<String, dynamic>.from(event.snapshot.value as Map);

        for (String userId in connections.keys) {
          if (connections[userId]['status'] == 'accepted') {
            _database.child('locations').child(userId).onValue.listen((locationEvent) {
              if (locationEvent.snapshot.exists) {
                _addUserMarker(userId, locationEvent.snapshot.value as Map<dynamic, dynamic>);
              }
            });
          }
        }
      }
    });
  }

  Future<void> _addUserMarker(String userId, Map<dynamic, dynamic> locationData) async {
    try {
      String userName = 'Unknown User';
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        userName = doc.data()?['name'] ?? 'Unknown User';
      }

      final lat = (locationData['latitude'] as num).toDouble();
      final lng = (locationData['longitude'] as num).toDouble();
      final userLatLng = LatLng(lat, lng);

      setState(() {
        _markers.removeWhere((marker) => marker.markerId.value == userId);
        _markers.add(
          Marker(
            markerId: MarkerId(userId),
            position: userLatLng,
            infoWindow: InfoWindow(title: userName),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
        );
      });

      await _drawPolylineFromCurrentToUser(_currentPosition, userLatLng, userId);
    } catch (e) {
      print('Error adding user marker: $e');
    }
  }

  Future<void> _drawPolylineFromCurrentToUser(LatLng start, LatLng end, String id) async {
    try {
      if (start.latitude == end.latitude && start.longitude == end.longitude) {
        print('Start and end are the same. Skipping polyline.');
        return;
      }

      print('Requesting ORS route from $start to $end');

      final response = await http.post(
        Uri.parse('https://api.openrouteservice.org/v2/directions/driving-car'),
        headers: {
          'Authorization': orsApiKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'coordinates': [
            [start.longitude, start.latitude],
            [end.longitude, end.latitude],
          ],
        }),
      );

      print('ORS status: ${response.statusCode}');
      print('ORS response: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final coordinates = data['features'][0]['geometry']['coordinates'] as List;

        final points = coordinates.map<LatLng>((coord) {
          return LatLng(coord[1], coord[0]); // ORS returns [lon, lat]
        }).toList();

        setState(() {
          _polylines.removeWhere((poly) => poly.polylineId.value == id);
          _polylines.add(
            Polyline(
              polylineId: PolylineId(id),
              color: Colors.blue,
              width: 5,
              points: points,
            ),
          );
        });
      } else {
        print('Failed to get directions from ORS: ${response.body}');
      }
    } catch (e) {
      print('Error fetching route from ORS: $e');
    }
  }

  // Fungsi ini buat TEST manual (contoh Jakarta → Bandung)
  Future<void> _drawTestPolyline() async {
    final LatLng start = LatLng(-6.2088, 106.8456); // Jakarta
    final LatLng end = LatLng(-6.9175, 107.6191);   // Bandung
    await _drawPolylineFromCurrentToUser(start, end, 'test_polyline');
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Peta Lokasi'),
        backgroundColor: Colors.blue,
      ),
      body: GoogleMap(
        onMapCreated: _onMapCreated,
        initialCameraPosition: CameraPosition(
          target: _currentPosition,
          zoom: 14.0,
        ),
        markers: _markers,
        polylines: _polylines,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          mapController?.animateCamera(
            CameraUpdate.newLatLng(_currentPosition),
          );
        },
        child: Icon(Icons.my_location),
        backgroundColor: Colors.blue,
      ),
    );
  }
}
