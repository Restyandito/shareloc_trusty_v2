import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:vibration/vibration.dart';
import '../models/distance_notification.dart';
import '../utils/map_constants.dart';
import 'map_services.dart';

/// Service untuk mengelola notifikasi jarak
class DistanceNotificationService {
  final bool Function() vibrationEnabled;
  final VoidCallback onNotificationUpdate;
  final TickerProvider vsync;
  final LatLng? Function() getCurrentPosition;  // Callback untuk dapat current position
  final Map<String, LatLng> Function() getUserLocations;  // Callback untuk dapat user locations
  final Map<String, String> Function() getUserNames;     // Callback untuk dapat user names

  DistanceNotificationService({
    required this.vibrationEnabled,
    required this.onNotificationUpdate,
    required this.vsync,
    required this.getCurrentPosition,
    required this.getUserLocations,
    required this.getUserNames,
  }) {
    _setupAnimation();
  }

  // State
  List<DistanceNotification> _activeNotifications = [];
  Timer? _notificationTimer;
  AnimationController? _animationController;
  Animation<double>? _animation;
  Map<String, DateTime> _lastNotificationTime = {};
  Map<String, DateTime> _lastVibrationTime = {};

  List<DistanceNotification> get activeNotifications => _activeNotifications;
  Animation<double>? get animation => _animation;

  /// Setup animation controller
  void _setupAnimation() {
    _animationController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: vsync,
    );

    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController!,
      curve: Curves.easeOutBack,
    ));
  }

  /// Start monitoring distance notifications - TANPA PARAMETER
  void startMonitoring() {
    _notificationTimer?.cancel();

    print('🔔 Starting distance monitoring timer (every ${MapConstants.notificationInterval.inSeconds} seconds)');

    // Check immediately when starting
    _checkDistanceNotifications();

    // Start periodic timer
    _notificationTimer = Timer.periodic(MapConstants.notificationInterval, (timer) {
      print('⏰ Timer tick - checking distances...');
      _checkDistanceNotifications();
    });
  }

  /// Stop monitoring
  void stopMonitoring() {
    _notificationTimer?.cancel();
    print('🔔 Distance monitoring stopped');
  }

  /// Check for distance notifications - now gets data from callbacks
  void _checkDistanceNotifications() {
    final currentPosition = getCurrentPosition();
    final userLocations = getUserLocations();
    final userNames = getUserNames();

    if (currentPosition == null || userLocations.isEmpty) {
      print('🔔 Skip check: currentPosition=$currentPosition, users=${userLocations.length}');
      return;
    }

    print('🔔 Checking distance notifications for ${userLocations.length} users from position $currentPosition');

    final now = DateTime.now();
    final farUsers = <DistanceNotification>[];
    bool shouldVibrate = false;

    for (final userId in userLocations.keys) {
      final userLocation = userLocations[userId];
      if (userLocation == null) continue;

      final distance = MapUtils.calculateDistance(currentPosition, userLocation);
      print('📏 Distance to ${userNames[userId] ?? userId}: ${distance.toStringAsFixed(1)}m');

      // Check if user is too far (more than max distance)
      if (distance > MapConstants.maxNotificationDistance) {
        final lastNotified = _lastNotificationTime[userId];

        // ALWAYS notify when timer triggers (every 15 seconds) for far users
        // No need to check notification interval again since timer IS the interval
        print('⚠️ User ${userNames[userId] ?? userId} is too far: ${distance.toStringAsFixed(1)}m - SHOWING NOTIFICATION');

        final userName = userNames[userId] ?? 'User';
        farUsers.add(DistanceNotification(
          userId: userId,
          userName: userName,
          distance: distance,
          timestamp: now,
        ));

        _lastNotificationTime[userId] = now;

        // Check if vibration is needed (still use vibration cooldown)
        if (_shouldVibrate(userId)) {
          shouldVibrate = true;
          _lastVibrationTime[userId] = now;
          print('📳 Will vibrate for $userId');
        } else {
          print('📳 Vibration skipped for $userId (cooldown)');
        }
      } else {
        // Reset timers if user is close again
        if (_lastNotificationTime.containsKey(userId)) {
          print('✅ User ${userNames[userId] ?? userId} is back in range');
          _lastNotificationTime.remove(userId);
          _lastVibrationTime.remove(userId);
        }
      }
    }

    if (farUsers.isNotEmpty) {
      print('🔔 Showing distance notifications for ${farUsers.length} users');
      _activeNotifications = farUsers;
      onNotificationUpdate();

      // Trigger vibration based on number of users
      if (shouldVibrate && vibrationEnabled()) {
        print('📳 Triggering vibration for ${farUsers.length} users');
        if (farUsers.length == 1) {
          _triggerVibration(VibrationPattern.warning);
        } else if (farUsers.length <= 3) {
          _triggerVibration(VibrationPattern.alert);
        } else {
          _triggerVibration(VibrationPattern.alert);
          Future.delayed(Duration(milliseconds: 800), () {
            _triggerVibration(VibrationPattern.gentle);
          });
        }
      }

      // Show notification animation
      _animationController?.reset();
      _animationController?.forward().then((_) {
        // Auto hide after 5 seconds, but keep data for next timer cycle
        Timer(Duration(seconds: 5), () {
          _hideNotificationUI();
        });
      });
    } else {
      // Clear notifications if no far users
      if (_activeNotifications.isNotEmpty) {
        print('✅ All users are within range, clearing notifications');
        _activeNotifications.clear();
        onNotificationUpdate();
      }
    }
  }

  /// Hide notification UI but keep notifications for next cycle
  void _hideNotificationUI() {
    _animationController?.reverse();
    // Don't clear _activeNotifications here, let timer cycle handle it
  }

  /// Check if should vibrate for user
  bool _shouldVibrate(String userId) {
    final now = DateTime.now();
    final lastVibration = _lastVibrationTime[userId];

    // Vibration cooldown hanya 10 detik agar bisa vibrate di setiap cycle notification (15 detik)
    // Jadi akan vibrate: cycle 1 (vibrate), cycle 2 (skip), cycle 3 (vibrate), cycle 4 (skip), dst.
    if (lastVibration != null && now.difference(lastVibration) < Duration(seconds: 10)) {
      return false;
    }

    return true;
  }

  /// Trigger vibration with pattern
  Future<void> _triggerVibration(VibrationPattern pattern) async {
    if (!vibrationEnabled()) return;

    try {
      bool? hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator != true) return;

      switch (pattern) {
        case VibrationPattern.warning:
          await Vibration.vibrate(duration: 200);
          await Future.delayed(Duration(milliseconds: 100));
          await Vibration.vibrate(duration: 200);
          await Future.delayed(Duration(milliseconds: 100));
          await Vibration.vibrate(duration: 500);
          break;

        case VibrationPattern.alert:
          for (int i = 0; i < 3; i++) {
            await Vibration.vibrate(duration: 150);
            if (i < 2) await Future.delayed(Duration(milliseconds: 100));
          }
          break;

        case VibrationPattern.gentle:
          await Vibration.vibrate(duration: 300);
          break;
      }

      HapticFeedback.heavyImpact();
    } catch (e) {
      print('❌ Vibration error: $e');
      HapticFeedback.heavyImpact();
    }
  }

  /// Hide notifications
  void hideNotifications() {
    _animationController?.reverse().then((_) {
      _activeNotifications.clear();
      onNotificationUpdate();
    });
  }

  /// Simulate notification for testing
  void simulateNotification(Map<String, LatLng> userLocations, Map<String, String> userNames) {
    if (userLocations.isNotEmpty) {
      final userId = userLocations.keys.first;
      final userName = userNames[userId] ?? 'Test User';

      _activeNotifications = [
        DistanceNotification(
          userId: userId,
          userName: userName,
          distance: 1500.0, // 1.5km simulation
          timestamp: DateTime.now(),
        )
      ];

      _triggerVibration(VibrationPattern.warning);
      _animationController?.reset();
      _animationController?.forward();
      onNotificationUpdate();

      Timer(Duration(seconds: 3), () {
        hideNotifications();
      });
    }
  }

  /// Dispose resources
  void dispose() {
    _notificationTimer?.cancel();
    _animationController?.dispose();
    _lastNotificationTime.clear();
    _lastVibrationTime.clear();
  }
}