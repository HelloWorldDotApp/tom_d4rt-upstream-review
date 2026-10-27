/// AST 运行时同步块函数自然落底不泄漏末尾表达式值的回归测试。
///
/// 预解析 AST 经原生动态调用时，普通块体的最后一条语句只应产生副作用；它
/// 不能成为函数返回值，也不能把未完成 Future 交给宿主关闭排空逻辑。
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:tom_d4rt_ast/runtime.dart';

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

/// 将 [_SyncProbe.tick] 注册为 AST 脚本可调用的静态桥接方法。
Object? _tickAdapter(
  InterpreterVisitor visitor,
  List<Object?> positional,
  Map<String, Object?> named,
  List<RuntimeType>? typeArguments,
) => _SyncProbe.tick();

/// 将 [_SyncProbe.completed] 注册为 AST 脚本可调用的静态桥接方法。
Object? _completedAdapter(
  InterpreterVisitor visitor,
  List<Object?> positional,
  Map<String, Object?> named,
  List<RuntimeType>? typeArguments,
) => _SyncProbe.completed();

/// 将 [_SyncProbe.pending] 注册为 AST 脚本可调用的静态桥接方法。
Object? _pendingAdapter(
  InterpreterVisitor visitor,
  List<Object?> positional,
  Map<String, Object?> named,
  List<RuntimeType>? typeArguments,
) => _SyncProbe.pending();

/// 创建名称为 [name] 的零长度测试标识符。
SSimpleIdentifier _id(String name) =>
    SSimpleIdentifier(offset: 0, length: 0, name: name);

/// 创建指定名称和可空性的类型标注。
SNamedType _type(String name, {bool isNullable = false}) =>
    SNamedType(offset: 0, length: 0, name: _id(name), isNullable: isNullable);

/// 创建无参数的原生 Probe 静态方法调用表达式。
SMethodInvocation _probeCall(String method) => SMethodInvocation(
  offset: 0,
  length: 0,
  target: _id('Probe'),
  operator: '.',
  methodName: _id(method),
  argumentList: SArgumentList(offset: 0, length: 0, arguments: const []),
);

/// 创建以 [statement] 结束的同步或 async 块函数。
SFunctionDeclaration _blockFunction(
  String name,
  SStatement statement, {
  STypeAnnotation? returnType,
  bool isAsync = false,
}) => SFunctionDeclaration(
  offset: 0,
  length: 0,
  name: _id(name),
  returnType: returnType,
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
      isAsync: isAsync,
      block: SBlock(offset: 0, length: 0, statements: [statement]),
    ),
  ),
);

/// 创建同步表达式函数，用于保护表达式体的返回语义。
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
          expression: expression,
        ),
      ),
    );

/// 创建由多个语句组成的 async 块函数。
SFunctionDeclaration _asyncBlockFunction(
  String name,
  List<SStatement> statements,
) => SFunctionDeclaration(
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

/// 创建覆盖自然落底、显式 return 与 async 块体的预解析 bundle。
AstBundle _bundle() {
  const entry = 'package:probe/main.dart';

  /// 创建仅计算表达式副作用、没有显式 return 的块体末尾语句。
  SExpressionStatement tail(String method) => SExpressionStatement(
    offset: 0,
    length: 0,
    expression: _probeCall(method),
  );

  /// 创建携带原生调用结果的显式 return 语句。
  SReturnStatement returned(String method) =>
      SReturnStatement(offset: 0, length: 0, expression: _probeCall(method));

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
              value: 'package:probe/sync.dart',
            ),
          ),
        ],
        declarations: [
          _arrowFunction('arrowValue', _probeCall('tick')),
          SClassDeclaration(
            offset: 0,
            length: 0,
            name: _id('Box'),
            members: [
              SFieldDeclaration(
                offset: 0,
                length: 0,
                fields: SVariableDeclarationList(
                  offset: 0,
                  length: 0,
                  type: _type('int'),
                  variables: [
                    SVariableDeclaration(
                      offset: 0,
                      length: 0,
                      name: _id('value'),
                      initializer: SIntegerLiteral(
                        offset: 0,
                        length: 0,
                        value: 17,
                      ),
                    ),
                  ],
                ),
              ),
              SConstructorDeclaration(
                offset: 0,
                length: 0,
                returnType: _id('Box'),
                parameters: SFormalParameterList(
                  offset: 0,
                  length: 0,
                  parameters: const [],
                ),
                body: SBlockFunctionBody(
                  offset: 0,
                  length: 0,
                  block: SBlock(
                    offset: 0,
                    length: 0,
                    statements: [tail('tick')],
                  ),
                ),
              ),
            ],
          ),
          _arrowFunction(
            'constructorValue',
            SPropertyAccess(
              offset: 0,
              length: 0,
              target: SInstanceCreationExpression(
                offset: 0,
                length: 0,
                constructorName: SConstructorName(
                  offset: 0,
                  length: 0,
                  type: _type('Box'),
                ),
                argumentList: SArgumentList(
                  offset: 0,
                  length: 0,
                  arguments: const [],
                ),
              ),
              operator: '.',
              propertyName: _id('value'),
            ),
          ),
          _blockFunction('voidTail', tail('tick'), returnType: _type('void')),
          _blockFunction(
            'nullableTail',
            tail('tick'),
            returnType: _type('Object', isNullable: true),
          ),
          _blockFunction(
            'dynamicTail',
            tail('tick'),
            returnType: _type('dynamic'),
          ),
          _blockFunction(
            'completedTail',
            tail('completed'),
            returnType: _type('Object', isNullable: true),
          ),
          _blockFunction(
            'pendingTail',
            tail('pending'),
            returnType: _type('Object', isNullable: true),
          ),
          _blockFunction(
            'explicitValue',
            returned('tick'),
            returnType: _type('Object', isNullable: true),
          ),
          _blockFunction(
            'explicitFuture',
            returned('completed'),
            returnType: _type('Object', isNullable: true),
          ),
          _asyncBlockFunction('asyncTail', [
            tail('tick'),
            SReturnStatement(offset: 0, length: 0),
          ]),
        ],
      ),
    },
  );
}

/// 创建并配置仅供本测试使用的 AST runner。
D4rtRunner _newRunner() => D4rtRunner()
  ..registerBridgedClass(
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
    sourceUri: 'package:probe/sync.dart',
  );

/// 以原生动态调用方式执行 bundle 中的指定函数。
dynamic _run(D4rtRunner runner, String name) =>
    runner.executeBundle(_bundle(), name: name);

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

/// 组织 AST 运行时的同步块体自然落底回归场景。
void main() {
  setUp(_SyncProbe.reset);

  group('同步块函数自然落底 (AST)', () {
    test('同步表达式体保留结果且副作用恰好一次', () {
      expect(_run(_newRunner(), 'arrowValue'), 42);
      expect(_SyncProbe.calls, 1);
    });

    test('普通构造器保留初始化后的实例且副作用恰好一次', () {
      expect(_run(_newRunner(), 'constructorValue'), 17);
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
        final result = _run(_newRunner(), name);

        expect(result, isNull, reason: '$name 不得隐式返回 Probe.tick 的值');
        expect(_SyncProbe.calls, 1, reason: '$name 只能执行末尾语句一次');
        _SyncProbe.reset();
      }
    });

    test('自然落底的已完成与未完成 Future 都不泄漏给调用方', () {
      final completedResult = _run(_newRunner(), 'completedTail');
      expect(completedResult, isNull);
      expect(_SyncProbe.calls, 1);
      expect(_SyncProbe.completedFuture, isA<Future<Object?>>());

      _SyncProbe.reset();
      final pendingResult = _run(_newRunner(), 'pendingTail');
      expect(pendingResult, isNull);
      expect(_SyncProbe.calls, 1);
      expect(_SyncProbe.pendingCompleter.isCompleted, isFalse);
    });

    test('显式 return 保留普通值，并使 Future 正确完成', () async {
      final valueResult = _run(_newRunner(), 'explicitValue');
      expect(valueResult, 42);
      expect(_SyncProbe.calls, 1);

      _SyncProbe.reset();
      final futureResult = _run(_newRunner(), 'explicitFuture');
      expect(futureResult, isA<Future<Object?>>());
      expect(await (futureResult as Future<Object?>), 'completed');
      expect(_SyncProbe.calls, 1);
    });

    test('真正 async 块函数仍返回 Future 并只执行一次副作用', () async {
      final result = _run(_newRunner(), 'asyncTail');

      expect(result, isA<Future<Object?>>());
      expect(await (result as Future<Object?>), isNull);
      expect(_SyncProbe.calls, 1);
    });
  });
}
