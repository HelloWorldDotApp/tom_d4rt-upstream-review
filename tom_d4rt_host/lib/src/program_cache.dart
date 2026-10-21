/// Parsed programs, kept so an unmodified source is not parsed again.
library;

import 'package:tom_d4rt/d4rt.dart';

/// A bounded, least-recently-used cache of [D4rtProgram]s keyed by a hash of
/// their source.
///
/// A [D4rtProgram] carries only syntax and holds no interpreter state, so one
/// entry serves every interpreter, and two runs of it share nothing —
/// `executeProgram` rebuilds the declarations and the environment. The cache
/// lives as long as its owner and is never persisted: a worker that is
/// discarded discards its cache with it.
class D4rtProgramCache {
  /// The capacity used when a caller states none.
  static const defaultCapacity = 32;

  final Map<String, D4rtProgram> _programs = {};

  /// How many times this cache has called `D4rt.parse`.
  ///
  /// The observable form of "an unmodified source is not parsed again": one
  /// source run twice reads 1. Counts attempts, so a source that fails to
  /// parse — and is therefore not cached — counts every time.
  int get parseCount => _parseCount;
  int _parseCount = 0;

  /// How many programs the cache holds now.
  int get length => _programs.length;

  /// The program for [source], parsed with [interpreter] on a miss, and
  /// whether this call parsed it.
  ///
  /// [capacity] bounds the cache from this call on — it may shrink between
  /// calls, and the bound holds from the call that says so. Values below one
  /// are read as one. A source that does not parse throws here and is not
  /// cached.
  (D4rtProgram, bool) obtain(
    D4rt interpreter, {
    required String sourceHash,
    required String source,
    int capacity = defaultCapacity,
  }) {
    final bound = capacity < 1 ? 1 : capacity;
    final hit = _programs.remove(sourceHash);
    if (hit != null) {
      // Re-inserted at the end: a `LinkedHashMap` iterates in insertion order,
      // so the first key is always the least recently used.
      _programs[sourceHash] = hit;
      _evictTo(bound);
      return (hit, false);
    }
    _parseCount++;
    final program = interpreter.parse(source);
    _programs[sourceHash] = program;
    _evictTo(bound);
    return (program, true);
  }

  void _evictTo(int capacity) {
    while (_programs.length > capacity) {
      _programs.remove(_programs.keys.first);
    }
  }
}
