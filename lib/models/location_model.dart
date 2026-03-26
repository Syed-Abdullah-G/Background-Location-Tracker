import 'package:cloud_firestore/cloud_firestore.dart';

class LocationModel {
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  LocationModel({required this.latitude, required this.longitude, required this.timestamp});

  Map<String, dynamic> toMap(String uid) {
    return {'uid': uid, 'latitude': latitude, 'longitude': longitude, 'timestamp': Timestamp.fromDate(timestamp)};
  }
}
