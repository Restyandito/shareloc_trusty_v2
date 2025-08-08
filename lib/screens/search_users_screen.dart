import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart' hide Query;
import 'package:cloud_firestore/cloud_firestore.dart';

class SearchUsersScreen extends StatefulWidget {
  @override
  _SearchUsersScreenState createState() => _SearchUsersScreenState();
}

class _SearchUsersScreenState extends State<SearchUsersScreen> {
  final _auth = FirebaseAuth.instance;
  final _database = FirebaseDatabase.instance.ref();
  final _firestore = FirebaseFirestore.instance;
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _allUsers = [];
  bool _isLoading = false;
  bool _showingAllUsers = false;

  @override
  void initState() {
    super.initState();
    _loadAllUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllUsers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      print('Loading all users from Firestore...');

      // Get all users from Firestore
      final querySnapshot = await _firestore.collection('users').get();
      final users = <Map<String, dynamic>>[];

      for (var doc in querySnapshot.docs) {
        // Skip current user
        if (doc.id != _auth.currentUser!.uid) {
          final userData = doc.data();
          userData['userId'] = doc.id;
          users.add(userData);
        }
      }

      print('Loaded ${users.length} users from Firestore');

      setState(() {
        _allUsers = users;
        _searchResults = users; // Show all users initially
        _showingAllUsers = true;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading users from Firestore: $e');

      // Fallback to Realtime Database if Firestore fails
      try {
        print('Fallback: Loading users from Realtime Database...');
        final snapshot = await _database.child('users').once();
        final users = <Map<String, dynamic>>[];

        if (snapshot.snapshot.exists) {
          final usersData = Map<String, dynamic>.from(snapshot.snapshot.value as Map);

          usersData.forEach((userId, userData) {
            if (userId != _auth.currentUser!.uid) {
              final userMap = Map<String, dynamic>.from(userData as Map);
              userMap['userId'] = userId;
              users.add(userMap);
            }
          });
        }

        setState(() {
          _allUsers = users;
          _searchResults = users;
          _showingAllUsers = true;
          _isLoading = false;
        });
      } catch (rtdbError) {
        print('Error loading users from Realtime Database: $rtdbError');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading users: $rtdbError'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _searchUsers(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = _allUsers;
        _showingAllUsers = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _showingAllUsers = false;
    });

    try {
      print('Searching users in Firestore for: "$query"');

      final searchQuery = query.toLowerCase().trim();

      // Method 1: Use array-contains for searchKeywords
      Query firestoreQuery = _firestore
          .collection('users')
          .where('searchKeywords', arrayContains: searchQuery);

      final querySnapshot = await firestoreQuery.get();
      final users = <Map<String, dynamic>>[];

      for (var doc in querySnapshot.docs) {
        if (doc.id != _auth.currentUser!.uid) {
          final userData = doc.data() as Map<String, dynamic>;
          userData['userId'] = doc.id;
          users.add(userData);
        }
      }

      // Method 2: If no results with exact match, try partial search from local cache
      if (users.isEmpty) {
        print('No exact matches found, searching locally...');
        final filteredUsers = _allUsers.where((user) {
          final name = user['name'].toString().toLowerCase();
          final email = user['email'].toString().toLowerCase();

          return name.contains(searchQuery) ||
              email.contains(searchQuery) ||
              name.split(' ').any((word) => word.startsWith(searchQuery));
        }).toList();

        users.addAll(filteredUsers);
      }

      print('Found ${users.length} users matching "$query"');

      setState(() {
        _searchResults = users;
        _isLoading = false;
      });
    } catch (e) {
      print('Error searching users: $e');

      // Fallback to local search
      final filteredUsers = _allUsers.where((user) {
        final name = user['name'].toString().toLowerCase();
        final email = user['email'].toString().toLowerCase();
        final searchQuery = query.toLowerCase();

        return name.contains(searchQuery) || email.contains(searchQuery);
      }).toList();

      setState(() {
        _searchResults = filteredUsers;
        _isLoading = false;
      });
    }
  }

  void _sendConnectionRequest(String targetUserId, String targetUserName) async {
    try {
      final currentUser = _auth.currentUser!;
      final myUserSnapshot = await _database.child('users').child(currentUser.uid).get();

      if (!myUserSnapshot.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Data pengguna tidak ditemukan')),
        );
        return;
      }

      final myData = Map<String, dynamic>.from(myUserSnapshot.value as Map);

      // Simpan / overwrite langsung setiap kali kirim
      await _database
          .child('connection_requests')
          .child(targetUserId)
          .child(currentUser.uid)
          .set({
        'fromUserId': currentUser.uid,
        'fromUserName': myData['name'] ?? 'Pengguna',
        'status': 'pending',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Permintaan terkirim ke $targetUserName')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  Future<Map<String, dynamic>> _getCurrentUserData() async {
    try {
      final currentUser = _auth.currentUser!;

      // Try Firestore first
      final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
      if (userDoc.exists) {
        return userDoc.data()!;
      }

      // Fallback to Realtime Database
      final snapshot = await _database.child('users').child(currentUser.uid).once();
      if (snapshot.snapshot.exists) {
        return Map<String, dynamic>.from(snapshot.snapshot.value as Map);
      }
    } catch (e) {
      print('Error getting current user data: $e');
    }

    return {'name': 'User'};
  }

  void _createTestUser() async {
    try {
      final testUserId = 'test_user_${DateTime.now().millisecondsSinceEpoch}';
      final testUserName = 'Test User ${DateTime.now().millisecond}';
      final testUserEmail = 'test${DateTime.now().millisecond}@example.com';

      final testUserData = {
        'name': testUserName,
        'email': testUserEmail,
        'isOnline': true,
        'createdAt': FieldValue.serverTimestamp(),
        'searchKeywords': _generateSearchKeywords(testUserName, testUserEmail),
      };

      // Save to Firestore
      await _firestore.collection('users').doc(testUserId).set(testUserData);

      // Also save to Realtime Database for compatibility
      await _database.child('users').child(testUserId).set({
        ...testUserData,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Test user "$testUserName" created!'),
          backgroundColor: Colors.green,
        ),
      );

      await _loadAllUsers();
    } catch (e) {
      print('Error creating test user: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating test user: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<String> _generateSearchKeywords(String name, String email) {
    final keywords = <String>[];

    // Add full name and email (lowercase)
    keywords.add(name.toLowerCase());
    keywords.add(email.toLowerCase());

    // Add individual words from name
    final nameWords = name.toLowerCase().split(' ');
    keywords.addAll(nameWords);

    // Add email username (before @)
    final emailUsername = email.split('@')[0].toLowerCase();
    keywords.add(emailUsername);

    // Add partial matches (first 3+ characters of each word)
    for (String word in nameWords) {
      if (word.length >= 3) {
        for (int i = 3; i <= word.length; i++) {
          keywords.add(word.substring(0, i));
        }
      }
    }

    return keywords.toSet().toList(); // Remove duplicates
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Cari Pengguna'),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadAllUsers,
            tooltip: 'Refresh daftar pengguna',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Cari berdasarkan nama atau email',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                      icon: Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _searchUsers('');
                      },
                    )
                        : null,
                  ),
                  onChanged: _searchUsers,
                  onSubmitted: _searchUsers,
                ),
                SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _showingAllUsers
                          ? 'Semua Pengguna (${_allUsers.length})'
                          : 'Hasil Pencarian (${_searchResults.length})',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                    if (_allUsers.isEmpty && !_isLoading)
                      TextButton.icon(
                        onPressed: _loadAllUsers,
                        icon: Icon(Icons.refresh, size: 16),
                        label: Text('Muat Ulang'),
                      ),
                  ],
                ),
              ],
            ),
          ),

          if (_isLoading)
            Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_searchResults.isEmpty && _allUsers.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
                    SizedBox(height: 16),
                    Text(
                      'Tidak ada pengguna lain',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Pastikan ada pengguna lain yang sudah registrasi\natau coba refresh untuk memuat ulang data',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _loadAllUsers,
                      icon: Icon(Icons.refresh),
                      label: Text('Coba Lagi'),
                    ),
                  ],
                ),
              ),
            )
          else if (_searchResults.isEmpty && !_showingAllUsers)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                      SizedBox(height: 16),
                      Text(
                        'Tidak ada hasil untuk "${_searchController.text}"',
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Coba kata kunci yang berbeda atau lihat semua pengguna',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: () {
                          _searchController.clear();
                          _searchUsers('');
                        },
                        icon: Icon(Icons.people),
                        label: Text('Lihat Semua Pengguna'),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    await _loadAllUsers();
                  },
                  child: ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final user = _searchResults[index];
                      return Card(
                        margin: EdgeInsets.only(bottom: 8),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: EdgeInsets.all(16),
                          leading: CircleAvatar(
                            radius: 28,
                            child: Text(
                              user['name'][0].toString().toUpperCase(),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            backgroundColor: Colors.blue[100],
                            foregroundColor: Colors.blue[800],
                          ),
                          title: Text(
                            user['name'] ?? 'Nama tidak tersedia',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: 4),
                              Text(
                                user['email'] ?? 'Email tidak tersedia',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              SizedBox(height: 8),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: user['isOnline'] == true
                                          ? Colors.green
                                          : Colors.grey,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    user['isOnline'] == true ? 'Online' : 'Offline',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: user['isOnline'] == true
                                          ? Colors.green
                                          : Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: ElevatedButton.icon(
                            onPressed: () => _sendConnectionRequest(
                              user['userId'],
                              user['name'] ?? 'User',
                            ),
                            icon: Icon(Icons.person_add, size: 16),
                            label: Text('Hubungkan'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
                ),
              ),
        ],
      ),

      // Debug button
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createTestUser,
        icon: Icon(Icons.add),
        label: Text('Test User'),
        backgroundColor: Colors.green,
        tooltip: 'Buat test user untuk debugging',
      ),
    );
  }
}