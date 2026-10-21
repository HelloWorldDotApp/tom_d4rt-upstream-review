## 0.1.0

- `D4rtHost`: one resident worker isolate serving runs one at a time, with a
  deadline and a cancellation that kill the worker, an application message
  channel whose handler runs in the caller's zone and may refuse a message, live
  output in the root zone, and `workerSpawnCount`, `programParseCount`,
  `dispose` and `isDisposed`.
- `D4rtWorker`, `D4rtWorkerDelegate`, `D4rtWorkerRun` and `d4rtWorkerMain`: the
  worker body the application furnishes — its bridges, its per-run state, the
  failures it recognises.
- `D4rtInterpreterPool`: one interpreter per bridge set, released after every
  run.
- `D4rtProgramCache`: a bounded LRU of parsed programs keyed by source hash,
  with `parseCount`.
- `d4rtRunCapturing` and `D4rtCapturedStdout`: `print`, `stdout` and `stderr`
  into one emitter.
- `D4rtRunRequest`, `D4rtRunOutcome`, `D4rtRunStatus`, `D4rtRunError`,
  `D4rtFrame` and `D4rtWorkerMessage`: what crosses the port.
