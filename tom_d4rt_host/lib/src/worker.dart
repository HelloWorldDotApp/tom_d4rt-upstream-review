/// The far side of the port: a resident worker that serves runs one at a time.
///
/// ## Why it is resident
///
/// The isolate outlives a run and serves many. Spawned per run, it would throw
/// away everything the interpreter had built the moment the run ended — and the
/// *spawn* is not what that costs. Measured on a 6.4 kB script: a bare
/// `Isolate.spawn` + round trip + kill is 0.2–0.6 ms, while a run against a
/// **fresh** interpreter is 7–8.6 ms against 3.5–5 ms for a resident one.
///
/// Residency costs two things, and both are answered here:
///
/// * **One interpreter per bridge set** ([D4rtInterpreterPool]). A registered
///   corpus cannot be withdrawn.
/// * **Per-run state must be repointed per run.** Bridges are registered once,
///   so whatever they read has to be a slot the application's delegate fills
///   in [D4rtWorkerDelegate.begin] and empties in [D4rtWorkerDelegate.end] —
///   a value captured at registration would make every later run read the
///   first run's state.
///
/// What residency cannot survive is a runaway: `D4rt.execute` is synchronous,
/// so a worker running away cannot service a stop message, and the only way to
/// end it is to kill the isolate. The host does that on a timeout, a
/// cancellation, a refused message or a death; the next run spawns a fresh
/// worker.
library;

import 'dart:isolate';

import 'package:tom_basics/utilities.dart';
import 'package:tom_d4rt/d4rt.dart';

import 'interpreter_pool.dart';
import 'output_capture.dart';
import 'program_cache.dart';
import 'run_protocol.dart';

/// A failure the application recognises, with the words and kind it wants
/// reported.
class D4rtWorkerFailure {
  final String message;
  final String kind;

  /// Whether the interpreter's frames belong with it. False for a failure
  /// raised outside any interpreted frame, where the interpreter's last trace
  /// describes an earlier error.
  final bool withFrames;

  const D4rtWorkerFailure(
    this.message, {
    required this.kind,
    this.withFrames = true,
  });
}

/// One run, as the application's delegate sees it inside the worker.
class D4rtWorkerRun {
  D4rtWorkerRun._(this.request, this._send, this._emit);

  final D4rtRunRequest request;
  final void Function(List<Object?> message) _send;
  final D4rtOutputEmitter _emit;

  String get runId => request.runId;

  /// The application's own part of the request.
  Map<String, Object?> get payload => request.payload;

  /// Sends one message on the application's channel. The host hands it to the
  /// run's message handler, in order, tagged with this run.
  void send(String tag, Object? data) =>
      _send([D4rtWorkerMessage.channel, request.runId, tag, data]);

  /// Adds one line to the run's transcript — for the application's own output
  /// sinks; `print`, `stdout` and `stderr` are captured already.
  void emit(TomOutputStream stream, String text) => _emit(stream, text);
}

/// What an application supplies to the worker: its bridges and its per-run
/// state.
///
/// [K] identifies an interpreter by the bridge corpora registered in it.
abstract class D4rtWorkerDelegate<K> {
  /// Prepares [run]: fills whatever the registered bridges read. Called before
  /// the interpreter is obtained; a throw fails the run.
  void begin(D4rtWorkerRun run);

  /// The interpreter [run] must use — the set of corpora it is granted.
  K interpreterKey(D4rtWorkerRun run);

  /// Registers what an interpreter for [key] must have into a fresh one.
  /// Called once per key, for the life of the worker.
  void furnish(D4rt interpreter, K key);

  /// Ends [run], whatever its outcome — so a resident interpreter does not pin
  /// the previous run's state, and a stray access between runs fails loudly.
  void end(D4rtWorkerRun run);

  /// A failure the application recognises, or null for the default report
  /// (the message, and the runtime type as the kind).
  D4rtWorkerFailure? recognise(Object error) => null;
}

/// Makes the application's delegate inside the worker isolate. Must be a
/// top-level or static function, because it crosses `Isolate.spawn`.
typedef D4rtWorkerDelegateFactory = D4rtWorkerDelegate<Object?> Function();

/// The worker isolate's entry point: `[toHost, delegateFactory]`.
///
/// Announces itself with [D4rtWorkerMessage.ready] carrying the port the host
/// posts requests on, then serves them one at a time until the isolate is
/// killed.
void d4rtWorkerMain(List<Object?> payload) {
  final toHost = payload[0]! as SendPort;
  final factory = payload[1]! as D4rtWorkerDelegateFactory;
  final requests = ReceivePort();
  final worker = D4rtWorker(toHost.send, factory());
  toHost.send([D4rtWorkerMessage.ready, requests.sendPort]);
  requests.listen((message) {
    worker.serve(D4rtRunRequest.fromMap(message as Map));
  });
}

/// The worker body, with the port abstracted to a callback.
///
/// A class because residency is state: the interpreters and the program
/// cache. Separate from [d4rtWorkerMain] so a test can drive it without an
/// isolate.
class D4rtWorker<K> {
  D4rtWorker(this._send, this._delegate)
    : _pool = D4rtInterpreterPool<K>(_delegate.furnish);

  final void Function(List<Object?> message) _send;
  final D4rtWorkerDelegate<K> _delegate;
  final D4rtInterpreterPool<K> _pool;

  /// The parsed programs this worker keeps.
  final D4rtProgramCache programs = D4rtProgramCache();

  /// How many interpreters the worker has furnished.
  int get interpreterCount => _pool.length;

  /// Runs one request and reports its outcome. Never throws: a program's
  /// failure is a value, and a throw here would kill the worker and its
  /// residency with it.
  void serve(D4rtRunRequest request) {
    Object? value;
    Map<String, Object?>? error;
    var status = D4rtRunStatus.ok;
    var parsed = false;
    D4rt? interpreter;
    K? key;

    // Bounded **here** rather than at the host: a runaway loop that prints
    // would flood the port long before the host could drop anything.
    final recorder = TomOutputRecorder();
    void emit(TomOutputStream stream, String text) {
      final line = recorder.add(stream, text);
      if (line == null) return;
      _send([D4rtWorkerMessage.output, request.runId, line.toMap()]);
    }

    final run = D4rtWorkerRun._(request, _send, emit);
    try {
      _delegate.begin(run);
      key = _delegate.interpreterKey(run);
      final furnished = _pool.obtain(key as K);
      interpreter = furnished;
      final (program, didParse) = programs.obtain(
        furnished,
        sourceHash: request.sourceHash,
        source: request.source,
        capacity: request.programCacheCapacity,
      );
      parsed = didParse;
      value = d4rtSendable(
        d4rtRunCapturing(
          () => furnished.executeProgram(
            program,
            name: request.entryPoint,
            positionalArgs: request.arguments,
          ),
          emit,
        ),
      );
    } on SourceCodeD4rtException catch (e) {
      status = D4rtRunStatus.failed;
      error = {'message': e.toString(), 'kind': D4rtRunError.parseKind};
    } catch (e) {
      status = D4rtRunStatus.failed;
      final recognised = _delegate.recognise(e);
      final frames = recognised == null || recognised.withFrames
          ? _frames(interpreter)
          : null;
      error = {
        'message': recognised?.message ?? e.toString(),
        'kind': recognised?.kind ?? e.runtimeType.toString(),
        'frames': ?frames,
      };
    } finally {
      _delegate.end(run);
      if (key != null) _pool.release(key as K);
    }

    _send([
      D4rtWorkerMessage.done,
      request.runId,
      {
        'status': status.name,
        'value': value,
        'error': ?error,
        'droppedLines': recorder.droppedLines,
        'parsed': parsed,
      },
    ]);
  }
}

/// [value] made sendable across a port: primitives and collections of them
/// pass through, anything else — an interpreted instance, a bridged handle, a
/// closure — is its `toString()`, which is what a caller on the far side can
/// use.
Object? d4rtSendable(Object? value) {
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  if (value is List) return [for (final entry in value) d4rtSendable(entry)];
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): d4rtSendable(entry.value),
    };
  }
  return value.toString();
}

/// The frames of the error that just left [interpreter], innermost first, as
/// port-ready maps — or null when it reported none.
///
/// Only frames in the **main program** (an unnamed source) are positions in
/// the program the caller ran; a frame in an imported library is a line in
/// somebody else's file.
List<Map<String, Object?>>? _frames(D4rt? interpreter) {
  if (interpreter == null) return null;
  final frames = [
    for (final frame in interpreter.lastErrorTrace)
      if (frame.source == null)
        D4rtFrame(
          line: frame.line,
          column: frame.column,
          member: frame.member,
        ).toMap(),
  ];
  return frames.isEmpty ? null : frames;
}
