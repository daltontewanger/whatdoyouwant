import 'restaurant.dart';

/// One place a person typed into their own list. Nothing in it comes from a
/// provider, so it is never looked up, geocoded or shown with a distance.
class OwnSpot {
  const OwnSpot({
    required this.id,
    required this.name,
    this.address = '',
    this.note = '',
  });

  static const maxSpots = 50;
  static const maxName = 80;
  static const maxAddress = 120;
  static const maxNote = 120;

  final String id;
  final String name;
  final String address;
  final String note;

  OwnSpot copyWith({String? name, String? address, String? note}) => OwnSpot(
    id: id,
    name: name ?? this.name,
    address: address ?? this.address,
    note: note ?? this.note,
  );

  /// Two spots with the same name are the same place, whatever the case or
  /// spacing, so merging lists does not double them up.
  String get matchKey =>
      name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Restaurant toRestaurant() => Restaurant(
    id: id,
    name: name,
    address: address,
    distance: 0,
    userEntered: true,
    note: note.isEmpty ? null : note,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    if (address.isNotEmpty) 'address': address,
    if (note.isNotEmpty) 'note': note,
  };

  /// Null for anything that is not a usable spot.
  static OwnSpot? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || name is! String || name.trim().isEmpty) return null;
    String text(Object? value) => value is String ? value : '';
    return OwnSpot(
      id: id,
      name: name,
      address: text(raw['address']),
      note: text(raw['note']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OwnSpot &&
      other.id == id &&
      other.name == name &&
      other.address == address &&
      other.note == note;

  @override
  int get hashCode => Object.hash(id, name, address, note);
}
