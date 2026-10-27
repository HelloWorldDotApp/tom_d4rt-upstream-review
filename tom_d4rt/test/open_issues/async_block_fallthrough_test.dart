/// async 块函数自然落底必须完成为 null 的回归测试。
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:tom_d4rt/d4rt.dart';

/// 提供末尾值、Future、finally 副作用和失败路径的原生夹具。
class _Probe {
  /// 记录普通方法调用次数。
  static int values = 0;

  /// 记录 finally 是否运行。
  static int finals = 0;

  /// 保存测试结束前必须主动完成的 Future。
  static Completer<Object?> pending = Completer<Object?>();

  /// 返回普通末尾值。
  static int value() => ++values;

  /// 返回已完成的 Future。
  static Future<Object?> completed() => Future<Object?>.value('done');

  /// 返回未完成 Future，验证自然落底不会隐式 await 它。
  static Future<Object?> wait() => pending.future;

  /// 记录 finally 的正常执行。
  static void finish() => finals++;

  /// 抛出应由 async Future 保留的错误。
  static Never fail() => throw StateError('async-block-fallthrough');

  /// 清理各测试之间的原生夹具状态。
  static void reset() {
    values = 0;
    finals = 0;
    pending = Completer<Object?>();
  }
}

/// 创建带 Probe 静态桥接的解释器。
D4rt _interpreter() {
  final interpreter = D4rt();
  interpreter.registerBridgedClass(
    BridgedClass(
      nativeType: _Probe,
      name: 'Probe',
      staticMethods: {
        'value': (v, p, n, t) => _Probe.value(),
        'completed': (v, p, n, t) => _Probe.completed(),
        'wait': (v, p, n, t) => _Probe.wait(),
        'finish': (v, p, n, t) => _Probe.finish(),
        'fail': (v, p, n, t) => _Probe.fail(),
      },
    ),
    'package:probe/async.dart',
  );
  return interpreter;
}

/// 返回覆盖 async 自然落底与显式离开路径的脚本。
String _script() => '''
import 'package:probe/async.dart';
/// 普通值末尾自然落底。
Future<Object?> valueTail() async { Probe.value(); }
/// 已完成 Future 末尾自然落底。
Future<Object?> completedTail() async { Probe.completed(); }
/// 未完成 Future 末尾自然落底。
Future<Object?> pendingTail() async { Probe.wait(); }
/// await 语句后自然落底。
Future<Object?> afterAwait() async { await Probe.completed(); }
/// try finally 正常执行后自然落底。
Future<Object?> tryFinallyTail() async { try { Probe.value(); } finally { Probe.finish(); } }
/// 箭头体保留普通值。
Future<Object?> arrowValue() async => Probe.value();
/// 箭头体保留 Future 的完成值。
Future<Object?> arrowFuture() async => Probe.completed();
/// 箭头体保留 await 的完成值。
Future<Object?> arrowAwait() async => await Probe.completed();
/// 显式返回普通值。
Future<Object?> explicitValue() async { return Probe.value(); }
/// 显式返回 Future。
Future<Object?> explicitFuture() async { return Probe.completed(); }
/// 显式返回未完成 Future，必须等待其真实完成。
Future<Object?> explicitPending() async { return Probe.wait(); }
/// 显式返回 null。
Future<Object?> explicitNull() async { return null; }
/// return null 穿过 finally 后仍必须保留。
Future<Object?> returnNullFinally() async { try { return null; } finally { Probe.finish(); } }
/// 通过原生桥接抛出错误。
Future<Object?> throwsAsync() async { Probe.fail(); }
''';

/// 经执行 API 动态调用脚本函数；返回值可能由 API 包装，测试只观察 Future 语义。
dynamic _run(String name) =>
    _interpreter().execute(source: _script(), name: name);

/// 原生 Dart 对照：普通值末尾自然落底。
Future<Object?> _nativeValueTail() async {
  _Probe.value();
}

/// 原生 Dart 对照：未完成 Future 末尾自然落底。
Future<Object?> _nativePendingTail() async {
  _Probe.wait();
}

/// 在有界时间内取得 async API 的完成值，仅作为测试哨兵。
Future<Object?> _withinTestBound(dynamic value) =>
    (value as Future<Object?>).timeout(const Duration(seconds: 1));

/// 组织 source async 块函数自然落底回归场景。
void main() {
  setUp(_Probe.reset);

  group('async 块函数自然落底 (source)', () {
    test('原生 Dart 对照的普通值和未完成 Future 末尾都完成为 null', () async {
      expect(await _nativeValueTail(), isNull);
      expect(_Probe.values, 1);
      _Probe.reset();
      try {
        expect(await _withinTestBound(_nativePendingTail()), isNull);
      } finally {
        _Probe.pending.complete('cleanup');
      }
    });

    test('普通值末尾自然落底完成为 null', () async {
      expect(await _withinTestBound(_run('valueTail')), isNull);
      expect(_Probe.values, 1);
    });

    test('已完成 Future 末尾自然落底完成为 null', () async {
      expect(await _withinTestBound(_run('completedTail')), isNull);
    });

    test('未完成 Future 末尾自然落底不隐式 await', () async {
      try {
        expect(await _withinTestBound(_run('pendingTail')), isNull);
        expect(_Probe.pending.isCompleted, isFalse);
      } finally {
        _Probe.pending.complete('cleanup');
      }
    });

    test('await 语句后自然落底完成为 null', () async {
      expect(await _withinTestBound(_run('afterAwait')), isNull);
    });

    test('try finally 正常落底完成为 null 且 finally 运行', () async {
      expect(await _withinTestBound(_run('tryFinallyTail')), isNull);
      expect(_Probe.finals, 1);
    });

    test('async 箭头体保留普通值、Future 与 await 的完成值', () async {
      expect(await _withinTestBound(_run('arrowValue')), 1);
      expect(await _withinTestBound(_run('arrowFuture')), 'done');
      expect(await _withinTestBound(_run('arrowAwait')), 'done');
    });

    test('显式 return 保留普通值和 null 经过 finally 的语义', () async {
      expect(await _withinTestBound(_run('explicitValue')), 1);
      expect(await _withinTestBound(_run('explicitNull')), isNull);
      expect(await _withinTestBound(_run('returnNullFinally')), isNull);
      expect(_Probe.finals, 1);
    });

    test('显式 return Future 保留完成语义且 pending Future 真实等待', () async {
      expect(await _withinTestBound(_run('explicitFuture')), 'done');
      final result = _run('explicitPending') as Future<Object?>;
      try {
        await expectLater(
          result.timeout(const Duration(milliseconds: 20)),
          throwsA(isA<TimeoutException>()),
        );
      } finally {
        _Probe.pending.complete('released');
      }
      expect(await result, 'released');
    });

    test('async 错误路径保持原语义', () async {
      await expectLater(
        _withinTestBound(_run('throwsAsync')),
        throwsA(isA<StateError>()),
      );
    });
  });
}
