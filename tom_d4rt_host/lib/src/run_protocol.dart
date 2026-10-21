/// What crosses the port between a [D4rtHost] and its worker.
library;

import 'package:tom_basics/utilities.dart';

import 'program_cache.dart';

/// Message tags on the worker → host port.
///
/// Strings rather than an enum because the value crosses an isolate boundary
/// and would have to be encoded anyway; naming them here keeps the two ends
/// from drifting. Every message after [ready] carries the run id second.
abstract final class D4rtWorkerMessage {
  /// The worker is up. Payload: its own `SendPort`, on which the host posts
  /// requests. Sent exactly once, before any run.
  static const ready = 'ready';

  /// One line the run wrote, as `TomOutputLine.toMap()`. Sent as it happens,
  /// so the host can show output while the run is in flight.
  static const output = 'output';

  /// One application message, `[channel, runId, tag, data]` — the
  /// application's own channel through the worker (for example the writes a
  /// script makes to a document).
  static const channel = 'channel';

  /// The run finished. Payload: `{status, value, error, droppedLines,
  /// parsed}`.
  static const done = 'done';
}

/// One run, as sendable primitives.
class D4rtRunRequest {
  /// The run this request belongs to.
  ///
  /// Every message the worker sends back is tagged with it, because a resident
  /// worker's port is shared across runs and a message from a run the host has
  /// given up on must not reach whatever is running now.
  final String runId;

  final String source;

  /// A hash of [source] — the parsed-program cache key. The caller computes
  /// it, so "which program" means one thing on both sides of the port.
  final String sourceHash;

  /// The function the run calls.
  final String entryPoint;

  /// Its positional arguments; sendable values only.
  final List<Object?> arguments;

  /// How many parsed programs the worker's cache may hold from this run on.
  final int programCacheCapacity;

  /// The application's own part of the request, handed to its
  /// [D4rtWorkerDelegate] unchanged. Sendable values only.
  final Map<String, Object?> payload;

  const D4rtRunRequest({
    required this.runId,
    required this.source,
    required this.sourceHash,
    this.entryPoint = 'main',
    this.arguments = const [],
    this.programCacheCapacity = D4rtProgramCache.defaultCapacity,
    this.payload = const {},
  });

  Map<String, Object?> toMap() => {
    'runId': runId,
    'source': source,
    'sourceHash': sourceHash,
    'entryPoint': entryPoint,
    'arguments': arguments,
    'programCacheCapacity': programCacheCapacity,
    'payload': payload,
  };

  static D4rtRunRequest fromMap(Map<Object?, Object?> map) => D4rtRunRequest(
    runId: map['runId']! as String,
    source: map['source']! as String,
    sourceHash: map['sourceHash']! as String,
    entryPoint: map['entryPoint']! as String,
    arguments: List<Object?>.from(map['arguments']! as List),
    programCacheCapacity: map['programCacheCapacity']! as int,
    payload: Map<String, Object?>.from(map['payload']! as Map),
  );
}

/// How a run ended.
enum D4rtRunStatus {
  /// The entry point returned.
  ok,

  /// The program failed: it did not parse, threw, the application refused it,
  /// or the worker died.
  failed,

  /// It ran past its deadline and the worker was killed.
  timedOut,

  /// It was cancelled and the worker was killed.
  cancelled,
}

/// One frame of the interpreter's call stack, in the program that was run.
class D4rtFrame {
  final int line;
  final int column;

  /// The function the frame is in, when the interpreter named one.
  final String? member;

  const D4rtFrame({required this.line, required this.column, this.member});

  Map<String, Object?> toMap() => {
    'line': line,
    'column': column,
    'member': ?member,
  };

  static D4rtFrame fromMap(Map<Object?, Object?> map) => D4rtFrame(
    line: map['line']! as int,
    column: map['column']! as int,
    member: map['member'] as String?,
  );

  @override
  String toString() =>
      member == null ? '$line:$column' : '$member ($line:$column)';
}

/// Why a run did not end with [D4rtRunStatus.ok].
class D4rtRunError {
  /// The kind of a source that did not parse.
  static const parseKind = 'parse';

  /// The kind of a run that ran past its deadline.
  static const timeoutKind = 'timeout';

  /// The kind of a run that was cancelled.
  static const cancelledKind = 'cancelled';

  /// The kind of a run whose worker isolate failed or exited.
  static const isolateKind = 'isolate';

  /// The kind of a run whose application refused a channel message.
  static const rejectedKind = 'rejected';

  final String message;

  /// [parseKind], [timeoutKind], [cancelledKind], [isolateKind],
  /// [rejectedKind], a kind the application's delegate named, or the runtime
  /// type of what the program threw.
  final String kind;

  /// The interpreter's frames in the program that was run, innermost first —
  /// empty when it reported none.
  final List<D4rtFrame> frames;

  /// What the application's channel handler threw, for [rejectedKind]. Held
  /// on the host side only; it never crosses the port.
  final Object? cause;

  const D4rtRunError(
    this.message, {
    required this.kind,
    this.frames = const [],
    this.cause,
  });

  @override
  String toString() => '$kind: $message';
}

/// The result of one run.
class D4rtRunOutcome {
  final D4rtRunStatus status;

  /// What the entry point returned, made sendable: primitives and collections
  /// of them pass through, anything else is its `toString()`.
  final Object? value;

  /// Why it failed; null when [status] is [D4rtRunStatus.ok].
  final D4rtRunError? error;

  /// What the run printed, bounded in the worker.
  final TomOutputTranscript transcript;

  /// Whether the worker parsed the source for this run rather than taking it
  /// from its cache. False for a run that never reached the parse.
  final bool parsed;

  /// Whether the host killed the worker because of this run. True when the
  /// run was abandoned while the interpreter was still executing — a timeout,
  /// a cancellation, a refused channel message — or when the worker died.
  final bool abandonedWorker;

  const D4rtRunOutcome({
    required this.status,
    this.value,
    this.error,
    this.transcript = TomOutputTranscript.empty,
    this.parsed = false,
    this.abandonedWorker = false,
  });

  bool get isOk => status == D4rtRunStatus.ok;
}
