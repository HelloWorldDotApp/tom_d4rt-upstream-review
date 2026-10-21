# tom_d4rt_host — API Summary

One library: `package:tom_d4rt_host/tom_d4rt_host.dart`. It also re-exports
`TomCancellationToken`, `TomOutputLine`, `TomOutputRecorder`, `TomOutputStream`
and `TomOutputTranscript` from `tom_basics`.

## Near side

| Symbol | Kind | Summary |
| --- | --- | --- |
| `D4rtHost` | class | `D4rtHost(factory, {debugName})`; `run(request, {deadline, cancellation, onMessage, onOutput}) → Future<D4rtRunOutcome>`; `workerSpawnCount`, `programParseCount`, `dispose()`, `isDisposed` |
| `D4rtMessageHandler` | typedef | `void Function(String tag, Object? data)` — a throw refuses the message |

## Far side

| Symbol | Kind | Summary |
| --- | --- | --- |
| `D4rtWorkerDelegate<K>` | abstract class | `begin`, `interpreterKey`, `furnish`, `end`, `recognise` |
| `D4rtWorkerDelegateFactory` | typedef | the top-level function that builds the delegate in the worker |
| `D4rtWorkerRun` | class | `request`, `runId`, `payload`, `send(tag, data)`, `emit(stream, text)` |
| `D4rtWorkerFailure` | class | a recognised failure: `message`, `kind`, `withFrames` |
| `D4rtWorker<K>` | class | the worker body: `serve(request)`, `programs`, `interpreterCount` |
| `d4rtWorkerMain` | function | the isolate entry point |
| `D4rtInterpreterPool<K>` | class | `obtain(key)`, `release(key)`, `length` |
| `D4rtProgramCache` | class | `obtain(interpreter, {sourceHash, source, capacity})`, `parseCount`, `length`, `defaultCapacity` |
| `d4rtRunCapturing` | function | runs a body with `print`/`stdout`/`stderr` sent to an emitter |
| `D4rtCapturedStdout` | class | a `Stdout` that emits lines |
| `D4rtOutputEmitter` | typedef | `void Function(TomOutputStream stream, String text)` |
| `d4rtSendable` | function | makes a value sendable across a port |

## Protocol

| Symbol | Kind | Summary |
| --- | --- | --- |
| `D4rtRunRequest` | class | `runId`, `source`, `sourceHash`, `entryPoint`, `arguments`, `programCacheCapacity`, `payload`; `toMap`/`fromMap` |
| `D4rtRunOutcome` | class | `status`, `value`, `error`, `transcript`, `parsed`, `abandonedWorker`, `isOk` |
| `D4rtRunStatus` | enum | `ok`, `failed`, `timedOut`, `cancelled` |
| `D4rtRunError` | class | `message`, `kind`, `frames`, `cause`; kinds `parseKind`, `timeoutKind`, `cancelledKind`, `isolateKind`, `rejectedKind` |
| `D4rtFrame` | class | `line`, `column`, `member` |
| `D4rtWorkerMessage` | constants | `ready`, `output`, `channel`, `done` |
