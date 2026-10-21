/// One interpreter per set of registered bridges.
library;

import 'package:tom_d4rt/d4rt.dart';

/// Interpreters keyed by the set of bridges registered in them, each
/// furnished on first use.
///
/// Keyed by the set rather than pooled, because a registered bridge corpus
/// cannot be withdrawn: an interpreter that has seen a library resolves it for
/// every later program, including one that was meant to be denied it. A few
/// instances is the cheap way to keep "which libraries a program can import" a
/// fact about that program. The key must therefore name **every** gated corpus
/// — keying on one flag would hand a run a corpus an earlier run registered.
class D4rtInterpreterPool<K> {
  D4rtInterpreterPool(this._furnish);

  /// Registers what an interpreter for [key] must have — bridges, grants —
  /// into a fresh [D4rt].
  final void Function(D4rt interpreter, K key) _furnish;

  final Map<K, D4rt> _interpreters = {};

  /// How many interpreters have been furnished.
  int get length => _interpreters.length;

  /// The interpreter for [key], furnished on first use.
  D4rt obtain(K key) => _interpreters.putIfAbsent(key, () {
    final fresh = D4rt();
    _furnish(fresh, key);
    return fresh;
  });

  /// Releases what the interpreter for [key] retains of its last run.
  ///
  /// A resident `D4rt` pins its last run's parsed unit, visitor and
  /// script-declared environment for the life of the instance — exactly what
  /// `D4rt.dispose` releases. It keeps the registered bridges and the bound
  /// module environments, so the next run on this interpreter pays nothing for
  /// it; and it does not touch a [D4rtProgramCache], whose programs hold their
  /// own units.
  void release(K key) => _interpreters[key]?.dispose();
}
