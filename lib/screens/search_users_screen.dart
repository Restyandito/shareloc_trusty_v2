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
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 12),
                Expanded(child: Text('Error loading users: $rtdbError')),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: EdgeInsets.all(16),
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
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 12),
                Expanded(child: Text('Data pengguna tidak ditemukan')),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: EdgeInsets.all(16),
          ),
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
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text('Permintaan terkirim ke $targetUserName')),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.all(16),
        ),
      );
    } catch (e) {
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
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text('Test user "$testUserName" created!')),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: EdgeInsets.all(16),
        ),
      );

      await _loadAllUsers();
    } catch (e) {
      print('Error creating test user: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text('Error creating test user: $e')),
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

  // Generate consistent colors for users based on their name
  List<Color> _getUserAvatarColors(String name) {
    final colorPalettes = [
      [Colors.blue.shade300, Colors.blue.shade600],        // Index 0
      [Colors.purple.shade300, Colors.purple.shade600],    // Index 1
      [Colors.green.shade300, Colors.green.shade600],      // Index 2
      [Colors.orange.shade300, Colors.orange.shade600],    // Index 3
      [Colors.pink.shade300, Colors.pink.shade600],        // Index 4
      [Colors.teal.shade300, Colors.teal.shade600],        // Index 5
      [Colors.indigo.shade300, Colors.indigo.shade600],    // Index 6
      [Colors.red.shade300, Colors.red.shade600],          // Index 7
      [Colors.amber.shade300, Colors.amber.shade600],      // Index 8
      [Colors.cyan.shade300, Colors.cyan.shade600],        // Index 9
      [Colors.deepOrange.shade300, Colors.deepOrange.shade600], // Index 10
      [Colors.lime.shade300, Colors.lime.shade600],        // Index 11
      [Colors.brown.shade300, Colors.brown.shade600],      // Index 12
      [Colors.blueGrey.shade300, Colors.blueGrey.shade600], // Index 13
      [Colors.deepPurple.shade300, Colors.deepPurple.shade600], // Index 14
    ];

    // Create a more diverse hash based on name characters
    int hash = 0;
    for (int i = 0; i < name.length; i++) {
      hash = hash + name.codeUnitAt(i);
    }

    // Add additional variation based on name length and first character
    hash = hash + (name.length * 17) + (name.isNotEmpty ? name.codeUnitAt(0) * 31 : 0);

    final colorIndex = hash.abs() % colorPalettes.length;

    print('🎨 Color for "$name": Index $colorIndex (Hash: $hash)');

    return colorPalettes[colorIndex];
  }

  Color _getUserAvatarShadowColor(String name) {
    final colors = _getUserAvatarColors(name);
    return colors[1].withOpacity(0.3);
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
          'Cari Pengguna',
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
              onPressed: _loadAllUsers,
              tooltip: 'Refresh daftar pengguna',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchSection() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Cari berdasarkan nama atau email',
                labelStyle: TextStyle(color: Colors.grey.shade600),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                prefixIcon: Container(
                  margin: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.search_rounded, color: Colors.blue.shade600),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? Container(
                  margin: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.clear_rounded, color: Colors.grey.shade600),
                    onPressed: () {
                      _searchController.clear();
                      _searchUsers('');
                    },
                  ),
                )
                    : null,
              ),
              onChanged: _searchUsers,
              onSubmitted: _searchUsers,
              style: TextStyle(fontSize: 16),
            ),
          ),
          SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _showingAllUsers ? Colors.blue.shade50 : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _showingAllUsers ? Colors.blue.shade200 : Colors.orange.shade200,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showingAllUsers ? Icons.people_rounded : Icons.search_rounded,
                      size: 16,
                      color: _showingAllUsers ? Colors.blue.shade600 : Colors.orange.shade600,
                    ),
                    SizedBox(width: 6),
                    Text(
                      _showingAllUsers
                          ? 'Semua Pengguna (${_allUsers.length})'
                          : 'Hasil Pencarian (${_searchResults.length})',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _showingAllUsers ? Colors.blue.shade600 : Colors.orange.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (_allUsers.isEmpty && !_isLoading)
                Container(
                  height: 32,
                  child: TextButton.icon(
                    onPressed: _loadAllUsers,
                    icon: Icon(Icons.refresh_rounded, size: 16),
                    label: Text('Muat Ulang', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.grey.shade100,
                      foregroundColor: Colors.grey.shade700,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Expanded(
      child: Center(
        child: Container(
          padding: EdgeInsets.all(32),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
                strokeWidth: 3,
              ),
              SizedBox(height: 20),
              Text(
                'Mencari pengguna...',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyAllUsersState() {
    return Expanded(
      child: Center(
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
                'Tidak ada pengguna lain',
                style: TextStyle(
                  fontSize: 20,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Pastikan ada pengguna lain yang sudah registrasi\natau coba refresh untuk memuat ulang data',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _loadAllUsers,
                icon: Icon(Icons.refresh_rounded),
                label: Text('Coba Lagi'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptySearchState() {
    return Expanded(
      child: Center(
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
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.search_off_rounded,
                  size: 48,
                  color: Colors.orange.shade400,
                ),
              ),
              SizedBox(height: 24),
              Text(
                'Tidak ada hasil untuk "${_searchController.text}"',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12),
              Text(
                'Coba kata kunci yang berbeda atau lihat semua pengguna',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  _searchController.clear();
                  _searchUsers('');
                },
                icon: Icon(Icons.people_rounded),
                label: Text('Lihat Semua Pengguna'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUsersList() {
    return Expanded(
      child: RefreshIndicator(
        onRefresh: () async {
          await _loadAllUsers();
        },
        color: Colors.blue.shade600,
        child: ListView.builder(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 100),
          itemCount: _searchResults.length,
          itemBuilder: (context, index) {
            final user = _searchResults[index];
            final isOnline = user['isOnline'] == true;
            final userName = user['name'] ?? 'User';
            final avatarColors = _getUserAvatarColors(userName);
            final shadowColor = _getUserAvatarShadowColor(userName);

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
                contentPadding: EdgeInsets.all(20),
                leading: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: avatarColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: shadowColor,
                            blurRadius: 10,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.transparent,
                        child: Text(
                          (userName.isNotEmpty)
                              ? userName[0].toString().toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: isOnline ? Colors.green : Colors.grey,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
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
                  userName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.grey.shade800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 6),
                    Text(
                      user['email'] ?? 'Email tidak tersedia',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 10),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isOnline ? Colors.green.shade50 : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isOnline ? Colors.green.shade200 : Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isOnline ? Colors.green : Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            isOnline ? 'Online' : 'Offline',
                            style: TextStyle(
                              fontSize: 12,
                              color: isOnline ? Colors.green.shade700 : Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                trailing: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade400, Colors.blue.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: () => _sendConnectionRequest(
                      user['userId'],
                      user['name'] ?? 'User',
                    ),
                    icon: Icon(Icons.person_add_rounded, size: 16),
                    label: Text(
                      'Hubungkan',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ),
                isThreeLine: true,
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight),
        child: _buildGradientAppBar(),
      ),
      body: Column(
        children: [
          _buildSearchSection(),

          if (_isLoading)
            _buildLoadingState()
          else if (_searchResults.isEmpty && _allUsers.isEmpty)
            _buildEmptyAllUsersState()
          else if (_searchResults.isEmpty && !_showingAllUsers)
              _buildEmptySearchState()
            else
              _buildUsersList(),
        ],
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.green.shade400, Colors.green.shade600],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withOpacity(0.3),
              blurRadius: 15,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: _createTestUser,
          icon: Icon(Icons.add_rounded, color: Colors.white),
          label: Text(
            'Test User',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          tooltip: 'Buat test user untuk debugging',
        ),
      ),
    );
  }
}