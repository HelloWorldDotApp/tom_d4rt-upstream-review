/// 同步块函数自然落底不泄漏末尾表达式值的回归测试。
///
/// 原生动态调用解释器函数时，普通块体的最后一条语句只应产生副作用；它不是
/// Dart 的隐式 return。尤其不能把未完成 Future 泄漏给宿主关闭排空逻辑。
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:tom_d4rt/d4rt.dart';

/// 提供可数副作用、已完成 Future 与未完成 Future 的原生桥接夹具。
class _SyncProbe {
  /// 记录脚本实际触发原生方法的次数。
  static int calls = 0;

  /// 保存最近一次已完成 Future，供显式 return 身份断言使用。
  static Future<Object?>? completedFuture;

  /// 保存永不完成的 Future，模拟关闭期间不能等待的原生工作。
  static Completer<Object?> pendingCompleter = Completer<Object?>();

  /// 递增副作用计数并返回普通末尾表达式值。
  static int tick() {
    calls++;
    return 42;
  }

  /// 递增副作用计数并返回已完成 Future。
  static Future<Object?> completed() {
    calls++;
    return completedFuture = Future<Object?>.value('completed');
  }

  /// 递增副作用计数并返回测试不会完成的 Future。
  static Future<Object?> pending() {
    calls++;
    return pendingCompleter.future;
  }

  /// 重置夹具状态，使每个断言都能独立检查一次副作用。
  static void reset() {
    calls = 0;
    completedFuture = null;
    pendingCompleter = Completer<Object?>();
  }
}

/// 将 [_SyncProbe.tick] 注册为脚本可调用的静态桥接方法。
Object? _tickAdapter(
  InterpreterVisitor visitor,
  List<Object?> positional,
  Map<String, Object?> named,
  List<RuntimeType>? typeArguments,
) => _SyncProbe.tick();

/// 将 [_SyncProbe.completed] 注册为脚本可调用的静态桥接方法。
Object? _completedAdapter(
  InterpreterVisitor visitor,
  List<Object?> positional,
  Map<String, Object?> named,
  List<RuntimeType>? typeArguments,
) => _SyncProbe.completed();

/// 将 [_SyncProbe.pending] 注册为脚本可调用的静态桥接方法。
Object? _pendingAdapter(
  InterpreterVisitor visitor,
  List<Object?> positional,
  Map<String, Object?> named,
  List<RuntimeType>? typeArguments,
) => _SyncProbe.pending();

/// 创建并配置仅供本测试使用的 source 解释器。
D4rt _newInterpreter() {
  final interpreter = D4rt();
  interpreter.registerBridgedClass(
    BridgedClass(
      nativeType: _SyncProbe,
      name: 'Probe',
      staticMethods: {
        'tick': _tickAdapter,
        'completed': _completedAdapter,
        'pending': _pendingAdapter,
      },
    ),
    'package:probe/sync.dart',
  );
  return interpreter;
}

/// 返回同时覆盖声明返回类型、自然落底与显式 return 的脚本。
String _script() => '''
import 'package:probe/sync.dart';

/// 同步表达式体应保留表达式的结果。
Object? arrowValue() => Probe.tick();

/// 普通构造器用于核验落底后的实例返回语义。
class Box {
  int value = 17;

  /// 初始化字段后执行一次末尾副作用，仍应返回新实例。
  Box() {
    Probe.tick();
  }
}

/// 通过新实例的字段验证构造结果没有被清空或替换。
Object? constructorValue() => Box().value;

/// void 块体只执行末尾副作用。
void voidTail() {
  Probe.tick();
}

/// 可空块体只执行末尾副作用。
Object? nullableTail() {
  Probe.tick();
}

/// dynamic 块体只执行末尾副作用。
dynamic dynamicTail() {
  Probe.tick();
}

/// 已完成 Future 作为自然落底语句时不得泄漏给宿主。
Object? completedTail() {
  Probe.completed();
}

/// 未完成 Future 作为自然落底语句时不得泄漏给宿主。
Object? pendingTail() {
  Probe.pending();
}

/// 显式 return 必须保留普通值。
Object? explicitValue() {
  return Probe.tick();
}

/// 显式 return 必须保留 Future 的完成语义。
Object? explicitFuture() {
  return Probe.completed();
}

/// 真正 async 函数显式返回 null，仍由异步状态机返回 Future。
asyncTail() async {
  Probe.tick();
  return null;
}
''';

/// 以原生动态调用方式执行脚本中的指定函数。
dynamic _run(D4rt interpreter, String name) =>
    interpreter.execute(source: _script(), name: name);

/// 作为原生 Dart 对照，void 块体自然落底只保留副作用。
void _nativeVoidTail() {
  _SyncProbe.tick();
}

/// 作为原生 Dart 对照，可空块体自然落底只保留副作用。
Object? _nativeNullableTail() {
  _SyncProbe.tick();
}

/// 作为原生 Dart 对照，dynamic 块体自然落底只保留副作用。
dynamic _nativeDynamicTail() {
  _SyncProbe.tick();
}

/// 组织 source 解释器的同步块体自然落底回归场景。
void main() {
  setUp(_SyncProbe.reset);

  group('同步块函数自然落底 (source)', () {
    test('同步表达式体保留结果且副作用恰好一次', () {
      expect(_run(_newInterpreter(), 'arrowValue'), 42);
      expect(_SyncProbe.calls, 1);
    });

    test('普通构造器保留初始化后的实例且副作用恰好一次', () {
      expect(_run(_newInterpreter(), 'constructorValue'), 17);
      expect(_SyncProbe.calls, 1);
    });

    test('原生 Dart 的动态调用对照中三类块体均返回 null 且副作用一次', () {
      final dynamic voidCall = _nativeVoidTail;
      expect(voidCall(), isNull);
      expect(_SyncProbe.calls, 1);

      _SyncProbe.reset();
      final dynamic nullableCall = _nativeNullableTail;
      expect(nullableCall(), isNull);
      expect(_SyncProbe.calls, 1);

      _SyncProbe.reset();
      final dynamic dynamicCall = _nativeDynamicTail;
      expect(dynamicCall(), isNull);
      expect(_SyncProbe.calls, 1);
    });

    test('void、可空与 dynamic 块体不返回末尾普通值，且副作用恰好一次', () {
      for (final name in ['voidTail', 'nullableTail', 'dynamicTail']) {
        final result = _run(_newInterpreter(), name);

        expect(result, isNull, reason: '$name 不得隐式返回 Probe.tick 的值');
        expect(_SyncProbe.calls, 1, reason: '$name 只能执行末尾语句一次');
        _SyncProbe.reset();
      }
    });

    test('自然落底的已完成与未完成 Future 都不泄漏给调用方', () {
      final completedResult = _run(_newInterpreter(), 'completedTail');
      expect(completedResult, isNull);
      expect(_SyncProbe.calls, 1);
      expect(_SyncProbe.completedFuture, isA<Future<Object?>>());

      _SyncProbe.reset();
      final pendingResult = _run(_newInterpreter(), 'pendingTail');
      expect(pendingResult, isNull);
      expect(_SyncProbe.calls, 1);
      expect(_SyncProbe.pendingCompleter.isCompleted, isFalse);
    });

    test('显式 return 保留普通值，并使 Future 正确完成', () async {
      final valueResult = _run(_newInterpreter(), 'explicitValue');
      expect(valueResult, 42);
      expect(_SyncProbe.calls, 1);

      _SyncProbe.reset();
      final futureResult = _run(_newInterpreter(), 'explicitFuture');
      expect(futureResult, isA<Future<Object?>>());
      expect(await (futureResult as Future<Object?>), 'completed');
      expect(_SyncProbe.calls, 1);
    });

    test('真正 async 块函数仍返回 Future 并只执行一次副作用', () async {
      final result = _run(_newInterpreter(), 'asyncTail');

      expect(result, isA<Future<Object?>>());
      expect(await (result as Future<Object?>), isNull);
      expect(_SyncProbe.calls, 1);
    });
  });
}
