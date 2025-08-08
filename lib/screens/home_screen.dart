import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart';
import 'dart:async';
import 'map_screen.dart';
import 'search_users_screen.dart';
import 'connections_screen.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _auth = FirebaseAuth.instance;
  final _database = FirebaseDatabase.instance.ref();
  final _firestore = FirebaseFirestore.instance;
  final _location = Location();

  Timer? _locationTimer;
  bool _isLocationEnabled = false;
  String _userName = '';

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _setUserOffline();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    await _getUserData();
    await _requestLocationPermission();
    await _setUserOnline();
  }

  Future<void> _getUserData() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        // Try to get data from Firestore first
        final userDoc = await _firestore.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          setState(() {
            _userName = userData['name'] ?? user.displayName ?? 'User';
          });
          return;
        }

        // Fallback to Realtime Database
        final snapshot = await _database.child('users').child(user.uid).once();
        if (snapshot.snapshot.exists) {
          final userData = snapshot.snapshot.value as Map<dynamic, dynamic>;
          setState(() {
            _userName = userData['name'] ?? user.displayName ?? 'User';
          });
        } else {
          setState(() {
            _userName = user.displayName ?? user.email?.split('@')[0] ?? 'User';
          });
        }
      } catch (e) {
        print('Error getting user data: $e');
        setState(() {
          _userName = user.displayName ?? user.email?.split('@')[0] ?? 'User';
        });
      }
    }
  }

  Future<void> _requestLocationPermission() async {
    try {
      // Check if location service is enabled
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('GPS harus diaktifkan untuk berbagi lokasi')),
          );
          return;
        }
      }

      // Check location permission using location package
      PermissionStatus permissionGranted = await _location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Izin lokasi diperlukan untuk berbagi lokasi')),
          );
          return;
        }
      }

      // Test get location once
      LocationData locationData = await _location.getLocation();
      print('Current location: ${locationData.latitude}, ${locationData.longitude}');

      setState(() {
        _isLocationEnabled = true;
      });

      // Update location immediately
      await _updateLocation(locationData.latitude!, locationData.longitude!);

      _startLocationTracking();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Berbagi lokasi diaktifkan!')),
      );

    } catch (e) {
      print('Error requesting location permission: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error mengakses lokasi: $e')),
      );
    }
  }

  void _startLocationTracking() {
    print('Starting location tracking...');
    _locationTimer = Timer.periodic(Duration(seconds: 10), (timer) async {
      try {
        print('Getting location update...');
        LocationData locationData = await _location.getLocation();
        print('Location data: lat=${locationData.latitude}, lng=${locationData.longitude}');

        if (locationData.latitude != null && locationData.longitude != null) {
          await _updateLocation(locationData.latitude!, locationData.longitude!);
          print('Location updated to Firebase');
        } else {
          print('Location data is null');
        }
      } catch (e) {
        print('Error getting location: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error mendapatkan lokasi: $e')),
        );
      }
    });

    // Also get location immediately when starting
    _getLocationNow();
  }

  Future<void> _getLocationNow() async {
    try {
      print('Getting immediate location...');
      LocationData locationData = await _location.getLocation();
      print('Immediate location: lat=${locationData.latitude}, lng=${locationData.longitude}');

      if (locationData.latitude != null && locationData.longitude != null) {
        await _updateLocation(locationData.latitude!, locationData.longitude!);
        print('Immediate location updated to Firebase');
      }
    } catch (e) {
      print('Error getting immediate location: $e');
    }
  }

  Future<void> _updateLocation(double lat, double lng) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        print('Updating location: lat=$lat, lng=$lng');
        print('User ID: ${user.uid}');

        final locationData = {
          'latitude': lat,
          'longitude': lng,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'userId': user.uid,
        };

        // Update in Realtime Database (primary for locations due to real-time nature)
        await _database.child('locations').child(user.uid).set(locationData);
        print('Location successfully updated to Realtime Database');

        // Also update in Firestore for consistency
        try {
          await _firestore.collection('locations').doc(user.uid).set({
            'latitude': lat,
            'longitude': lng,
            'timestamp': FieldValue.serverTimestamp(),
            'userId': user.uid,
          });
          print('Location also updated to Firestore');
        } catch (firestoreError) {
          print('Warning: Failed to update location in Firestore: $firestoreError');
          // Continue anyway since Realtime Database is primary for locations
        }

        // Verify the data was written to Realtime Database
        final snapshot = await _database.child('locations').child(user.uid).once();
        if (snapshot.snapshot.exists) {
          print('Verified location data in Realtime Database: ${snapshot.snapshot.value}');
        } else {
          print('WARNING: Location data not found in Realtime Database after writing');
        }
      } else {
        print('ERROR: No authenticated user found');
      }
    } catch (e) {
      print('Error updating location: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error menyimpan lokasi: $e')),
      );
    }
  }

  Future<void> _setUserOnline() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        // Update in Firestore (primary for user status)
        await _firestore.collection('users').doc(user.uid).update({
          'isOnline': true,
          'lastSeen': FieldValue.serverTimestamp(),
        });
        print('User status updated to online in Firestore');

        // Also update in Realtime Database for compatibility
        await _database.child('users').child(user.uid).update({
          'isOnline': true,
          'lastSeen': DateTime.now().millisecondsSinceEpoch,
        });
        print('User status updated to online in Realtime Database');
      } catch (e) {
        print('Error setting user online: $e');
      }
    }
  }

  Future<void> _setUserOffline() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        // Update in Firestore (primary for user status)
        await _firestore.collection('users').doc(user.uid).update({
          'isOnline': false,
          'lastSeen': FieldValue.serverTimestamp(),
        });
        print('User status updated to offline in Firestore');

        // Also update in Realtime Database for compatibility
        await _database.child('users').child(user.uid).update({
          'isOnline': false,
          'lastSeen': DateTime.now().millisecondsSinceEpoch,
        });
        print('User status updated to offline in Realtime Database');
      } catch (e) {
        print('Error setting user offline: $e');
      }
    }
  }

  void _testLocationNow() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Testing lokasi...')),
      );

      LocationData locationData = await _location.getLocation();
      print('Test location result: ${locationData.latitude}, ${locationData.longitude}');

      if (locationData.latitude != null && locationData.longitude != null) {
        await _updateLocation(locationData.latitude!, locationData.longitude!);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✅ Lokasi berhasil: ${locationData.latitude?.toStringAsFixed(6)}, ${locationData.longitude?.toStringAsFixed(6)}'
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Gagal mendapatkan lokasi'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Test location error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showFirebaseData() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ User tidak login')),
        );
        return;
      }

      List<String> dataInfo = [];

      // Current user info
      dataInfo.add('=== USER SAYA ===');
      dataInfo.add('UID: ${currentUser.uid}');
      dataInfo.add('Email: ${currentUser.email}');
      dataInfo.add('Display Name: ${currentUser.displayName ?? "None"}');

      // Firestore users data
      dataInfo.add('\n=== FIRESTORE USERS ===');
      try {
        final firestoreUsersSnapshot = await _firestore.collection('users').get();
        dataInfo.add('Total Firestore users: ${firestoreUsersSnapshot.docs.length}');

        for (var doc in firestoreUsersSnapshot.docs) {
          final user = doc.data();
          dataInfo.add('- ${user['name']} (${user['email']}) - ${user['isOnline'] == true ? 'Online' : 'Offline'}');
        }
      } catch (e) {
        dataInfo.add('Error loading Firestore users: $e');
      }

      // Realtime Database users data
      dataInfo.add('\n=== REALTIME DB USERS ===');
      try {
        final rtdbUsersSnapshot = await _database.child('users').once();
        if (rtdbUsersSnapshot.snapshot.exists) {
          final usersData = Map<String, dynamic>.from(rtdbUsersSnapshot.snapshot.value as Map);
          dataInfo.add('Total RTDB users: ${usersData.length}');

          usersData.forEach((userId, userData) {
            final user = Map<String, dynamic>.from(userData as Map);
            dataInfo.add('- ${user['name']} (${user['email']}) - ${user['isOnline'] == true ? 'Online' : 'Offline'}');
          });
        } else {
          dataInfo.add('No users in Realtime Database');
        }
      } catch (e) {
        dataInfo.add('Error loading RTDB users: $e');
      }

      // Locations data (Realtime Database)
      dataInfo.add('\n=== LOKASI AKTIF (RTDB) ===');
      try {
        final locationsSnapshot = await _database.child('locations').once();
        if (locationsSnapshot.snapshot.exists) {
          final locationsData = Map<String, dynamic>.from(locationsSnapshot.snapshot.value as Map);
          dataInfo.add('Total locations: ${locationsData.length}');

          for (String userId in locationsData.keys) {
            final location = Map<String, dynamic>.from(locationsData[userId] as Map);

            // Get user name
            String userName = 'Unknown';
            try {
              final userDoc = await _firestore.collection('users').doc(userId).get();
              if (userDoc.exists) {
                userName = userDoc.data()!['name'] ?? 'Unknown';
              }
            } catch (e) {
              // Try Realtime Database
              final userSnapshot = await _database.child('users').child(userId).once();
              if (userSnapshot.snapshot.exists) {
                final userData = userSnapshot.snapshot.value as Map;
                userName = userData['name'] ?? 'Unknown';
              }
            }

            dataInfo.add('- $userName: ${location['latitude']?.toStringAsFixed(6)}, ${location['longitude']?.toStringAsFixed(6)}');
          }
        } else {
          dataInfo.add('Tidak ada lokasi aktif');
        }
      } catch (e) {
        dataInfo.add('Error loading locations: $e');
      }

      // Show dialog
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text('Data Firebase'),
            content: SingleChildScrollView(
              child: Container(
                width: double.maxFinite,
                child: Text(
                  dataInfo.join('\n'),
                  style: TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Tutup'),
              ),
            ],
          );
        },
      );

    } catch (e) {
      print('Error showing firebase data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _toggleLocationSharing() async {
    if (!_isLocationEnabled) {
      // Turning ON location sharing
      await _requestLocationPermission();
    } else {
      // Turning OFF location sharing
      setState(() {
        _isLocationEnabled = false;
      });
      _locationTimer?.cancel();

      // Remove location data from both databases when turned off
      final user = _auth.currentUser;
      if (user != null) {
        try {
          // Remove from Realtime Database
          await _database.child('locations').child(user.uid).remove();
          print('Location data removed from Realtime Database');

          // Remove from Firestore
          await _firestore.collection('locations').doc(user.uid).delete();
          print('Location data removed from Firestore');
        } catch (e) {
          print('Error removing location data: $e');
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Berbagi lokasi dimatikan')),
      );
    }
  }

  void _logout() async {
    await _setUserOffline();
    _locationTimer?.cancel();

    // Remove location data when logging out
    final user = _auth.currentUser;
    if (user != null) {
      try {
        await _database.child('locations').child(user.uid).remove();
        await _firestore.collection('locations').doc(user.uid).delete();
      } catch (e) {
        print('Error removing location data on logout: $e');
      }
    }

    await _auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ShareLoc - Hello $_userName'),
        backgroundColor: Colors.blue,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue, Colors.blue.shade50],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Location Status Card
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        Icon(
                          _isLocationEnabled ? Icons.location_on : Icons.location_off,
                          size: 48,
                          color: _isLocationEnabled ? Colors.green : Colors.red,
                        ),
                        SizedBox(height: 12),
                        Text(
                          _isLocationEnabled ? 'Berbagi Lokasi Aktif' : 'Berbagi Lokasi Nonaktif',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 8),
                        Text(
                          _isLocationEnabled
                              ? 'Lokasi Anda dibagikan setiap 10 detik'
                              : 'Aktifkan untuk berbagi lokasi dengan teman',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _toggleLocationSharing,
                          icon: Icon(_isLocationEnabled ? Icons.location_off : Icons.location_on),
                          label: Text(_isLocationEnabled ? 'Matikan Berbagi' : 'Aktifkan Berbagi'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isLocationEnabled ? Colors.red : Colors.green,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 20),

                // Main Actions
                Expanded(
                  child: Column(
                    children: [
                      _buildActionCard(
                        context,
                        icon: Icons.map,
                        title: 'Lihat Peta',
                        subtitle: 'Lihat lokasi teman di peta',
                        color: Colors.blue,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => MapScreen()),
                          );
                        },
                      ),

                      SizedBox(height: 12),

                      _buildActionCard(
                        context,
                        icon: Icons.search,
                        title: 'Cari Pengguna',
                        subtitle: 'Temukan dan hubungkan dengan pengguna lain',
                        color: Colors.orange,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => SearchUsersScreen()),
                          );
                        },
                      ),

                      SizedBox(height: 12),

                      _buildActionCard(
                        context,
                        icon: Icons.people,
                        title: 'Koneksi Saya',
                        subtitle: 'Kelola permintaan dan koneksi',
                        color: Colors.purple,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => ConnectionsScreen()),
                          );
                        },
                      ),

                      Spacer(),

                      // Debug section
                      Card(
                        color: Colors.grey[100],
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.bug_report, size: 16, color: Colors.grey[600]),
                                  SizedBox(width: 8),
                                  Text(
                                    'Debug Tools:',
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _testLocationNow,
                                      icon: Icon(Icons.gps_fixed, size: 16),
                                      label: Text('Test Lokasi'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.orange,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _showFirebaseData,
                                      icon: Icon(Icons.storage, size: 16),
                                      label: Text('Lihat Data'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.teal,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String subtitle,
        required Color color,
        required VoidCallback onTap,
      }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: color,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.grey[400],
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}