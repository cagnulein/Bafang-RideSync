class PasPid {
  int minPas;
  int maxPas;

  // 1 = very gentle (change every 30s), 10 = aggressive (change every 3s)
  int intensity;

  DateTime? _lastChange;

  PasPid({
    this.minPas = 0,
    this.maxPas = 9,
    this.intensity = 3,
  });

  // Cooldown between PAS changes: intensity 1→30s, 10→3s
  double get _cooldownSeconds => 33.0 - intensity * 3.0;

  // Dead band: bpm outside zone before reacting: intensity 1→5bpm, 10→1bpm
  int get _deadbandBpm => 6 - (intensity / 2.0).round();

  void reset() {
    _lastChange = null;
  }

  // Positive error (HR above target) → increase PAS (more assist → less effort → HR drops).
  // Negative error (HR below target) → decrease PAS (less assist → more effort → HR rises).
  int update(int currentHr, int targetHrMin, int targetHrMax, int currentPas) {
    // Within zone: do nothing
    if (currentHr >= targetHrMin && currentHr <= targetHrMax) return currentPas;

    // Within dead band outside zone: do nothing
    final overMax = currentHr - targetHrMax;
    final underMin = targetHrMin - currentHr;
    if (overMax > 0 && overMax < _deadbandBpm) return currentPas;
    if (underMin > 0 && underMin < _deadbandBpm) return currentPas;

    // Cooldown: don't change faster than allowed
    final now = DateTime.now();
    if (_lastChange != null) {
      final elapsed = now.difference(_lastChange!).inMilliseconds / 1000.0;
      if (elapsed < _cooldownSeconds) return currentPas;
    }

    // Change PAS by exactly 1 level
    final newPas = currentHr > targetHrMax
        ? (currentPas + 1).clamp(minPas, maxPas)
        : (currentPas - 1).clamp(minPas, maxPas);

    if (newPas != currentPas) _lastChange = now;
    return newPas;
  }
}
