import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ConnectionsScreen extends StatefulWidget {
  @override
  _ConnectionsScreenState createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> with TickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _database = FirebaseDatabase.instance.ref();
  final _firestore = FirebaseFirestore.instance;

  TabController? _tabController;
  List<Map<String, dynamic>> _connectionRequests = [];
  List<Map<String, dynamic>> _connections = [];
  bool _isLoadingConnections = false;
  bool _isLoadingRequests = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadConnectionRequests();
    _loadConnections();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _loadConnectionRequests() {
    final currentUser = _auth.currentUser!;
    _database
        .child('connection_requests')
        .child(currentUser.uid)
        .onValue
        .listen((event) async {
      if (!mounted) return;

      setState(() {
        _isLoadingRequests = true;
      });

      if (event.snapshot.exists) {
        final requests = <Map<String, dynamic>>[];
        final requestsData = Map<String, dynamic>.from(
            event.snapshot.value as Map);

        print('🔗 Loading ${requestsData.keys.length} connection requests...');

        for (String fromUserId in requestsData.keys) {
          final requestData = Map<String, dynamic>.from(requestsData[fromUserId] as Map);

          if (requestData['status'] == 'pending') {
            print('📝 Getting user data for request from $fromUserId...');

            // Get comprehensive user info using the same method as connections
            final userData = await _getUserData(fromUserId);
            if (userData != null) {
              final request = {
                'fromUserId': fromUserId,
                'fromUserName': userData['name'],
                'fromUserEmail': userData['email'],
                'isOnline': userData['isOnline'],
                'lastSeen': userData['lastSeen'],
                'timestamp': requestData['timestamp'],
                'status': requestData['status'],
              };
              requests.add(request);
              print('✅ Added request from: ${userData['name']} (${userData['email']})');
            } else {
              // Fallback to stored data if user data not found
              final request = {
                'fromUserId': fromUserId,
                'fromUserName': requestData['fromUserName'] ?? 'Pengguna',
                'fromUserEmail': 'Email tidak tersedia',
                'isOnline': false,
                'lastSeen': null,
                'timestamp': requestData['timestamp'],
                'status': requestData['status'],
              };
              requests.add(request);
              print('⚠️ Used fallback data for $fromUserId');
            }
          }
        }

        print('✅ Loaded ${requests.length} connection requests');

        if (mounted) {
          setState(() {
            _connectionRequests = requests;
            _isLoadingRequests = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _connectionRequests = [];
            _isLoadingRequests = false;
          });
        }
      }
    });
  }

  void _loadConnections() {
    final currentUser = _auth.currentUser!;
    _database
        .child('connections')
        .child(currentUser.uid)
        .onValue
        .listen((event) async {
      if (!mounted) return;

      setState(() {
        _isLoadingConnections = true;
      });

      if (event.snapshot.exists) {
        final connections = <Map<String, dynamic>>[];
        final connectionsData = Map<String, dynamic>.from(
            event.snapshot.value as Map);

        print('🔗 Loading ${connectionsData.keys.length} connections...');

        for (String userId in connectionsData.keys) {
          final connectionData = Map<String, dynamic>.from(
              connectionsData[userId] as Map);

          if (connectionData['status'] == 'accepted') {
            print('📝 Getting user data for $userId...');

            // Get comprehensive user info
            final userData = await _getUserData(userId);
            if (userData != null) {
              userData['userId'] = userId;
              userData['connectionTimestamp'] = connectionData['timestamp'];
              connections.add(userData);
              print('✅ Added connection: ${userData['name']} (${userData['email']})');
            } else {
              print('❌ Failed to get user data for $userId');
            }
          }
        }

        print('✅ Loaded ${connections.length} connections');

        if (mounted) {
          setState(() {
            _connections = connections;
            _isLoadingConnections = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _connections = [];
            _isLoadingConnections = false;
          });
        }
      }
    });
  }

  Future<Map<String, dynamic>?> _getUserData(String userId) async {
    try {
      print('🔍 Searching user data for $userId...');

      // Method 1: Try Firestore first (most up-to-date)
      try {
        final firestoreDoc = await _firestore.collection('users').doc(userId).get();
        if (firestoreDoc.exists) {
          final userData = firestoreDoc.data()!;
          print('✅ Found user in Firestore: ${userData['name']} (${userData['email']})');

          // Ensure required fields exist
          return {
            'name': userData['name'] ?? 'Pengguna',
            'email': userData['email'] ?? 'Email tidak tersedia',
            'isOnline': userData['isOnline'] ?? false,
            'lastSeen': userData['lastSeen'],
            'createdAt': userData['createdAt'],
          };
        }
      } catch (firestoreError) {
        print('⚠️ Firestore error for $userId: $firestoreError');
      }

      // Method 2: Fallback to Realtime Database
      try {
        final rtdbSnapshot = await _database.child('users').child(userId).once();
        if (rtdbSnapshot.snapshot.exists) {
          final userData = Map<String, dynamic>.from(rtdbSnapshot.snapshot.value as Map);
          print('✅ Found user in RTDB: ${userData['name']} (${userData['email']})');

          return {
            'name': userData['name'] ?? 'Pengguna',
            'email': userData['email'] ?? 'Email tidak tersedia',
            'isOnline': userData['isOnline'] ?? false,
            'lastSeen': userData['lastSeen'],
            'createdAt': userData['createdAt'],
          };
        }
      } catch (rtdbError) {
        print('⚠️ RTDB error for $userId: $rtdbError');
      }

      print('❌ User $userId not found in any database');
      return null;

    } catch (e) {
      print('❌ Error getting user data for $userId: $e');
      return null;
    }
  }

  void _acceptConnectionRequest(String fromUserId, String fromUserName) async {
    try {
      final currentUser = _auth.currentUser!;

      // Create bidirectional connection
      await _database.child('connections').child(currentUser.uid).child(fromUserId).set({
        'status': 'accepted',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      await _database.child('connections').child(fromUserId).child(currentUser.uid).set({
        'status': 'accepted',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      // Remove the connection request
      await _database.child('connection_requests').child(currentUser.uid).child(fromUserId).remove();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text('Koneksi dengan $fromUserName diterima')),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.all(16),
        ),
      );

      print('✅ Connection accepted: $fromUserName');
    } catch (e) {
      print('❌ Error accepting connection: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text('Error: ${e.toString()}')),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.all(16),
        ),
      );
    }
  }

  void _rejectConnectionRequest(String fromUserId, String fromUserName) async {
    try {
      final currentUser = _auth.currentUser!;
      await _database.child('connection_requests').child(currentUser.uid).child(fromUserId).remove();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.info, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text('Permintaan dari $fromUserName ditolak')),
            ],
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.all(16),
        ),
      );

      print('✅ Connection rejected: $fromUserName');
    } catch (e) {
      print('❌ Error rejecting connection: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text('Error: ${e.toString()}')),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.all(16),
        ),
      );
    }
  }

  void _removeConnection(String userId, String userName) async {
    try {
      final currentUser = _auth.currentUser!;

      // Remove bidirectional connection
      await _database.child('connections').child(currentUser.uid).child(userId).remove();
      await _database.child('connections').child(userId).child(currentUser.uid).remove();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.info, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text('Koneksi dengan $userName dihapus')),
            ],
          ),
          backgroundColor: Colors.blue,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.all(16),
        ),
      );

      print('✅ Connection removed: $userName');
    } catch (e) {
      print('❌ Error removing connection: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text('Error: ${e.toString()}')),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.all(16),
        ),
      );
    }
  }

  String _getLastSeenText(dynamic lastSeen) {
    if (lastSeen == null) return 'Tidak diketahui';

    try {
      DateTime lastSeenDate;

      // Handle different timestamp formats
      if (lastSeen is Timestamp) {
        lastSeenDate = lastSeen.toDate();
      } else if (lastSeen is int) {
        lastSeenDate = DateTime.fromMillisecondsSinceEpoch(lastSeen);
      } else {
        return 'Tidak diketahui';
      }

      final now = DateTime.now();
      final difference = now.difference(lastSeenDate);

      if (difference.inMinutes < 5) {
        return 'Baru saja';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes} menit lalu';
      } else if (difference.inDays < 1) {
        return '${difference.inHours} jam lalu';
      } else {
        return '${difference.inDays} hari lalu';
      }
    } catch (e) {
      return 'Tidak diketahui';
    }
  }

  Widget _buildGradientAppBar() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade600, Colors.blue.shade800],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: AppBar(
        title: Text(
          'Koneksi Saya',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Container(
            margin: EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: Icon(Icons.refresh_rounded),
              onPressed: () {
                _loadConnectionRequests();
                _loadConnections();
              },
              tooltip: 'Refresh',
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(60),
          child: Container(
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: TextStyle(fontWeight: FontWeight.bold),
              unselectedLabelStyle: TextStyle(fontWeight: FontWeight.normal),
              tabs: [
                Tab(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_add_rounded),
                      SizedBox(height: 4),
                      Text('Permintaan (${_connectionRequests.length})'),
                    ],
                  ),
                ),
                Tab(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_rounded),
                      SizedBox(height: 4),
                      Text('Terhubung (${_connections.length})'),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(120),
        child: _buildGradientAppBar(),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Connection Requests Tab
          _buildConnectionRequestsTab(),

          // Connections Tab
          _buildConnectionsTab(),
        ],
      ),
    );
  }

  Widget _buildConnectionRequestsTab() {
    if (_isLoadingRequests) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.1),
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
                    strokeWidth: 3,
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Memuat permintaan...',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_connectionRequests.isEmpty) {
      return Center(
        child: Container(
          margin: EdgeInsets.all(32),
          padding: EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.inbox_rounded,
                  size: 48,
                  color: Colors.blue.shade400,
                ),
              ),
              SizedBox(height: 24),
              Text(
                'Tidak ada permintaan koneksi',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Permintaan koneksi dari teman akan muncul di sini',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        _loadConnectionRequests();
      },
      color: Colors.blue.shade600,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 20, 16, 100),
        itemCount: _connectionRequests.length,
        itemBuilder: (context, index) {
          final request = _connectionRequests[index];
          final isOnline = request['isOnline'] == true;

          return Container(
            margin: EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 15,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              leading: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Colors.orange.shade300, Colors.orange.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withOpacity(0.3),
                          blurRadius: 10,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.transparent,
                      child: Text(
                        (request['fromUserName'] != null && request['fromUserName'].isNotEmpty)
                            ? request['fromUserName'][0].toString().toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: isOnline ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: (isOnline ? Colors.green : Colors.grey).withOpacity(0.3),
                            blurRadius: 5,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              title: Text(
                request['fromUserName'] ?? 'Pengguna',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.grey.shade800,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 6),
                  Text(
                    request['fromUserEmail'] ?? 'Email tidak tersedia',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  SizedBox(height: 6),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.handshake_rounded,
                          size: 12,
                          color: Colors.blue.shade600,
                        ),
                        SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Ingin terhubung',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.3),
                          blurRadius: 6,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: () => _acceptConnectionRequest(
                        request['fromUserId'],
                        request['fromUserName'] ?? 'Pengguna',
                      ),
                      icon: Icon(Icons.check_rounded),
                      color: Colors.white,
                      iconSize: 18,
                      tooltip: 'Terima',
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  SizedBox(width: 6),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.3),
                          blurRadius: 6,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: () => _rejectConnectionRequest(
                        request['fromUserId'],
                        request['fromUserName'] ?? 'Pengguna',
                      ),
                      icon: Icon(Icons.close_rounded),
                      color: Colors.white,
                      iconSize: 18,
                      tooltip: 'Tolak',
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildConnectionsTab() {
    if (_isLoadingConnections) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.1),
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
                    strokeWidth: 3,
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Memuat koneksi...',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_connections.isEmpty) {
      return Center(
        child: Container(
          margin: EdgeInsets.all(32),
          padding: EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.people_outline_rounded,
                  size: 48,
                  color: Colors.blue.shade400,
                ),
              ),
              SizedBox(height: 24),
              Text(
                'Belum ada koneksi',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Cari teman dan kirim permintaan koneksi\nuntuk mulai berbagi lokasi',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        _loadConnections();
      },
      color: Colors.blue.shade600,
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, 20, 16, 100),
        itemCount: _connections.length,
        itemBuilder: (context, index) {
          final connection = _connections[index];
          final isOnline = connection['isOnline'] == true;

          return Container(
            margin: EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 15,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              leading: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Colors.green.shade300, Colors.green.shade600],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withOpacity(0.3),
                          blurRadius: 10,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.transparent,
                      child: Text(
                        (connection['name'] != null && connection['name'].isNotEmpty)
                            ? connection['name'][0].toString().toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: isOnline ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: (isOnline ? Colors.green : Colors.grey).withOpacity(0.3),
                            blurRadius: 5,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              title: Text(
                connection['name'] ?? 'Pengguna',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.grey.shade800,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 6),
                  Text(
                    connection['email'] ?? 'Email tidak tersedia',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  SizedBox(height: 6),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isOnline ? Colors.green.shade50 : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isOnline ? Colors.green.shade200 : Colors.grey.shade300,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isOnline ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            isOnline ? 'Online' : 'Offline',
                            style: TextStyle(
                              fontSize: 10,
                              color: isOnline ? Colors.green.shade700 : Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              trailing: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: PopupMenuButton(
                  icon: Icon(Icons.more_vert_rounded, color: Colors.grey.shade600, size: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 8,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'remove',
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.red,
                                size: 18,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Hapus Koneksi',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    if (value == 'remove') {
                      showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return Dialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Container(
                              padding: EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.delete_outline_rounded,
                                      color: Colors.red,
                                      size: 32,
                                    ),
                                  ),
                                  SizedBox(height: 20),
                                  Text(
                                    'Hapus Koneksi',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'Apakah Anda yakin ingin menghapus koneksi dengan ${connection['name'] ?? 'Pengguna'}?\n\nAnda tidak akan bisa melihat lokasi mereka lagi.',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      height: 1.5,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: 24),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Container(
                                          height: 48,
                                          child: TextButton(
                                            onPressed: () => Navigator.of(context).pop(),
                                            child: Text(
                                              'Batal',
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            style: TextButton.styleFrom(
                                              backgroundColor: Colors.grey.shade100,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Container(
                                          height: 48,
                                          child: ElevatedButton(
                                            onPressed: () {
                                              Navigator.of(context).pop();
                                              _removeConnection(
                                                connection['userId'],
                                                connection['name'] ?? 'Pengguna',
                                              );
                                            },
                                            child: Text(
                                              'Hapus',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              elevation: 0,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    }
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}