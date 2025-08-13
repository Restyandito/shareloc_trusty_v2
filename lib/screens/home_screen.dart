import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:location/location.dart';
import 'dart:async';

// Import screens dengan path yang benar
import 'map_screen.dart';         // Sekarang sudah ada di screens folder
import 'search_users_screen.dart';
import 'connections_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _database = FirebaseDatabase.instance.ref();
  final _firestore = FirebaseFirestore.instance;
  final _location = Location();

  Timer? _locationTimer;
  bool _isLocationEnabled = false;
  String _userName = '';
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeApp();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    if (_isLocationEnabled) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
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
          if (mounted) {
            setState(() {
              _userName = userData['name'] ?? user.displayName ?? 'User';
            });
          }
          return;
        }

        // Fallback to Realtime Database
        final snapshot = await _database.child('users').child(user.uid).once();
        if (snapshot.snapshot.exists) {
          final userData = snapshot.snapshot.value as Map<dynamic, dynamic>;
          if (mounted) {
            setState(() {
              _userName = userData['name'] ?? user.displayName ?? 'User';
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _userName = user.displayName ?? user.email?.split('@')[0] ?? 'User';
            });
          }
        }
      } catch (e) {
        print('Error getting user data: $e');
        if (mounted) {
          setState(() {
            _userName = user.displayName ?? user.email?.split('@')[0] ?? 'User';
          });
        }
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
          _showSnackBar('GPS harus diaktifkan untuk berbagi lokasi', Colors.orange);
          return;
        }
      }

      // Check location permission using location package
      PermissionStatus permissionGranted = await _location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          _showSnackBar('Izin lokasi diperlukan untuk berbagi lokasi', Colors.orange);
          return;
        }
      }

      // Test get location once
      LocationData locationData = await _location.getLocation();
      print('Current location: ${locationData.latitude}, ${locationData.longitude}');

      if (mounted) {
        setState(() {
          _isLocationEnabled = true;
        });
      }

      // Start pulse animation when location is enabled
      _pulseController.repeat(reverse: true);

      // Update location immediately
      await _updateLocation(locationData.latitude!, locationData.longitude!);

      _startLocationTracking();

      _showSnackBar('Berbagi lokasi diaktifkan!', Colors.green);

    } catch (e) {
      print('Error requesting location permission: $e');
      if (mounted) {
        _showSnackBar('Error mengakses lokasi: $e', Colors.red);
      }
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
        if (mounted) {
          _showSnackBar('Error mendapatkan lokasi: $e', Colors.red);
        }
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
      if (mounted) {
        _showSnackBar('Error menyimpan lokasi: $e', Colors.red);
      }
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

  void _toggleLocationSharing() async {
    if (!_isLocationEnabled) {
      // Turning ON location sharing
      await _requestLocationPermission();
    } else {
      // Turning OFF location sharing
      if (mounted) {
        setState(() {
          _isLocationEnabled = false;
        });
      }
      _pulseController.stop();
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

      _showSnackBar('Berbagi lokasi dimatikan', Colors.orange);
    }
  }

  void _logout() async {
    await _setUserOffline();
    _locationTimer?.cancel();
    _pulseController.stop();

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

  void _showSnackBar(String message, Color backgroundColor) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              backgroundColor == Colors.green ? Icons.check_circle : Icons.error,
              color: Colors.white,
            ),
            SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: CustomScrollView(
        slivers: [
          // Modern SliverAppBar with gradient - Fixed height
          SliverAppBar(
            expandedHeight: 140, // Reduced from 200 to 140
            floating: false,
            pinned: true,
            elevation: 0,
            backgroundColor: Colors.transparent,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.blue.shade600,
                      Colors.blue.shade700,
                      Colors.blue.shade800,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, 16, 24, 20), // Adjusted padding
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end, // Align to bottom
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Hi, $_userName! 👋',
                                    style: TextStyle(
                                      fontSize: 26, // Slightly smaller
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Selamat datang di Trusty',
                                    style: TextStyle(
                                      fontSize: 15, // Slightly smaller
                                      color: Colors.white.withOpacity(0.9),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: IconButton(
                                icon: Icon(Icons.logout_rounded, color: Colors.white),
                                onPressed: _logout,
                                tooltip: 'Logout',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Main Content
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(20), // Reduced from 24 to 20
              child: Column(
                children: [
                  // Location Status Card - Modern Design
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _isLocationEnabled
                            ? [Colors.green.shade400, Colors.green.shade600]
                            : [Colors.grey.shade400, Colors.grey.shade600],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: (_isLocationEnabled ? Colors.green : Colors.grey).withOpacity(0.3),
                          spreadRadius: 0,
                          blurRadius: 20,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        children: [
                          AnimatedBuilder(
                            animation: _pulseAnimation,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _isLocationEnabled ? _pulseAnimation.value : 1.0,
                                child: Container(
                                  padding: EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _isLocationEnabled ? Icons.location_on : Icons.location_off,
                                    size: 48,
                                    color: Colors.white,
                                  ),
                                ),
                              );
                            },
                          ),
                          SizedBox(height: 16),
                          Text(
                            _isLocationEnabled ? 'Berbagi Lokasi Aktif' : 'Berbagi Lokasi Dinonaktifkan',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 8),
                          Text(
                            _isLocationEnabled
                                ? 'Lokasi Anda dibagikan setiap 10 detik'
                                : 'Aktifkan untuk berbagi lokasi dengan teman',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.9),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 20),
                          Container(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _toggleLocationSharing,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: _isLocationEnabled ? Colors.green.shade600 : Colors.grey.shade600,
                                elevation: 0,
                                padding: EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _isLocationEnabled ? Icons.pause : Icons.play_arrow,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    _isLocationEnabled ? 'Jeda Berbagi' : 'Mulai Berbagi',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 20),

                  GridView.count(
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.1,
                    children: [
                      _buildMenuCard(
                        context,
                        icon: Icons.map_rounded,
                        title: 'Lihat Peta',
                        subtitle: 'Lihat lokasi teman',
                        gradient: [Colors.blue.shade400, Colors.blue.shade600],
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => MapScreen()),
                          );
                        },
                      ),
                      _buildMenuCard(
                        context,
                        icon: Icons.search_rounded,
                        title: 'Cari Pengguna',
                        subtitle: 'Terhubung Sekarang',
                        gradient: [Colors.orange.shade400, Colors.orange.shade600],
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => SearchUsersScreen()),
                          );
                        },
                      ),
                      _buildMenuCard(
                        context,
                        icon: Icons.people_rounded,
                        title: 'Koneksi Saya',
                        subtitle: 'Kelola koneksi',
                        gradient: [Colors.purple.shade400, Colors.purple.shade600],
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => ConnectionsScreen()),
                          );
                        },
                      ),
                      _buildMenuCard(
                        context,
                        icon: Icons.person_rounded,
                        title: 'Profil',
                        subtitle: 'Kelola profil Anda',
                        gradient: [Colors.teal.shade400, Colors.teal.shade600],
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => ProfileScreen()),
                          );
                        },
                      ),
                    ],
                  ),

                  SizedBox(height: 20), // Reduced from 24 to 20
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuCard(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String subtitle,
        required List<Color> gradient,
        required VoidCallback onTap,
      }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradient.first.withOpacity(0.3),
            spreadRadius: 0,
            blurRadius: 15,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 32,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}