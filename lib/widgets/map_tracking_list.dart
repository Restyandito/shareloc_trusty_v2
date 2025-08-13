import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/map_services.dart';

/// User tracking list widget
class MapTrackingList extends StatelessWidget {
  final Map<String, LatLng> userLocations;
  final Map<String, String> userNames;
  final LatLng? currentPosition;
  final bool useAStarRouting;
  final double maxDistance;
  final Function(String) onFocusUser;

  const MapTrackingList({
    Key? key,
    required this.userLocations,
    required this.userNames,
    required this.currentPosition,
    required this.useAStarRouting,
    required this.maxDistance,
    required this.onFocusUser,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 12, offset: Offset(0, -3)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildListHeader(),
            if (userLocations.isEmpty) _buildEmptyState() else _buildUserList(),
          ],
        ),
      ),
    );
  }

  Widget _buildListHeader() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade100, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: useAStarRouting ? Colors.green.shade50 : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.people_rounded,
              color: useAStarRouting ? Colors.green.shade600 : Colors.blue.shade600,
              size: 20,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  useAStarRouting ? 'Rute Pintar' : 'Orang yang Dilacak',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey.shade800),
                ),
                if (userLocations.isNotEmpty)
                  Text(
                    useAStarRouting ? '${userLocations.length} rute optimal' : '${userLocations.length} teman aktif',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
              ],
            ),
          ),
          if (userLocations.isNotEmpty)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: useAStarRouting ? Colors.green.shade600 : Colors.blue.shade600,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                '${userLocations.length}',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUserList() {
    return Flexible(
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.symmetric(vertical: 8),
        itemCount: userLocations.length,
        itemBuilder: (context, index) {
          final userId = userLocations.keys.elementAt(index);
          return _buildUserCard(userId);
        },
      ),
    );
  }

  Widget _buildUserCard(String userId) {
    final userName = userNames[userId] ?? 'User';
    final userLocation = userLocations[userId];
    final distance = userLocation != null && currentPosition != null
        ? MapUtils.calculateDistance(currentPosition!, userLocation)
        : 0.0;
    final distanceText = MapUtils.formatDistance(distance);
    final isFarAway = distance > maxDistance;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onFocusUser(userId),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isFarAway ? Colors.red.shade50 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isFarAway ? Colors.red.shade200 : Colors.grey.shade100),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isFarAway
                          ? [Colors.red.shade400, Colors.red.shade600]
                          : useAStarRouting
                          ? [Colors.green.shade400, Colors.green.shade600]
                          : [Colors.blue.shade400, Colors.blue.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Center(
                    child: Text(
                      userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.grey.shade800),
                      ),
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isFarAway ? Colors.red : useAStarRouting ? Colors.green : Colors.blue,
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              isFarAway
                                  ? 'Jarak terlalu jauh!'
                                  : useAStarRouting ? 'Rute optimal aktif' : 'Berbagi lokasi aktif',
                              style: TextStyle(
                                fontSize: 12,
                                color: isFarAway ? Colors.red.shade600 : Colors.grey.shade600,
                                fontWeight: isFarAway ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isFarAway
                            ? Colors.red.shade50
                            : useAStarRouting ? Colors.green.shade50 : Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        distanceText,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isFarAway
                              ? Colors.red.shade700
                              : useAStarRouting
                              ? Colors.green.shade700
                              : Colors.blue.shade700,
                        ),
                      ),
                    ),
                    SizedBox(height: 4),
                    Icon(
                      isFarAway ? Icons.warning_rounded : Icons.touch_app,
                      size: 14,
                      color: isFarAway ? Colors.red.shade400 : Colors.grey.shade400,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(20)),
            child: Icon(Icons.location_off_rounded, size: 32, color: Colors.grey.shade400),
          ),
          SizedBox(height: 16),
          Text(
            'Belum ada teman yang berbagi lokasi',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 4),
          Text(
            'Ajak teman untuk berbagi lokasi',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}