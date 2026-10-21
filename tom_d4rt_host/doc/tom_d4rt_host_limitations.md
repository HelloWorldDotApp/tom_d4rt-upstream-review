# tom_d4rt_host — Limitations

The interpreter's own limitations are the canon in
[`tom_d4rt`'s `d4rt_limitations.md`](../../tom_d4rt/doc/d4rt_limitations.md);
these are the host's own.

- **A runaway is stopped by killing the worker.** `D4rt.execute` is
  synchronous, so there is no cooperative stop: a deadline, a cancellation and
  a refused channel message all kill the isolate, and the next run pays a spawn
  and a fresh interpreter.
- **Runs are serialized.** One worker serves one run at a time; runs started
  together queue in the order they were started. Two hosts give two workers.
- **Everything that crosses the port must be sendable.** The request's
  arguments and payload, and the channel's data, are primitives and collections
  of them. A run's return value is made sendable for you: anything else becomes
  its `toString()`.
- **Frames are the main program's only.** A runtime failure's frames are those
  of the unnamed main source; a frame in an imported library is dropped,
  because its line belongs to another file. A failure the interpreter reports
  with an empty trace has no frames.
- **The delegate factory must be top-level or static**, since it crosses
  `Isolate.spawn`.
- **A Dart VM library.** It uses `dart:isolate` and `dart:io` and does not
  compile for the web.
