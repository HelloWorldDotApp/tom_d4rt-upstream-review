// Runs a script in a resident worker: one bridged value, one channel message
// back to the application, and the transcript of what the script printed.
//
//   dart run example/tom_d4rt_host_example.dart
import 'package:tom_d4rt/d4rt.dart';
import 'package:tom_d4rt_host/tom_d4rt_host.dart';

/// The application's side inside the worker: what the script can reach.
class TodoDelegate extends D4rtWorkerDelegate<Object?> {
  D4rtWorkerRun? _run;

  @override
  void begin(D4rtWorkerRun run) => _run = run;

  // One interpreter is enough: this application gates no corpus.
  @override
  Object? interpreterKey(D4rtWorkerRun run) => 'todo';

  @override
  void furnish(D4rt interpreter, Object? key) {
    interpreter
      // Read per run, so each run sees its own list.
      ..registerGlobalGetter(
        'items',
        () => _run!.payload['items'],
        'package:todo/todo.dart',
      )
      // The application's channel: the script asks, the host decides.
      ..registertopLevelFunction('complete', (visitor, args, named, types) {
        _run!.send('complete', args.single);
        return null;
      }, 'package:todo/todo.dart');
  }

  @override
  void end(D4rtWorkerRun run) => _run = null;
}

/// Built inside the worker isolate, so it must be top-level.
D4rtWorkerDelegate<Object?> todoDelegate() => TodoDelegate();

const script = '''
import 'package:todo/todo.dart';

int main() {
  var done = 0;
  for (final item in items) {
    if (item.startsWith('x ')) {
      complete(item);
      done++;
    }
  }
  print('completed \$done of \${items.length}');
  return done;
}
''';

Future<void> main() async {
  final host = D4rtHost(todoDelegate, debugName: 'todo-scripts');
  try {
    final outcome = await host.run(
      const D4rtRunRequest(
        runId: 'run-1',
        source: script,
        sourceHash: 'todo-script-1',
        payload: {
          'items': ['x write the README', 'test the host', 'x publish'],
        },
      ),
      deadline: const Duration(seconds: 10),
      onMessage: (tag, data) => print('host: $tag "$data"'),
    );
    print('status: ${outcome.status.name}, value: ${outcome.value}');
    for (final line in outcome.transcript.lines) {
      print('script ${line.stream.name}: ${line.text}');
    }
  } finally {
    await host.dispose();
  }
}
