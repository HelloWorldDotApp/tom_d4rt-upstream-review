/// The host over a real worker isolate: residency, the endings that kill the
/// worker and the one that keeps it, the channel, live output and the queue.
///
/// Each test spawns an isolate; the bound is for one that hangs.
@Timeout(Duration(seconds: 120))
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:tom_basics/utilities.dart' show TomCancellationSource;
import 'package:tom_d4rt_host/tom_d4rt_host.dart';

import 'support/fixture_delegate.dart';

const deadline = Duration(seconds: 30);

D4rtHost newHost() {
  final host = D4rtHost(fixtureDelegate, debugName: 'host-test');
  addTearDown(host.dispose);
  return host;
}

void main() {
  group('HOST-H1 residency', () {
    test('HOST-H1-1: ten runs are served by one worker, and one unmodified '
        'source is parsed once', () async {
      final host = newHost();
      for (var i = 0; i < 10; i++) {
        final outcome = await host.run(
          fixtureRequest('int main() => 7;', runId: 'r$i'),
          deadline: deadline,
        );
        expect(outcome.value, 7);
      }
      expect(host.workerSpawnCount, 1);
      expect(host.programParseCount, 1);
    });

    test('HOST-H1-2: a program that fails keeps the worker', () async {
      final host = newHost();
      final failed = await host.run(
        fixtureRequest('int main() => throw StateError("typo");'),
        deadline: deadline,
      );
      expect(failed.status, D4rtRunStatus.failed);
      expect(failed.abandonedWorker, isFalse);
      final next = await host.run(
        fixtureRequest('int main() => 1;'),
        deadline: deadline,
      );
      expect(next.isOk, isTrue);
      expect(host.workerSpawnCount, 1);
    });
  });

  group('HOST-H2 the endings that kill the worker', () {
    const spins = 'void main() { while (true) {} }';

    test('HOST-H2-1: a run past its deadline is timed out, its worker killed, '
        'and the next run spawns a fresh one', () async {
      final host = newHost();
      final outcome = await host.run(
        fixtureRequest(spins),
        deadline: const Duration(milliseconds: 500),
      );
      expect(outcome.status, D4rtRunStatus.timedOut);
      expect(outcome.error!.kind, D4rtRunError.timeoutKind);
      expect(outcome.abandonedWorker, isTrue);
      final next = await host.run(
        fixtureRequest('int main() => 2;'),
        deadline: deadline,
      );
      expect(next.value, 2);
      expect(host.workerSpawnCount, 2);
    });

    test(
      'HOST-H2-2: a cancellation stops a runaway and states its reason',
      () async {
        final host = newHost();
        final source = TomCancellationSource();
        Timer(const Duration(milliseconds: 300), () => source.cancel('stop'));
        final outcome = await host.run(
          fixtureRequest(spins),
          deadline: deadline,
          cancellation: source.token,
        );
        expect(outcome.status, D4rtRunStatus.cancelled);
        expect(outcome.error!.message, 'stop');
        expect(outcome.abandonedWorker, isTrue);
      },
    );

    test('HOST-H2-3: a channel message the application refuses fails the run '
        'with its cause and kills the worker', () async {
      final host = newHost();
      final outcome = await host.run(
        fixtureRequest('''
import 'package:fixture/run.dart';
void main() {
  post('write', 1);
  while (true) {}
}
'''),
        deadline: deadline,
        onMessage: (tag, data) => throw ArgumentError('not this one'),
      );
      expect(outcome.status, D4rtRunStatus.failed);
      expect(outcome.error!.kind, D4rtRunError.rejectedKind);
      expect(outcome.error!.cause, isA<ArgumentError>());
      expect(outcome.abandonedWorker, isTrue);
      expect(host.workerSpawnCount, 1);
      await host.run(fixtureRequest('int main() => 1;'), deadline: deadline);
      expect(host.workerSpawnCount, 2);
    });

    test('HOST-H2-4: a worker that exits without reporting fails the run as '
        'an isolate failure, not a timeout', () async {
      final host = newHost();
      final outcome = await host.run(
        fixtureRequest('''
import 'package:fixture/run.dart';
void main() => die();
'''),
        deadline: deadline,
      );
      expect(outcome.status, D4rtRunStatus.failed);
      expect(outcome.error!.kind, D4rtRunError.isolateKind);
      expect(outcome.abandonedWorker, isTrue);
    });
  });

  group('HOST-H3 the channel and the output', () {
    test('HOST-H3-1: channel messages arrive in order, in the caller\'s zone; '
        'output arrives live, in the root zone', () async {
      final host = newHost();
      final received = <Object?>[];
      final zones = <Object?>[];
      final outputZones = <Object?>[];
      final live = <String>[];
      await runZoned(
        () => host.run(
          fixtureRequest('''
import 'package:fixture/run.dart';
void main() {
  post('write', 1);
  print('between');
  post('write', 2);
}
'''),
          deadline: deadline,
          onMessage: (tag, data) {
            received.add('$tag:$data');
            zones.add(Zone.current[#caller]);
          },
          onOutput: (line) {
            live.add(line.text);
            outputZones.add(Zone.current[#caller]);
          },
        ),
        zoneValues: {#caller: 'mine'},
      );
      expect(received, ['write:1', 'write:2']);
      expect(zones, ['mine', 'mine']);
      expect(live, ['between']);
      expect(outputZones, [null]);
    });

    test('HOST-H3-2: the outcome carries what the run printed, a failed run '
        'included', () async {
      final host = newHost();
      final outcome = await host.run(
        fixtureRequest('''
void main() {
  print('before');
  throw StateError('after');
}
'''),
        deadline: deadline,
      );
      expect(outcome.status, D4rtRunStatus.failed);
      expect([for (final l in outcome.transcript.lines) l.text], ['before']);
    });
  });

  group('HOST-H4 the queue and the lifecycle', () {
    test('HOST-H4-1: runs started together are served one at a time, in '
        'order', () async {
      final host = newHost();
      final outcomes = await Future.wait([
        for (var i = 0; i < 4; i++)
          host.run(fixtureRequest('int main() => $i;'), deadline: deadline),
      ]);
      expect([for (final o in outcomes) o.value], [0, 1, 2, 3]);
      expect(host.workerSpawnCount, 1);
    });

    test('HOST-H4-2: dispose is idempotent and recorded', () async {
      final host = D4rtHost(fixtureDelegate);
      await host.run(fixtureRequest('int main() => 1;'), deadline: deadline);
      expect(host.isDisposed, isFalse);
      await host.dispose();
      await host.dispose();
      expect(host.isDisposed, isTrue);
    });
  });
}
