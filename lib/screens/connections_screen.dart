import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class ConnectionsScreen extends StatefulWidget {
  @override
  _ConnectionsScreenState createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> with TickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _database = FirebaseDatabase.instance.ref();

  TabController? _tabController;
  List<Map<String, dynamic>> _connectionRequests = [];
  List<Map<String, dynamic>> _connections = [];

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
        .listen((event) {
      if (event.snapshot.exists) {
        final requests = <Map<String, dynamic>>[];
        final requestsData = Map<String, dynamic>.from(
            event.snapshot.value as Map);

        requestsData.forEach((fromUserId, requestData) {
          final request = Map<String, dynamic>.from(requestData as Map);
          request['fromUserId'] = fromUserId;

          // Fallback jika fromUserName null
          if (!request.containsKey('fromUserName') || request['fromUserName'] == null) {
            request['fromUserName'] = 'Pengguna';
          }

          if (request['status'] == 'pending') {
            requests.add(request);
          }
        });

        setState(() {
          _connectionRequests = requests;
        });
      } else {
        setState(() {
          _connectionRequests = [];
        });
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
      if (event.snapshot.exists) {
        final connections = <Map<String, dynamic>>[];
        final connectionsData = Map<String, dynamic>.from(
            event.snapshot.value as Map);

        for (String userId in connectionsData.keys) {
          final connectionData = Map<String, dynamic>.from(
              connectionsData[userId] as Map);
          if (connectionData['status'] == 'accepted') {
            // Get user info
            final userSnapshot = await _database.child('users')
                .child(userId)
                .once();
            if (userSnapshot.snapshot.exists) {
              final userData = Map<String, dynamic>.from(
                  userSnapshot.snapshot.value as Map);

              // Fallback jika name null
              if (!userData.containsKey('name') || userData['name'] == null) {
                userData['name'] = 'Pengguna';
              }

              userData['userId'] = userId;
              connections.add(userData);
            }
          }
        }

        setState(() {
          _connections = connections;
        });
      } else {
        setState(() {
          _connections = [];
        });
      }
    });
  }

  void _acceptConnectionRequest(String fromUserId, String fromUserName) async {
    try {
      final currentUser = _auth.currentUser!;

      await _database.child('connections').child(currentUser.uid).child(
          fromUserId).set({
        'status': 'accepted',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      await _database.child('connections').child(fromUserId).child(
          currentUser.uid).set({
        'status': 'accepted',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      await _database.child('connection_requests').child(currentUser.uid).child(
          fromUserId).remove();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Koneksi dengan $fromUserName diterima')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  void _rejectConnectionRequest(String fromUserId, String fromUserName) async {
    try {
      final currentUser = _auth.currentUser!;
      await _database.child('connection_requests').child(currentUser.uid).child(
          fromUserId).remove();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Permintaan dari $fromUserName ditolak')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  void _removeConnection(String userId, String userName) async {
    try {
      final currentUser = _auth.currentUser!;

      await _database.child('connections').child(currentUser.uid)
          .child(userId)
          .remove();
      await _database.child('connections').child(userId)
          .child(currentUser.uid)
          .remove();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Koneksi dengan $userName dihapus')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Koneksi Saya'),
        backgroundColor: Colors.blue,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              text: 'Permintaan (${_connectionRequests.length})',
            ),
            Tab(
              text: 'Terhubung (${_connections.length})',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Connection Requests Tab
          _connectionRequests.isEmpty
              ? Center(
            child: Text('Tidak ada permintaan koneksi'),
          )
              : ListView.builder(
            itemCount: _connectionRequests.length,
            itemBuilder: (context, index) {
              final request = _connectionRequests[index];
              return Card(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      (request['fromUserName'] != null &&
                          request['fromUserName'].isNotEmpty)
                          ? request['fromUserName'][0]
                          .toString()
                          .toUpperCase()
                          : '?',
                    ),
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  title: Text(request['fromUserName'] ?? 'Pengguna'),
                  subtitle: Text('Ingin terhubung dengan Anda'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _acceptConnectionRequest(
                          request['fromUserId'],
                          request['fromUserName'] ?? 'Pengguna',
                        ),
                        icon: Icon(Icons.check),
                        color: Colors.green,
                      ),
                      IconButton(
                        onPressed: () => _rejectConnectionRequest(
                          request['fromUserId'],
                          request['fromUserName'] ?? 'Pengguna',
                        ),
                        icon: Icon(Icons.close),
                        color: Colors.red,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

          // Connections Tab
          _connections.isEmpty
              ? Center(
            child: Text('Belum ada koneksi'),
          )
              : ListView.builder(
            itemCount: _connections.length,
            itemBuilder: (context, index) {
              final connection = _connections[index];
              return Card(
                margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      (connection['name'] != null &&
                          connection['name'].isNotEmpty)
                          ? connection['name'][0]
                          .toString()
                          .toUpperCase()
                          : '?',
                    ),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  title: Text(connection['name'] ?? 'Pengguna'),
                  subtitle: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: connection['isOnline'] == true
                              ? Colors.green
                              : Colors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(connection['isOnline'] == true
                          ? 'Online'
                          : 'Offline'),
                    ],
                  ),
                  trailing: PopupMenuButton(
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'remove',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Hapus Koneksi'),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      if (value == 'remove') {
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              title: Text('Hapus Koneksi'),
                              content: Text(
                                  'Apakah Anda yakin ingin menghapus koneksi dengan ${connection['name'] ?? 'Pengguna'}?'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(),
                                  child: Text('Batal'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    _removeConnection(
                                        connection['userId'],
                                        connection['name'] ??
                                            'Pengguna');
                                  },
                                  child: Text('Hapus',
                                      style:
                                      TextStyle(color: Colors.red)),
                                ),
                              ],
                            );
                          },
                        );
                      }
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
