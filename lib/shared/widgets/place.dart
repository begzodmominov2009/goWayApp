class Place {
  final String name;
  final String address;
  final double lat;
  final double lng;
  final double? distanceKm;

  Place({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    this.distanceKm,
  });
}