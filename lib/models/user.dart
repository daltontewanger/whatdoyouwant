import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String id;
  final String name;

  AppUser({
    required this.id,
    required this.name,
  });

  /// Construct from Firestore document snapshot
  factory AppUser.fromDocument(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppUser(
      id: doc.id,
      name: data['name'] as String,
    );
  }

  /// Construct from JSON map
  factory AppUser.fromJson(Map<String, dynamic> json, String id) {
    return AppUser(
      id: id,
      name: json['name'] as String,
    );
  }

  /// Convert to JSON for Firestore write
  Map<String, dynamic> toJson() {
    return {
      'name': name,
    };
  }
}
