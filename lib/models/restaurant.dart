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

  /// Typed by a person into their own list rather than found by a search:
  /// no distance, and maps search for the name and address instead.
  final bool userEntered;

  /// The person's own note on a spot they typed in.
  final String? note;

  /// False for a notice card in a room's deck: nobody votes on it, and it
  /// never counts toward anyone's progress or the results. Its title and
  /// text arrive as [name] and [address].
  final bool votable;

  /// A photo of the place, only while the server's photos switch is on.
  final String? photoUrl;

  /// What the place serves, in the provider's words, most important first.
  final List<String> foodLabels;

  /// Vegetarian, vegan, halal or kosher, as the listing claims it.
  final List<String> dietary;

  Restaurant({
    required this.id,
    required this.name,
    required this.address,
    required this.distance,
    this.latitude,
    this.longitude,
    this.phone,
    this.website,
    this.userEntered = false,
    this.note,
    this.votable = true,
    this.photoUrl,
    this.foodLabels = const [],
    this.dietary = const [],
  });

  /// A card that sits between places in the deck and only asks to be
  /// passed.
  Restaurant.notice({
    required this.id,
    required String title,
    required String text,
  }) : name = title,
       address = text,
       distance = 0,
       latitude = null,
       longitude = null,
       phone = null,
       website = null,
       userEntered = false,
       note = null,
       votable = false,
       photoUrl = null,
       foodLabels = const [],
       dietary = const [];

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
