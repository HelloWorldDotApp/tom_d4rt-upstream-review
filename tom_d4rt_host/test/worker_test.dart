/// The worker body, driven without an isolate: the program cache, the
/// interpreter pool, per-run state, output capture, the error report and the
/// application's channel.
library;

import 'package:test/test.dart';
import 'package:tom_d4rt_host/tom_d4rt_host.dart';

import 'support/fixture_delegate.dart';

/// A worker over [FixtureDelegate] and the messages it sent, oldest first.
(D4rtWorker<Object?>, FixtureDelegate, List<List<Object?>>) worker() {
  final sent = <List<Object?>>[];
  final delegate = FixtureDelegate();
  return (D4rtWorker<Object?>(sent.add, delegate), delegate, sent);
}

List<Map<Object?, Object?>> dones(List<List<Object?>> sent) => [
  for (final m in sent)
    if (m[0] == D4rtWorkerMessage.done) m[2]! as Map<Object?, Object?>,
];

void main() {
  group('HOST-W1 the program cache', () {
    test('HOST-W1-1: the second run of one source does not parse', () {
      final (w, _, sent) = worker();
      const source = 'int main() => 41 + 1;';
      w.serve(fixtureRequest(source));
      w.serve(fixtureRequest(source));
      expect(w.programs.parseCount, 1);
      expect([for (final d in dones(sent)) d['value']], [42, 42]);
      expect([for (final d in dones(sent)) d['parsed']], [true, false]);
    });

    test('HOST-W1-2: an edit invalidates exactly the edited source', () {
      final (w, _, _) = worker();
      for (final n in [1, 2, 1, 2]) {
        w.serve(fixtureRequest('int main() => $n;'));
      }
      expect(w.programs.parseCount, 2);
    });

    test('HOST-W1-3: bounded and least-recently-used; a smaller capacity '
        'evicts at once', () {
      final (w, _, _) = worker();
      void runIt(int n, {int capacity = 2}) =>
          w.serve(fixtureRequest('int main() => $n;', capacity: capacity));
      runIt(1);
      runIt(2);
      runIt(1);
      runIt(3); // evicts 2
      expect(w.programs.length, 2);
      runIt(1);
      expect(w.programs.parseCount, 3, reason: '1 was used after 2');
      runIt(2);
      expect(w.programs.parseCount, 4, reason: '2 was evicted');
      for (var n = 10; n < 15; n++) {
        runIt(n, capacity: 32);
      }
      runIt(99, capacity: 1);
      expect(w.programs.length, 1);
    });

    test('HOST-W1-4: a source that does not parse is not cached and is '
        'reported as a parse failure', () {
      final (w, _, sent) = worker();
      const broken = 'int main() { var a = ; }';
      w.serve(fixtureRequest(broken));
      w.serve(fixtureRequest(broken));
      expect(w.programs.parseCount, 2);
      expect(w.programs.length, 0);
      expect(
        [for (final d in dones(sent)) (d['error']! as Map)['kind']],
        [D4rtRunError.parseKind, D4rtRunError.parseKind],
      );
    });

    test('HOST-W1-5: two runs of one cached program share no state', () {
      final (w, _, sent) = worker();
      const source = '''
var counter = 0;
int main() {
  counter = counter + 1;
  return counter;
}
''';
      w.serve(fixtureRequest(source));
      w.serve(fixtureRequest(source));
      expect([for (final d in dones(sent)) d['value']], [1, 1]);
    });
  });

  group('HOST-W2 one interpreter per bridge set', () {
    const greets = '''
import 'package:fixture/greet.dart';
String main() => greeting;
''';

    test('HOST-W2-1: a corpus is reachable only from the interpreter it was '
        'registered in, even after another run registered it', () {
      final (w, delegate, sent) = worker();
      w.serve(fixtureRequest(greets, corpus: 'greet'));
      w.serve(fixtureRequest(greets, corpus: 'none', tag: 'second'));
      final results = dones(sent);
      expect(results[0]['value'], 'hello');
      expect(
        results[1]['status'],
        'failed',
        reason: 'the none interpreter never had the greet corpus',
      );
      expect(delegate.furnished, ['greet', 'none']);
    });

    test('HOST-W2-2: each key is furnished once, however many runs use it', () {
      final (w, delegate, _) = worker();
      for (var i = 0; i < 4; i++) {
        w.serve(fixtureRequest('int main() => $i;', corpus: 'greet'));
      }
      expect(delegate.furnished, ['greet']);
      expect(w.interpreterCount, 1);
    });
  });

  group('HOST-W3 per-run state', () {
    const readsTag = '''
import 'package:fixture/run.dart';
Object? main() => runTag;
''';

    test('HOST-W3-1: a bridge registered once reads each run\'s own state', () {
      final (w, _, sent) = worker();
      w.serve(fixtureRequest(readsTag, tag: 'first'));
      w.serve(fixtureRequest(readsTag, tag: 'second'));
      expect([for (final d in dones(sent)) d['value']], ['first', 'second']);
    });

    test('HOST-W3-2: the run is ended whatever its outcome, so nothing reads '
        'a finished run', () {
      final (w, delegate, sent) = worker();
      w.serve(fixtureRequest('int main() => throw StateError("x");'));
      w.serve(fixtureRequest('int main() => 1;', failBegin: true));
      expect(delegate.ended, 2);
      expect(delegate.current, isNull);
      final second = dones(sent)[1];
      expect(second['status'], 'failed');
      expect((second['error']! as Map)['kind'], 'StateError');
      expect(
        (second['error']! as Map).containsKey('frames'),
        isFalse,
        reason: 'a run that failed before the interpreter has no frames',
      );
    });
  });

  group('HOST-W4 output capture', () {
    test('HOST-W4-1: print, stdout, stderr and the application\'s own sink '
        'arrive as one transcript in the order they happened', () {
      final (w, _, sent) = worker();
      w.serve(
        fixtureRequest('''
import 'dart:io';
import 'package:fixture/run.dart';
void main() {
  print('one');
  stderr.writeln('two');
  note('three');
  stdout.write('four');
}
'''),
      );
      final lines = [
        for (final m in sent)
          if (m[0] == D4rtWorkerMessage.output)
            TomOutputLine.fromMap(m[2]! as Map),
      ];
      expect([for (final l in lines) l.text], ['one', 'two', 'three', 'four']);
      expect(
        [for (final l in lines) l.stream],
        [
          TomOutputStream.stdout,
          TomOutputStream.stderr,
          TomOutputStream.stderr,
          TomOutputStream.stdout,
        ],
      );
      expect(dones(sent).single['droppedLines'], 0);
    });

    test('HOST-W4-2: a runaway that prints is bounded in the worker, and the '
        'drop is counted, not silent', () {
      final (w, _, sent) = worker();
      final extra = 5;
      w.serve(
        fixtureRequest('''
void main() {
  for (var i = 0; i < ${TomOutputTranscript.maxLines + extra}; i++) {
    print('line \$i');
  }
}
'''),
      );
      final outputs = sent.where((m) => m[0] == D4rtWorkerMessage.output);
      expect(outputs.length, TomOutputTranscript.maxLines);
      expect(dones(sent).single['droppedLines'], extra);
    });
  });

  group('HOST-W5 the error report', () {
    test('HOST-W5-1: a thrown error names its type and the frames in the '
        'program that was run', () {
      final (w, _, sent) = worker();
      w.serve(
        fixtureRequest('''
void inner() {
  throw ArgumentError('bad');
}
void main() {
  inner();
}
'''),
      );
      final error = dones(sent).single['error']! as Map;
      expect(error['message'], contains('bad'));
      final frames = [
        for (final f in error['frames']! as List) D4rtFrame.fromMap(f as Map),
      ];
      expect(frames, isNotEmpty);
      expect(frames.first.line, 2);
      expect(frames.first.member, 'inner');
    });

    test('HOST-W5-2: a failure the application recognises is reported in its '
        'words and kind; one it does not is the default', () {
      final (w, _, sent) = worker();
      w.serve(
        fixtureRequest('''
import 'package:fixture/run.dart';
void main() => overrun();
'''),
      );
      final error = dones(sent).single['error']! as Map;
      expect(error['kind'], 'budget');
      expect(error['message'], startsWith('FixtureBudgetException'));
    });
  });

  group('HOST-W6 the channel and the value', () {
    test('HOST-W6-1: a channel message is tagged with its run and sent before '
        'done', () {
      final (w, _, sent) = worker();
      w.serve(
        fixtureRequest('''
import 'package:fixture/run.dart';
void main() {
  post('write', {'n': 1});
  post('write', {'n': 2});
}
''', runId: 'r1'),
      );
      final channel = [
        for (final m in sent)
          if (m[0] == D4rtWorkerMessage.channel) m,
      ];
      expect(channel, [
        [
          D4rtWorkerMessage.channel,
          'r1',
          'write',
          {'n': 1},
        ],
        [
          D4rtWorkerMessage.channel,
          'r1',
          'write',
          {'n': 2},
        ],
      ]);
      expect(sent.last[0], D4rtWorkerMessage.done);
    });

    test('HOST-W6-2: a returned value is made sendable', () {
      expect(d4rtSendable([1, 'a', true, null]), [1, 'a', true, null]);
      expect(d4rtSendable({1: Uri.parse('x:y')}), {'1': 'x:y'});
      expect(d4rtSendable(Duration.zero), Duration.zero.toString());
    });
  });
}
