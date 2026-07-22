class RecordPoint {
  final DateTime timestamp;
  final double? lat;
  final double? lon;
  final int? hrBpm;
  final double? speedKmh;
  final int? powerWatts;
  final double? cadenceRpm;
  final int? batteryPct;
  final double? distanceKm;
  final int? pas;

  const RecordPoint({
    required this.timestamp,
    this.lat,
    this.lon,
    this.hrBpm,
    this.speedKmh,
    this.powerWatts,
    this.cadenceRpm,
    this.batteryPct,
    this.distanceKm,
    this.pas,
  });
}

class WorkoutRecord {
  final DateTime startTime;
  final List<RecordPoint> points = [];

  Duration get elapsed => points.isEmpty
      ? Duration.zero
      : points.last.timestamp.difference(startTime);

  double get totalDistanceKm => points.isEmpty
      ? 0
      : (points.last.distanceKm ?? 0) - (points.first.distanceKm ?? 0);

  WorkoutRecord({required this.startTime});

  void add(RecordPoint p) => points.add(p);
}
