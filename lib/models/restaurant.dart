class Restaurant {
  final String id;
  final String name;
  final String address;
  final double distance;

  /// The restaurant's own position, phone and website, where the deck has
  /// them. Legacy rooms leave these empty.
  final double? latitude;
  final double? longitude;
  final String? phone;
  final String? website;

  Restaurant({
    required this.id,
    required this.name,
    required this.address,
    required this.distance,
    this.latitude,
    this.longitude,
    this.phone,
    this.website,
  });

  factory Restaurant.fromJson(Map<String, dynamic> json) {
    return Restaurant(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String,
      distance: (json['distance'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'address': address, 'distance': distance};
  }
}
