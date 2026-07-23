class PasLevelConfig {
  int motorWatts;
  double maxSpeedKmh;

  PasLevelConfig({required this.motorWatts, this.maxSpeedKmh = 99});

  static List<PasLevelConfig> defaults() => [
    PasLevelConfig(motorWatts: 0),
    PasLevelConfig(motorWatts: 75),
    PasLevelConfig(motorWatts: 130),
    PasLevelConfig(motorWatts: 185),
    PasLevelConfig(motorWatts: 245),
    PasLevelConfig(motorWatts: 300),
    PasLevelConfig(motorWatts: 360),
    PasLevelConfig(motorWatts: 400),
    PasLevelConfig(motorWatts: 450),
    PasLevelConfig(motorWatts: 500),
  ];
}
