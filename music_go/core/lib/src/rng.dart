/// Deterministic 32-bit hashing and RNG.
///
/// Every player and the server must derive *exactly* the same spawns from the
/// same inputs. On the web Dart ints are JS doubles, so a plain 64-bit
/// multiply silently loses precision. Everything here stays inside 32 bits
/// and multiplies via 16-bit halves, which gives identical results on the
/// Dart VM, dart2js and dart2wasm.
library;

const int _mask32 = 0xFFFFFFFF;

/// 32-bit multiply modulo 2^32 (like JavaScript's `Math.imul`, but unsigned).
int imul32(int a, int b) {
  a &= _mask32;
  b &= _mask32;
  final aHi = (a >> 16) & 0xFFFF, aLo = a & 0xFFFF;
  final bHi = (b >> 16) & 0xFFFF, bLo = b & 0xFFFF;
  final cross = ((aHi * bLo + aLo * bHi) & 0xFFFF) << 16;
  return (aLo * bLo + cross) & _mask32;
}

/// MurmurHash3 finalizer: good avalanche for a single 32-bit value.
int mix32(int h) {
  h &= _mask32;
  h ^= h >> 16;
  h = imul32(h, 0x85ebca6b);
  h ^= h >> 13;
  h = imul32(h, 0xc2b2ae35);
  h ^= h >> 16;
  return h;
}

/// Hashes a list of (possibly negative) ints into an unsigned 32-bit value.
int hashInts(List<int> values, [int seed = 0]) {
  var h = seed & _mask32;
  for (final v in values) {
    h = mix32(h ^ (v & _mask32));
    h = (imul32(h, 5) + 0xe6546b64) & _mask32;
  }
  return mix32(h ^ values.length);
}

/// Mulberry32: tiny, fast, good enough for game content.
class Rng {
  Rng(int seed) : _state = seed & _mask32;

  int _state;

  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & _mask32;
    var t = _state;
    t = imul32(t ^ (t >> 15), t | 1);
    t ^= (t + imul32(t ^ (t >> 7), t | 61)) & _mask32;
    return (t ^ (t >> 14)) & _mask32;
  }

  /// Uniform double in [0, 1).
  double nextDouble() => nextUint32() / 4294967296.0;

  /// Uniform int in [0, max).
  int nextInt(int max) => (nextDouble() * max).floor();
}
