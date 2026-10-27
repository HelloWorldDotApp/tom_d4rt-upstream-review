import 'package:test/test.dart';
import 'package:tom_ast_generator/tom_ast_generator.dart';
import 'package:tom_d4rt_ast/runtime.dart' as runtime;

import 'fixtures/relationship_visibility_cases.dart';

/// 通过官方 AST 打包入口执行一份隔离的关系可见性模块图。
Future<Object?> _execute(String entry) async {
  final bundle = await AstBundler(
    explicitSources: relationshipSources(entry),
    fileAccessValidator: (_) => false,
  ).createFromSource(entry, sourcePath: relationshipEntryUri);
  final runner = runtime.D4rtRunner();
  try {
    return runner.executeBundleAs<Object?>(bundle);
  } finally {
    runner.dispose();
  }
}

/// 判断关系目标错误是否明确指出指定类型未找到或不是类。
bool _isRejectedRelationship(Object error, String type) {
  final message = error.toString();
  return message.contains("'$type'") &&
      (message.contains('not found') || message.contains('not a class'));
}

/// 注册 AST 解释器中前缀关系和导出隔离的回归用例。
void main() {
  group('关系可见性 AST', () {
    for (final positive in relationshipPositiveCases) {
      test('${positive.name} 通过官方 AST 入口', () async {
        expect(await _execute(positive.entry), positive.expected);
      });
    }

    test('隐藏的前缀基类不得退回同名本地类', () async {
      await expectLater(
        _execute(hiddenSuperclassEntry),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains("Superclass 'Base' not found"),
          ),
        ),
      );
    });

    test('缺失的前缀接口不得退回同名本地类', () async {
      await expectLater(
        _execute(missingInterfaceEntry),
        throwsA(
          predicate<Object>(
            (error) =>
                error.toString().contains("Interface 'Missing' not found"),
          ),
        ),
      );
    });

    test('barrel 过滤的接口不得退回同名本地类', () async {
      await expectLater(
        _execute(barrelFilteredInterfaceEntry),
        throwsA(
          predicate<Object>(
            (error) =>
                error.toString().contains("Interface 'Contract' not found"),
          ),
        ),
      );
    });

    test('不存在的前缀必须拒绝关系解析', () async {
      await expectLater(
        _execute(absentPrefixEntry),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains("Superclass 'Base' not found"),
          ),
        ),
      );
    });

    test('显式 core 前缀不得泄露脚本全局声明', () async {
      await expectLater(
        _execute(leakedScriptGlobalEntry),
        throwsA(
          predicate<Object>(
            (error) =>
                error.toString().contains("Superclass 'ScriptLocal' not found"),
          ),
        ),
      );
    });

    for (final relation in <String>['extends', 'implements']) {
      for (final type in <String>['dynamic', 'Record']) {
        test('$relation $type 不能作为关系目标', () async {
          await expectLater(
            _execute(invalidRelationshipEntry(relation, type)),
            throwsA(
              predicate<Object>(
                (error) => _isRejectedRelationship(error, type),
              ),
            ),
          );
        });
      }
    }
  });
}
