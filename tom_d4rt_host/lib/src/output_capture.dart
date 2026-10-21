/// Everything a run prints, captured into one emitter.
///
/// A script reaches its output three ways, and all three must land in one
/// transcript, in the order they happened:
///
/// * **`print`.** The interpreter's `print` calls Dart's, which goes to
///   `Zone.current.print` — so the run's **zone** captures it.
/// * **`dart:io`'s `stdout` and `stderr`.** A host that grants the interpreter
///   `dart:io` lets a script write there as readily as it prints. Those getters
///   consult `IOOverrides`, so the run installs a [D4rtCapturedStdout] per
///   stream; without it the line would go to a console the user of an
///   application never sees.
/// * **The application's own sinks**, if it bridges any, call the same
///   emitter directly.
///
/// One emitter for every producer is what makes the interleaving a fact rather
/// than a reconstruction.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tom_basics/utilities.dart';

/// Receives one line a run produced.
typedef D4rtOutputEmitter = void Function(TomOutputStream stream, String text);

/// Runs [body] with `print`, `stdout` and `stderr` delivered to [emit].
///
/// Only [body] is wrapped, so the worker's own diagnostics are not swallowed
/// into somebody's transcript.
T d4rtRunCapturing<T>(T Function() body, D4rtOutputEmitter emit) =>
    IOOverrides.runZoned(
      () => runZoned(
        body,
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) =>
              emit(TomOutputStream.stdout, line),
        ),
      ),
      stdout: () => D4rtCapturedStdout(TomOutputStream.stdout, emit),
      stderr: () => D4rtCapturedStdout(TomOutputStream.stderr, emit),
    );

/// `dart:io`'s `stdout` or `stderr`, as a run sees it: the run's transcript,
/// not the application's console.
///
/// It follows a transcript's rule rather than a byte stream's: a transcript is
/// a list of **lines**, so `write` and `writeln` are one line each. Bytes
/// handed to [add] are decoded and split into lines.
class D4rtCapturedStdout implements Stdout {
  D4rtCapturedStdout(this.stream, this._emit);

  final TomOutputStream stream;
  final D4rtOutputEmitter _emit;

  @override
  Encoding encoding = utf8;

  @override
  String lineTerminator = '\n';

  void _line(String text) => _emit(stream, text);

  @override
  void write(Object? object) => _line('$object');

  @override
  void writeln([Object? object = '']) => _line('$object');

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _line(objects.map((o) => '$o').join(separator));

  @override
  void writeCharCode(int charCode) => _line(String.fromCharCode(charCode));

  @override
  void add(List<int> data) {
    final text = encoding.decode(data);
    const LineSplitter().convert(text).forEach(_line);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) => _line('$error');

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.forEach(add);

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> get done => Future.value();

  /// Not a terminal: the transcript is shown by the application.
  @override
  bool get hasTerminal => false;

  @override
  bool get supportsAnsiEscapes => false;

  @override
  int get terminalColumns =>
      throw const StdoutException('the run transcript is not a terminal');

  @override
  int get terminalLines =>
      throw const StdoutException('the run transcript is not a terminal');

  @override
  IOSink get nonBlocking => this;
}
