/// Model untuk distance notification
class DistanceNotification {
  final String userId;
  final String userName;
  final double distance;
  final DateTime timestamp;

  const DistanceNotification({
    required this.userId,
    required this.userName,
    required this.distance,
    required this.timestamp,
  });

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'userName': userName,
      'distance': distance,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Create from JSON
  factory DistanceNotification.fromJson(Map<String, dynamic> json) {
    return DistanceNotification(
      userId: json['userId'] as String,
      userName: json['userName'] as String,
      distance: (json['distance'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  /// Create a copy with updated fields
  DistanceNotification copyWith({
    String? userId,
    String? userName,
    double? distance,
    DateTime? timestamp,
  }) {
    return DistanceNotification(
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      distance: distance ?? this.distance,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Get formatted distance string
  String get formattedDistance {
    if (distance < 1000) {
      return '${distance.round()}m';
    } else {
      return '${(distance / 1000).toStringAsFixed(1)}km';
    }
  }

  /// Check if notification is still valid (not too old)
  bool isValid({Duration maxAge = const Duration(minutes: 5)}) {
    return DateTime.now().difference(timestamp) <= maxAge;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DistanceNotification &&
        other.userId == userId &&
        other.userName == userName &&
        other.distance == distance &&
        other.timestamp == timestamp;
  }

  @override
  int get hashCode {
    return userId.hashCode ^
    userName.hashCode ^
    distance.hashCode ^
    timestamp.hashCode;
  }

  @override
  String toString() {
    return 'DistanceNotification(userId: $userId, userName: $userName, distance: ${formattedDistance}, timestamp: $timestamp)';
  }
}