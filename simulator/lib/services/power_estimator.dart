import 'dart:math';

/// Estimates cycling power using standard road-load physics.
///
/// Model: P_total = P_gravity + P_rolling + P_aero
///   P_gravity  = m * g * sin(θ) * v
///   P_rolling  = Crr * m * g * cos(θ) * v   (Crr = 0.005)
///   P_aero     = 0.5 * CdA * ρ * v³          (CdA = 0.50 m², ρ = 1.225 kg/m³)
///
/// P_rider = max(0, P_total / drivetrain_eff - P_motor)
class PowerEstimator {
  static const double _g = 9.81;
  static const double _crr = 0.005;
  static const double _cda = 0.50;
  static const double _rho = 1.225;
  static const double _eff = 0.95;

  static double totalPowerW({
    required double speedKmh,
    required double gradientPct,
    required double totalMassKg,
  }) {
    if (speedKmh <= 0) return 0;
    final v = speedKmh / 3.6;
    final grade = gradientPct / 100.0;
    final theta = atan(grade);
    final pGravity = totalMassKg * _g * sin(theta) * v;
    final pRolling = _crr * totalMassKg * _g * cos(theta) * v;
    final pAero = 0.5 * _cda * _rho * v * v * v;
    return (pGravity + pRolling + pAero) / _eff;
  }

  static int riderPowerW({
    required double speedKmh,
    required double gradientPct,
    required double totalMassKg,
    required int motorWatts,
  }) {
    final total = totalPowerW(
      speedKmh: speedKmh,
      gradientPct: gradientPct,
      totalMassKg: totalMassKg,
    );
    return (total - motorWatts).clamp(0, 9999).round();
  }
}
