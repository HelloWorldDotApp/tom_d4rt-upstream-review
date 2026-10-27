import 'package:test/test.dart';
import 'package:tom_d4rt/d4rt.dart';

import 'fixtures/relationship_visibility_cases.dart';

/// 通过公开 source 解释器入口执行一份隔离的关系可见性模块图。
Object? _execute(String entry) {
  final runner = D4rt();
  try {
    return runner.execute(
      library: relationshipEntryUri,
      sources: relationshipSources(entry),
      allowFileSystemImports: false,
    );
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

/// 注册 source 解释器中前缀关系和导出隔离的回归用例。
void main() {
  group('关系可见性 source', () {
    for (final positive in relationshipPositiveCases) {
      test('${positive.name} 通过公开 source 入口', () {
        expect(_execute(positive.entry), positive.expected);
      });
    }

    test('隐藏的前缀基类不得退回同名本地类', () {
      expect(
        () => _execute(hiddenSuperclassEntry),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains("Superclass 'Base' not found"),
          ),
        ),
      );
    });

    test('缺失的前缀接口不得退回同名本地类', () {
      expect(
        () => _execute(missingInterfaceEntry),
        throwsA(
          predicate<Object>(
            (error) =>
                error.toString().contains("Interface 'Missing' not found"),
          ),
        ),
      );
    });

    test('barrel 过滤的接口不得退回同名本地类', () {
      expect(
        () => _execute(barrelFilteredInterfaceEntry),
        throwsA(
          predicate<Object>(
            (error) =>
                error.toString().contains("Interface 'Contract' not found"),
          ),
        ),
      );
    });

    test('不存在的前缀必须拒绝关系解析', () {
      expect(
        () => _execute(absentPrefixEntry),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains("Superclass 'Base' not found"),
          ),
        ),
      );
    });

    test('显式 core 前缀不得泄露脚本全局声明', () {
      expect(
        () => _execute(leakedScriptGlobalEntry),
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
        test('$relation $type 不能作为关系目标', () {
          expect(
            () => _execute(invalidRelationshipEntry(relation, type)),
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
