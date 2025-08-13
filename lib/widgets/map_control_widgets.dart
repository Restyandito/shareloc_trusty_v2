import 'package:flutter/material.dart';

/// Top control bar widget
class MapTopControlBar extends StatelessWidget {
  final bool hasValidLocation;
  final bool autoFollowEnabled;
  final bool isManuallyControlled;
  final bool vibrationEnabled;
  final bool useAStarRouting;
  final VoidCallback onToggleAutoFollow;
  final VoidCallback onToggleVibration;
  final VoidCallback onToggleRouting;
  final VoidCallback onRefresh;

  const MapTopControlBar({
    Key? key,
    required this.hasValidLocation,
    required this.autoFollowEnabled,
    required this.isManuallyControlled,
    required this.vibrationEnabled,
    required this.useAStarRouting,
    required this.onToggleAutoFollow,
    required this.onToggleVibration,
    required this.onToggleRouting,
    required this.onRefresh,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 16,
      right: 80,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildControlButton(
                icon: autoFollowEnabled
                    ? (isManuallyControlled ? Icons.pause_circle_filled : Icons.my_location)
                    : Icons.location_disabled,
                label: autoFollowEnabled
                    ? (isManuallyControlled ? 'Pause' : 'Follow')
                    : 'Manual',
                color: autoFollowEnabled
                    ? (isManuallyControlled ? Colors.orange : Colors.green)
                    : Colors.grey,
                onTap: onToggleAutoFollow,
              ),
            ),
            Container(width: 1, height: 24, color: Colors.grey.shade200),
            Expanded(
              child: _buildControlButton(
                icon: vibrationEnabled ? Icons.vibration : Icons.phone_android,
                label: vibrationEnabled ? 'Vibrate' : 'Silent',
                color: vibrationEnabled ? Colors.purple.shade600 : Colors.grey,
                onTap: onToggleVibration,
              ),
            ),
            Container(width: 1, height: 24, color: Colors.grey.shade200),
            Expanded(
              child: _buildControlButton(
                icon: useAStarRouting ? Icons.route : Icons.timeline,
                label: useAStarRouting ? 'Smart' : 'Basic',
                color: useAStarRouting ? Colors.green.shade600 : Colors.blue,
                onTap: onToggleRouting,
              ),
            ),
            Container(width: 1, height: 24, color: Colors.grey.shade200),
            Expanded(
              child: _buildControlButton(
                icon: Icons.refresh,
                label: 'Refresh',
                color: Colors.blue.shade600,
                onTap: onRefresh,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Debug button widget
class MapDebugButton extends StatelessWidget {
  final bool debugMode;
  final VoidCallback onToggle;

  const MapDebugButton({
    Key? key,
    required this.debugMode,
    required this.onToggle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      right: 8,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: debugMode
                  ? [Colors.red.shade400, Colors.red.shade600]
                  : [Colors.green.shade400, Colors.green.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: debugMode ? Colors.red.shade200 : Colors.green.shade200,
              width: 2,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(28),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.bug_report_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  if (debugMode)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.yellow,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.yellow.withOpacity(0.6),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}