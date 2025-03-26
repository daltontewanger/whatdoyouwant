class RoomSettings {
  final double searchRadius; // in miles
  final int maxOptions;

  RoomSettings({
    required this.searchRadius,
    required this.maxOptions,
  });

  factory RoomSettings.fromJson(Map<String, dynamic> json) {
    return RoomSettings(
      searchRadius: (json['searchRadius'] as num).toDouble(),
      maxOptions: json['maxOptions'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'searchRadius': searchRadius,
      'maxOptions': maxOptions,
    };
  }
}
