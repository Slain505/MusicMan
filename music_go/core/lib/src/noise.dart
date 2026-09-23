import 'rng.dart';

/// 2D value noise in [0, 1].
///
/// Uses only +, *, and floor (no sin/cos/pow): IEEE-754 guarantees these give
/// bit-identical results on every platform, so spawn counts never diverge
/// between client and server.
double valueNoise(double x, double y, int seed) {
  final x0 = x.floor(), y0 = y.floor();
  final fx = _smooth(x - x0), fy = _smooth(y - y0);
  double corner(int cx, int cy) => hashInts([cx, cy], seed) / 4294967295.0;
  final top = _lerp(corner(x0, y0), corner(x0 + 1, y0), fx);
  final bottom = _lerp(corner(x0, y0 + 1), corner(x0 + 1, y0 + 1), fx);
  return _lerp(top, bottom, fy);
}

/// Two octaves of value noise, normalized back to [0, 1].
double fractalNoise(double x, double y, int seed) =>
    (valueNoise(x, y, seed) * 2 + valueNoise(x * 2.7, y * 2.7, seed + 1)) / 3;

double _smooth(double t) => t * t * (3 - 2 * t);
double _lerp(double a, double b, double t) => a + (b - a) * t;
