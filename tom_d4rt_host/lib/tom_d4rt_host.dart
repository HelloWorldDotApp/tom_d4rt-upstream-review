/// Hosting the D4rt interpreter in an application.
///
/// A [D4rtHost] owns one **resident** worker isolate and serves runs one at a
/// time: the worker keeps one interpreter per set of registered bridges
/// ([D4rtInterpreterPool]) and the programs it has parsed
/// ([D4rtProgramCache]), so an unmodified source is neither re-parsed nor run
/// against a freshly furnished interpreter. A run that outlives its deadline,
/// is cancelled, or has a channel message refused kills the worker; a program
/// that merely fails keeps it. Everything a run prints — `print`, `dart:io`'s
/// `stdout` and `stderr`, and the application's own sinks — lands in one
/// bounded transcript ([TomOutputTranscript], from `tom_basics`).
///
/// The application supplies what is its own through a
/// [D4rtWorkerDelegate]: the bridges it registers, the per-run state they
/// read, and the messages it sends back on its own channel
/// ([D4rtWorkerRun.send], received by the run's [D4rtMessageHandler]).
///
/// A Dart VM library: it spawns isolates and redirects `dart:io`.
library;

export 'package:tom_basics/utilities.dart'
    show
        TomCancellationToken,
        TomOutputLine,
        TomOutputRecorder,
        TomOutputStream,
        TomOutputTranscript;

export 'src/host.dart';
export 'src/interpreter_pool.dart';
export 'src/output_capture.dart';
export 'src/program_cache.dart';
export 'src/run_protocol.dart';
export 'src/worker.dart';
