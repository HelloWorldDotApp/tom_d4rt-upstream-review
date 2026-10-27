/// AST async 块函数自然落底必须完成为 null 的回归测试。
library;

import 'dart:async';
import 'package:test/test.dart';
import 'package:tom_d4rt_ast/runtime.dart';

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

  /// 返回已完成 Future。
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

/// 创建测试 AST 的标识符。
SSimpleIdentifier _id(String name) =>
    SSimpleIdentifier(offset: 0, length: 0, name: name);

/// 创建 `Probe.<method>()` 调用。
SMethodInvocation _call(String method) => SMethodInvocation(
  offset: 0,
  length: 0,
  target: _id('Probe'),
  operator: '.',
  methodName: _id(method),
  argumentList: SArgumentList(offset: 0, length: 0, arguments: const []),
);

/// 将表达式包装为语句。
SExpressionStatement _statement(SExpression expression) =>
    SExpressionStatement(offset: 0, length: 0, expression: expression);

/// 创建 async 块函数。
SFunctionDeclaration _function(String name, List<SStatement> statements) =>
    SFunctionDeclaration(
      offset: 0,
      length: 0,
      name: _id(name),
      functionExpression: SFunctionExpression(
        offset: 0,
        length: 0,
        parameters: SFormalParameterList(
          offset: 0,
          length: 0,
          parameters: const [],
        ),
        body: SBlockFunctionBody(
          offset: 0,
          length: 0,
          isAsync: true,
          block: SBlock(offset: 0, length: 0, statements: statements),
        ),
      ),
    );

/// 创建 async 箭头函数，验证它不适用块体自然落底规则。
SFunctionDeclaration _arrowFunction(String name, SExpression expression) =>
    SFunctionDeclaration(
      offset: 0,
      length: 0,
      name: _id(name),
      functionExpression: SFunctionExpression(
        offset: 0,
        length: 0,
        parameters: SFormalParameterList(
          offset: 0,
          length: 0,
          parameters: const [],
        ),
        body: SExpressionFunctionBody(
          offset: 0,
          length: 0,
          isAsync: true,
          expression: expression,
        ),
      ),
    );

/// 创建覆盖 async 自然落底与显式离开路径的 bundle。
AstBundle _bundle() {
  const entry = 'package:probe/main.dart';
  return AstBundle(
    entryPointUri: entry,
    modules: {
      entry: SCompilationUnit(
        offset: 0,
        length: 0,
        directives: [
          SImportDirective(
            offset: 0,
            length: 0,
            uri: SSimpleStringLiteral(
              offset: 0,
              length: 0,
              value: 'package:probe/async.dart',
            ),
          ),
        ],
        declarations: [
          _function('valueTail', [_statement(_call('value'))]),
          _function('completedTail', [_statement(_call('completed'))]),
          _function('pendingTail', [_statement(_call('wait'))]),
          _function('afterAwait', [
            _statement(
              SAwaitExpression(
                offset: 0,
                length: 0,
                expression: _call('completed'),
              ),
            ),
          ]),
          _function('tryFinallyTail', [
            STryStatement(
              offset: 0,
              length: 0,
              body: SBlock(
                offset: 0,
                length: 0,
                statements: [_statement(_call('value'))],
              ),
              finallyBlock: SBlock(
                offset: 0,
                length: 0,
                statements: [_statement(_call('finish'))],
              ),
            ),
          ]),
          _arrowFunction('arrowValue', _call('value')),
          _arrowFunction('arrowFuture', _call('completed')),
          _arrowFunction(
            'arrowAwait',
            SAwaitExpression(
              offset: 0,
              length: 0,
              expression: _call('completed'),
            ),
          ),
          _function('explicitValue', [
            SReturnStatement(offset: 0, length: 0, expression: _call('value')),
          ]),
          _function('explicitFuture', [
            SReturnStatement(
              offset: 0,
              length: 0,
              expression: _call('completed'),
            ),
          ]),
          _function('explicitPending', [
            SReturnStatement(offset: 0, length: 0, expression: _call('wait')),
          ]),
          _function('explicitNull', [SReturnStatement(offset: 0, length: 0)]),
          _function('returnNullFinally', [
            STryStatement(
              offset: 0,
              length: 0,
              body: SBlock(
                offset: 0,
                length: 0,
                statements: [SReturnStatement(offset: 0, length: 0)],
              ),
              finallyBlock: SBlock(
                offset: 0,
                length: 0,
                statements: [_statement(_call('finish'))],
              ),
            ),
          ]),
          _function('throwsAsync', [_statement(_call('fail'))]),
        ],
      ),
    },
  );
}

/// 创建带 Probe 静态桥接的 AST runner。
D4rtRunner _runner() => D4rtRunner()
  ..registerBridgedClass(
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
    sourceUri: 'package:probe/async.dart',
  );

/// 经执行 API 动态调用 bundle 函数；测试只观察 Future 语义。
dynamic _run(String name) => _runner().executeBundle(_bundle(), name: name);

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

/// 组织 AST async 块函数自然落底回归场景。
void main() {
  setUp(_Probe.reset);
  group('async 块函数自然落底 (AST)', () {
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
