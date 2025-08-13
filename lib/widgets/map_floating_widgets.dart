import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/distance_notification.dart';

/// Distance notifications widget
class MapDistanceNotifications extends StatelessWidget {
  final List<DistanceNotification> notifications;
  final Animation<double>? animation;
  final bool vibrationEnabled;
  final Function(String) onFocusUser;
  final VoidCallback onDismiss;

  const MapDistanceNotifications({
    Key? key,
    required this.notifications,
    required this.animation,
    required this.vibrationEnabled,
    required this.onFocusUser,
    required this.onDismiss,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (notifications.isEmpty || animation == null) {
      return SizedBox.shrink();
    }

    return Positioned(
      top: MediaQuery.of(context).padding.top + 72,
      left: 16,
      right: 16,
      child: AnimatedBuilder(
        animation: animation!,
        builder: (context, child) {
          final animValue = animation!.value.clamp(0.0, 1.0);

          return Transform.scale(
            scale: animValue,
            child: Opacity(
              opacity: animValue,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.3,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.orange.shade50, Colors.red.shade50],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.shade200, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withOpacity(0.2),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildNotificationHeader(),
                    if (notifications.length == 1)
                      _buildSingleNotification(notifications.first)
                    else
                      _buildMultipleNotifications(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotificationHeader() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade100,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.warning_rounded, color: Colors.orange.shade800, size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Jarak Terlalu Jauh!',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                    ),
                    if (vibrationEnabled) ...[
                      SizedBox(width: 8),
                      Icon(Icons.vibration, color: Colors.purple.shade600, size: 16),
                    ],
                  ],
                ),
                Text(
                  notifications.length == 1
                      ? 'Teman Anda berada lebih dari 1km'
                      : '${notifications.length} teman berada lebih dari 1km',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onDismiss,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, color: Colors.orange.shade600, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleNotification(DistanceNotification notification) {
    final distanceKm = (notification.distance / 1000).toStringAsFixed(1);

    return Container(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.red.shade400, Colors.red.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Center(
              child: Text(
                notification.userName.isNotEmpty ? notification.userName[0].toUpperCase() : 'U',
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
                  notification.userName,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.grey.shade800),
                ),
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.location_on, color: Colors.red.shade500, size: 14),
                    SizedBox(width: 4),
                    Text('$distanceKm km dari Anda', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                onFocusUser(notification.userId);
                onDismiss();
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
                child: Text('Lihat', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange.shade700)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultipleNotifications() {
    return Container(
      constraints: BoxConstraints(maxHeight: 200),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.symmetric(vertical: 8),
        itemCount: notifications.length,
        itemBuilder: (context, index) {
          final notification = notifications[index];
          final distanceKm = (notification.distance / 1000).toStringAsFixed(1);

          return Container(
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade100),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: Colors.red.shade500, borderRadius: BorderRadius.circular(16)),
                  child: Center(
                    child: Text(
                      notification.userName.isNotEmpty ? notification.userName[0].toUpperCase() : 'U',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.userName,
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey.shade800),
                      ),
                      Text('$distanceKm km', style: TextStyle(fontSize: 11, color: Colors.red.shade600, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      onFocusUser(notification.userId);
                      onDismiss();
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(6)),
                      child: Icon(Icons.visibility_rounded, color: Colors.orange.shade600, size: 16),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Floating action buttons widget dengan toggle tracking list
class MapFloatingButtons extends StatelessWidget {
  final LatLng? currentPosition;
  final Map<String, LatLng> userLocations;
  final bool autoFollowEnabled;
  final bool isManuallyControlled;
  final bool useAStarRouting;
  final bool showTrackingList;
  final VoidCallback onMyLocation;
  final VoidCallback onFitAll;
  final VoidCallback onToggleTrackingList;

  const MapFloatingButtons({
    Key? key,
    required this.currentPosition,
    required this.userLocations,
    required this.autoFollowEnabled,
    required this.isManuallyControlled,
    required this.useAStarRouting,
    required this.showTrackingList,
    required this.onMyLocation,
    required this.onFitAll,
    required this.onToggleTrackingList,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bottomOffset = userLocations.isNotEmpty && showTrackingList ?
    (MediaQuery.of(context).size.height * 0.4 + 32) : 32.0;

    return Positioned(
      bottom: bottomOffset,
      right: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // My Location Button
          if (currentPosition != null)
            Container(
              margin: EdgeInsets.only(bottom: 12),
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: autoFollowEnabled && !isManuallyControlled
                          ? [Colors.green.shade400, Colors.green.shade600]
                          : [Colors.grey.shade400, Colors.grey.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onMyLocation,
                      borderRadius: BorderRadius.circular(28),
                      child: Icon(Icons.my_location_rounded, color: Colors.white, size: 24),
                    ),
                  ),
                ),
              ),
            ),

          // Fit All Button
          Container(
            margin: EdgeInsets.only(bottom: userLocations.isNotEmpty ? 12 : 0),
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(28),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: useAStarRouting
                        ? [Colors.green.shade500, Colors.green.shade700]
                        : [Colors.blue.shade500, Colors.blue.shade700],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onFitAll,
                    borderRadius: BorderRadius.circular(28),
                    child: Icon(
                      userLocations.isNotEmpty ? Icons.zoom_out_map_rounded : Icons.location_searching_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Toggle Tracking List Button - Pindah ke bawah
          if (userLocations.isNotEmpty)
            Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(28),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: showTrackingList
                        ? [Colors.lightBlue.shade400, Colors.lightBlue.shade600]
                        : [Colors.grey.shade400, Colors.grey.shade600],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: showTrackingList ? Colors.lightBlue.shade200 : Colors.grey.shade300,
                    width: 2,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onToggleTrackingList,
                    borderRadius: BorderRadius.circular(28),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.people_rounded, // Sama dengan icon di tracking list header
                          color: Colors.white,
                          size: 24,
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: showTrackingList ? Colors.orange.shade600 : Colors.grey.shade600,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${userLocations.length}',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}