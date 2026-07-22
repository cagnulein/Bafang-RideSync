class PasPid {
  final double kp;
  final double ki;
  final double kd;
  final int minPas;
  final int maxPas;

  double _integral = 0;
  double _prevError = 0;
  DateTime? _prevTime;

  PasPid({
    this.kp = 0.15,
    this.ki = 0.02,
    this.kd = 0.05,
    this.minPas = 0,
    this.maxPas = 9,
  });

  void reset() {
    _integral = 0;
    _prevError = 0;
    _prevTime = null;
  }

  // Positive error → HR above target → increase PAS (more assistance, less effort, HR drops).
  // Negative error → HR below target → decrease PAS (less assistance, more effort, HR rises).
  int update(int currentHr, int targetHrMin, int targetHrMax, int currentPas) {
    final now = DateTime.now();
    final dt = _prevTime == null
        ? 1.0
        : now.difference(_prevTime!).inMilliseconds / 1000.0;
    _prevTime = now;

    final targetHr = (targetHrMin + targetHrMax) / 2.0;
    final error = currentHr - targetHr;

    _integral += error * dt;
    _integral = _integral.clamp(-30.0, 30.0); // anti-windup

    final derivative = dt > 0 ? (error - _prevError) / dt : 0.0;
    _prevError = error;

    final output = kp * error + ki * _integral + kd * derivative;
    final newPas = (currentPas + output.round()).clamp(minPas, maxPas);
    return newPas;
  }
}
