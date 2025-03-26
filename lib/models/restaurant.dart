class Restaurant {
  final String id;
  final String name;
  final String address;
  final double rating;
  final double distance; // distance in kilometers, for example

  Restaurant({
    required this.id,
    required this.name,
    required this.address,
    required this.rating,
    required this.distance,
  });

  factory Restaurant.fromJson(Map<String, dynamic> json) {
    return Restaurant(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String,
      rating: (json['rating'] as num).toDouble(),
      distance: (json['distance'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'rating': rating,
      'distance': distance,
    };
  }
}
