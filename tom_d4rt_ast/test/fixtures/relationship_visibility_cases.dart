/// 关系可见性夹具的入口库 URI。
const relationshipEntryUri = 'package:relationship_visibility/main.dart';

/// 关系可见性夹具的被前缀导入库 URI。
const relationshipTypesUri = 'package:relationship_visibility/types.dart';

/// 关系可见性夹具的仅重导出公开基类的 barrel 库 URI。
const relationshipBarrelUri = 'package:relationship_visibility/barrel.dart';

/// 关系可见性夹具循环导入中首个模块的 URI。
const relationshipCycleAUri = 'package:relationship_visibility/cycle_a.dart';

/// 关系可见性夹具循环导入中第二个模块的 URI。
const relationshipCycleBUri = 'package:relationship_visibility/cycle_b.dart';

/// 描述可同时交给解释器和原生 Dart 对照运行的正例入口。
class RelationshipPositiveCase {
  /// 创建带名称、入口源码和预期结果的可复用正例。
  const RelationshipPositiveCase(this.name, this.entry, this.expected);

  /// 标识该正例覆盖的关系或导出边界。
  final String name;

  /// 保存可原样写入入口库文件的 Dart 源码。
  final String entry;

  /// 保存入口执行后必须得到的稳定结果。
  final Object? expected;
}

/// 生成每个回归场景独占的内存模块图，避免测试间共享解释器状态。
Map<String, String> relationshipSources(String entry) => <String, String>{
  relationshipEntryUri: entry,
  relationshipTypesUri: '''
class Base {
  /// 返回导入基类的固定标记，用于识别同名本地类未被错误采用。
  int base() => 10;
}

abstract class Contract {
  /// 声明前缀接口要求的固定标记读取操作。
  int contract();
}

mixin Feature {
  /// 返回导入混入的固定标记，用于验证实际混入目标。
  int feature() => 30;
}

int _privateValue = 41;

/// 创建读取声明库私有状态的闭包，验证导出过滤后仍保留闭包环境。
int Function() makeReader() {
  final captured = _privateValue;
  return () => captured + 1;
}
''',
  relationshipBarrelUri: '''
export 'types.dart' show Base;
''',
  relationshipCycleAUri: '''
import 'cycle_b.dart' as cycle;

class CycleA extends cycle.CycleB {}
''',
  relationshipCycleBUri: '''
import 'cycle_a.dart' as cycle;

class CycleB {
  /// 返回循环模块真实基类的固定标记。
  int value() => 29;
}
''',
};

/// 覆盖六种关系位置及同名本地声明的正向入口源码。
const prefixedRelationshipEntry = '''
import 'package:relationship_visibility/types.dart' as imported;

class Base {
  /// 返回同名本地基类标记；前缀关系不得解析到这里。
  int base() => -1;
}

abstract class Contract {
  /// 返回同名本地接口标记；前缀关系不得解析到这里。
  int contract();
}

mixin Feature {
  /// 返回同名本地混入标记；前缀关系不得解析到这里。
  int feature() => -1;
}

class Extended extends imported.Base {}

class Implemented implements imported.Contract {
  /// 实现前缀接口要求的读取操作。
  int contract() => 40;
}

class Mixed with imported.Feature {}

mixin Constrained on imported.Base {
  /// 读取前缀约束基类的成员，避免依赖未修复的 super 分派。
  int constrained() => base();
}

mixin InterfaceMixin implements imported.Contract {
  /// 实现前缀接口要求的读取操作。
  int contract() => 50;
}

class ConstraintApplied extends imported.Base with Constrained {}

class InterfaceApplied with InterfaceMixin {}

enum Mode with imported.Feature { active }

/// 汇总六种关系与过滤后闭包的结果，验证均解析到前缀导入库。
int main() {
  final reader = imported.makeReader();
  final implementedIsContract = Implemented() is imported.Contract;
  final interfaceAppliedIsContract = InterfaceApplied() is imported.Contract;
  return Extended().base() +
      Implemented().contract() +
      Mixed().feature() +
      ConstraintApplied().constrained() +
      InterfaceApplied().contract() +
      Mode.active.feature() +
      reader() +
      (implementedIsContract ? 1 : 0) +
      (interfaceAppliedIsContract ? 1 : 0);
}
''';

/// 返回显式 core 前缀只导出标准库成员的正向入口源码。
const explicitCoreEntry = '''
import 'dart:core' as core;

/// 通过显式 core 前缀访问标准类型，验证受限导出面仍保留标准库能力。
core.int main() => core.int.parse('7');
''';

/// 返回显式 async 前缀只导出标准库成员的正向入口源码。
const explicitAsyncEntry = '''
import 'dart:async' as a;

/// 构造未完成的 Completer，验证 async 前缀保留公开标准库成员。
int main() => a.Completer<int>().isCompleted ? 1 : 0;
''';

/// 返回两个 core/async 前缀同时存在时的正向入口源码。
const repeatedStandardLibraryEntry = '''
import 'dart:core' as first;
import 'dart:core' as second;
import 'dart:async' as firstAsync;
import 'dart:async' as secondAsync;

/// 读取两个标准库前缀，验证各自导出面没有因复制或过滤互相覆盖。
first.int main() {
  final firstReady = firstAsync.Completer<first.int>().isCompleted ? 1 : 0;
  final secondReady = secondAsync.Completer<second.int>().isCompleted ? 1 : 0;
  return first.int.parse('4') + second.int.parse('5') + firstReady + secondReady;
}
''';

/// 返回仍使用隐式 core 和未前缀 async 的正向入口源码。
const implicitStandardLibraryEntry = '''
import 'dart:async';

/// 使用未加前缀的标准类型，验证显式导出隔离不污染普通脚本环境。
int main() => int.parse('8') + (Completer<int>().isCompleted ? 1 : 0);
''';

/// 返回仅导入函数时仍能执行声明环境闭包的入口源码。
const filteredClosureEntry = '''
import 'package:relationship_visibility/types.dart' as imported show makeReader;

/// 调用过滤后导入的函数并执行其闭包，验证捕获环境未被过滤丢失。
int main() => imported.makeReader()();
''';

/// 返回经 barrel 重导出后按前缀继承公开类的正向入口源码。
const barrelSuperclassEntry = '''
import 'package:relationship_visibility/barrel.dart' as barrel;

class Child extends barrel.Base {}

/// 调用 barrel 导出的真实基类成员，验证前缀复制保留重导出边界。
int main() => Child().base();
''';

/// 返回循环导入模块中按前缀继承的正向入口源码。
const cycleRelationshipEntry = '''
import 'package:relationship_visibility/cycle_a.dart' as cycle;

/// 调用循环模块真实基类成员，验证过滤后模块仍保留原始库 URI。
int main() => cycle.CycleA().value();
''';

/// 返回隐藏前缀基类且存在同名本地类的反例入口源码。
const hiddenSuperclassEntry = '''
import 'package:relationship_visibility/types.dart' as imported hide Base;

class Base {}

class Child extends imported.Base {}

/// 隐藏目标必须在执行前拒绝，不能退回同名本地类。
int main() => 1;
''';

/// 返回 barrel 已过滤接口且存在同名本地类的反例入口源码。
const barrelFilteredInterfaceEntry = '''
import 'package:relationship_visibility/barrel.dart' as barrel;

class Contract {}

class Child implements barrel.Contract {}

/// barrel 未重导出的接口必须拒绝，不能退回同名本地类。
int main() => 1;
''';

/// 返回缺失前缀接口且存在同名本地类的反例入口源码。
const missingInterfaceEntry = '''
import 'package:relationship_visibility/types.dart' as imported;

class Missing {}

class Child implements imported.Missing {}

/// 缺失前缀接口必须在执行前拒绝，不能退回同名本地类。
int main() => 1;
''';

/// 返回不存在前缀的反例入口源码。
const absentPrefixEntry = '''
import 'package:relationship_visibility/types.dart' as imported;

class Child extends absent.Base {}

/// 未声明的前缀必须在执行前拒绝，不能退回任意可见基类。
int main() => 1;
''';

/// 返回试图从显式 core 导出面读取脚本全局的反例入口源码。
const leakedScriptGlobalEntry = '''
import 'dart:core' as core;

class ScriptLocal {}

class Child extends core.ScriptLocal {}

/// 标准库前缀不得泄露调用脚本声明。
core.int main() => 1;
''';

/// 生成指定关系关键字和非法类型的反例入口源码。
String invalidRelationshipEntry(String relation, String type) =>
    '''
class Child $relation $type {}

/// 非类类型不能作为声明关系目标。
int main() => 1;
''';

/// 公开所有可直接用于原生 Dart 对照的关系可见性正例。
const relationshipPositiveCases = <RelationshipPositiveCase>[
  RelationshipPositiveCase('六种前缀关系与同名本地类型', prefixedRelationshipEntry, 214),
  RelationshipPositiveCase('显式 core 前缀', explicitCoreEntry, 7),
  RelationshipPositiveCase('显式 async 前缀', explicitAsyncEntry, 0),
  RelationshipPositiveCase(
    '重复显式 core/async 前缀',
    repeatedStandardLibraryEntry,
    9,
  ),
  RelationshipPositiveCase(
    '隐式 core 与未前缀 async',
    implicitStandardLibraryEntry,
    8,
  ),
  RelationshipPositiveCase('过滤导入保留函数闭包', filteredClosureEntry, 42),
  RelationshipPositiveCase('barrel 重导出前缀继承', barrelSuperclassEntry, 10),
  RelationshipPositiveCase('循环导入前缀继承', cycleRelationshipEntry, 29),
];
