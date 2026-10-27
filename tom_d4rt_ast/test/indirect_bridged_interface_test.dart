/// 间接桥接接口在 AST 解释器中的类型归属回归测试。
library;

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:test/test.dart';
import 'package:tom_ast_generator/tom_ast_generator.dart';
import 'package:tom_d4rt_ast/runtime.dart';

const _entryUri = 'package:indirect_bridged_interface_ast/main.dart';
const _rootUri = 'package:indirect_bridged_interface_ast/native_root.dart';
const _fakeUri = 'package:indirect_bridged_interface_ast/other_root.dart';

/// 作为真实注册桥接目标的宿主根类型。
class _NativeRoot {
  /// 创建可被动态脚本继承的宿主根对象。
  const _NativeRoot();
}

/// 与真实根同名假桥对应的另一宿主根类型。
class _OtherRoot {
  /// 创建只供假桥接使用的宿主根对象。
  const _OtherRoot();
}

/// 原生对照中的第一层接口。
abstract class _NativeInterface implements _NativeRoot {}

/// 原生对照中的第二层接口。
abstract class _NativeSecondInterface implements _NativeInterface {}

/// 原生对照中的直接接口实现。
class _NativeDirectInterface implements _NativeRoot {}

/// 原生对照中的直接继承实现。
class _NativeDirectExtends extends _NativeRoot {}

/// 原生对照中的一层间接接口实现。
class _NativeIndirect implements _NativeInterface {}

/// 原生对照中的两层间接接口实现。
class _NativeTwoLayer implements _NativeSecondInterface {}

/// 原生对照中通过接口取得根类型关系的父类。
class _NativeParent implements _NativeInterface {}

/// 原生对照中经父类取得根类型关系的子类。
class _NativeChild extends _NativeParent {}

/// 原生对照中通过接口取得根类型关系的 mixin。
mixin _NativeMixin implements _NativeInterface {}

/// 原生对照中应用接口 mixin 的类型。
class _NativeMixed with _NativeMixin {}

/// 原生对照中 diamond 左支接口。
abstract class _NativeLeft implements _NativeInterface {}

/// 原生对照中 diamond 右支接口。
abstract class _NativeRight implements _NativeInterface {}

/// 原生对照中共享祖先的 diamond 实现。
class _NativeDiamond implements _NativeLeft, _NativeRight {}

/// 原生对照中与真实根类型无关的类型。
class _NativeUnrelated {}

/// 原生对照中实现假桥宿主根的类型。
class _NativeFakeInterface implements _OtherRoot {}

/// 原生对照中继承假桥宿主根的类型。
class _NativeFakeExtends extends _OtherRoot {}

/// 原生对照中实现假桥宿主根的 mixin。
mixin _NativeFakeMixin implements _OtherRoot {}

/// 原生对照中应用假桥接口 mixin 的类型。
class _NativeFakeMixed with _NativeFakeMixin {}

/// 保存真实桥和同名不同 nativeType 的假桥，供宿主侧精确查询。
class _BridgePair {
  /// 创建实际宿主类型不同的两份同名桥接定义。
  _BridgePair() : root = _rootBridge(), fake = _fakeBridge();

  /// 真实宿主根的桥接类型参数绑定。
  final BridgedClass root;

  /// 同名但绑定另一宿主根的桥接类型参数。
  final BridgedClass fake;
}

/// 创建唯一注册到正例解释器的真实桥接定义。
BridgedClass _rootBridge() => BridgedClass(
  nativeType: _NativeRoot,
  name: 'NativeRoot',
  isAssignable: (value) => value is _NativeRoot,
  constructors: {'': (visitor, positional, named) => const _NativeRoot()},
);

/// 创建只注册到负例解释器的同名假桥接定义。
BridgedClass _fakeBridge() => BridgedClass(
  nativeType: _OtherRoot,
  name: 'NativeRoot',
  isAssignable: (value) => value is _OtherRoot,
  constructors: {'': (visitor, positional, named) => const _OtherRoot()},
);

/// 将 [source] 转换成 AST runner 可执行的编译单元。
SCompilationUnit _unit(String source) =>
    AstConverter().convertCompilationUnit(parseString(content: source).unit);

/// 仅注册真实桥并执行正例 AST 脚本，不向该 runner 提供同名假桥。
Object? _executeTrue(BridgedClass root, String source) {
  final runner = D4rtRunner();
  runner.registerBridgedClass(root, _rootUri, sourceUri: _rootUri);
  try {
    return runner.executeBundle(
      AstBundle(
        entryPointUri: _entryUri,
        modules: <String, SCompilationUnit>{
          _entryUri: _unit(source),
          _rootUri: _unit('library;'),
        },
      ),
    );
  } finally {
    runner.dispose();
  }
}

/// 仅注册假桥并执行负例 AST 脚本；真实桥仅在宿主侧用作查询目标。
Object? _executeFake(BridgedClass fake, String source) {
  final runner = D4rtRunner();
  runner.registerBridgedClass(fake, _fakeUri, sourceUri: _fakeUri);
  try {
    return runner.executeBundle(
      AstBundle(
        entryPointUri: _entryUri,
        modules: <String, SCompilationUnit>{
          _entryUri: _unit(source),
          _fakeUri: _unit('library;'),
        },
      ),
    );
  } finally {
    runner.dispose();
  }
}

/// 返回只无前缀导入唯一真实桥的完整正例脚本，并构造 [expression] 对象。
String _trueScript(String expression) =>
    '''
import '$_rootUri';

/// 第一层接口直接实现唯一真实桥接根类型。
abstract class I implements NativeRoot {}
/// 第二层接口经 I 间接实现真实桥接根类型。
abstract class I2 implements I {}
/// 验证直接 implements 的基线类型。
class DirectInterface implements NativeRoot {}
/// 验证直接 extends 的基线类型。
class DirectExtends extends NativeRoot {
  /// 初始化真实桥接父对象。
  DirectExtends() : super();
}
/// 验证一层间接接口类型。
class Indirect implements I {}
/// 验证两层间接接口类型。
class TwoLayer implements I2 {}
/// 验证经父类保留的间接接口类型。
class Parent implements I {}
/// 验证子类沿父类接口链取得的类型。
class Child extends Parent {}
/// 验证 mixin 经接口取得的类型。
mixin IndirectMixin implements I {}
/// 验证应用接口 mixin 后的类型。
class Mixed with IndirectMixin {}
/// 验证 diamond 的左侧接口分支。
abstract class Left implements I {}
/// 验证 diamond 的右侧接口分支。
abstract class Right implements I {}
/// 验证共享祖先的 diamond 类型。
class Diamond implements Left, Right {}
/// 验证无关类型不会被桥接根类型接纳。
class Unrelated {}

/// 构造本用例要求核验的动态对象。
Object main() => $expression;
''';

/// 返回只无前缀导入同名假桥的负例脚本，并构造 [expression] 对象。
String _fakeScript(String expression) =>
    '''
import '$_fakeUri';

/// 验证实现假桥不会授予真实桥类型。
class FakeInterface implements NativeRoot {}
/// 验证继承假桥不会授予真实桥类型。
class FakeExtends extends NativeRoot {
  /// 初始化假桥接父对象。
  FakeExtends() : super();
}
/// 验证 mixin 经假桥接口不会授予真实桥类型。
mixin FakeMixin implements NativeRoot {}
/// 验证应用假桥接口 mixin 后的类型。
class FakeMixed with FakeMixin {}

/// 构造本用例要求核验的同名假桥对象。
Object main() => $expression;
''';

/// 返回一次执行全部正例脚本 `is NativeRoot` 判定的源码。
String _trueChecksScript() =>
    '''
import '$_rootUri';

abstract class I implements NativeRoot {}
abstract class I2 implements I {}
class DirectInterface implements NativeRoot {}
class DirectExtends extends NativeRoot {
  /// 初始化唯一真实桥接父对象。
  DirectExtends() : super();
}
class Indirect implements I {}
class TwoLayer implements I2 {}
class Parent implements I {}
class Child extends Parent {}
mixin IndirectMixin implements I {}
class Mixed with IndirectMixin {}
abstract class Left implements I {}
abstract class Right implements I {}
class Diamond implements Left, Right {}
class Unrelated {}

/// 返回全部正例及无关类型的脚本 is 判定结果。
List<bool> main() => <bool>[
  DirectInterface() is NativeRoot,
  DirectExtends() is NativeRoot,
  Indirect() is NativeRoot,
  TwoLayer() is NativeRoot,
  Child() is NativeRoot,
  Mixed() is NativeRoot,
  Diamond() is NativeRoot,
  Unrelated() is NativeRoot,
];
''';

/// 返回一次执行全部假桥脚本 `is NativeRoot` 判定的源码。
String _fakeChecksScript() =>
    '''
import '$_fakeUri';

class FakeInterface implements NativeRoot {}
class FakeExtends extends NativeRoot {
  /// 初始化当前负例实际导入的假桥接父对象。
  FakeExtends() : super();
}
mixin FakeMixin implements NativeRoot {}
class FakeMixed with FakeMixin {}

/// 返回假桥对象只属于已导入假桥的脚本 is 判定结果。
List<bool> main() => <bool>[
  FakeInterface() is NativeRoot,
  FakeExtends() is NativeRoot,
  FakeMixed() is NativeRoot,
];
''';

/// 返回 [value] 是否属于真实原生根类型，作为 Dart 语言自身的合法性对照。
bool _isNativeRoot(Object value) => value is _NativeRoot;

/// 生成与真实桥脚本正例一一对应的原生 Dart `is` 判定结果。
List<bool> _nativeTrueParity() => <bool>[
  _isNativeRoot(_NativeDirectInterface()),
  _isNativeRoot(_NativeDirectExtends()),
  _isNativeRoot(_NativeIndirect()),
  _isNativeRoot(_NativeTwoLayer()),
  _isNativeRoot(_NativeChild()),
  _isNativeRoot(_NativeMixed()),
  _isNativeRoot(_NativeDiamond()),
  _isNativeRoot(_NativeUnrelated()),
];

/// 生成同名假桥三个反例对真实原生根类型的 Dart `is` 判定结果。
List<bool> _nativeFakeParity() => <bool>[
  _isNativeRoot(_NativeFakeInterface()),
  _isNativeRoot(_NativeFakeExtends()),
  _isNativeRoot(_NativeFakeMixed()),
];

/// 在宿主侧读取真实桥正例对象的 klass，并用同一桥对象验证子类型关系。
bool _trueHostSubtype(BridgedClass root, String expression) {
  final result = _executeTrue(root, _trueScript(expression));
  expect(result, isA<InterpretedInstance>());
  return (result! as InterpretedInstance).klass.isSubtypeOf(root);
}

/// 返回同名假桥对象对假桥和未注册真实桥的宿主侧类型关系。
({bool fake, bool real}) _fakeHostSubtype(
  _BridgePair bridges,
  String expression,
) {
  final result = _executeFake(bridges.fake, _fakeScript(expression));
  expect(result, isA<InterpretedInstance>());
  final klass = (result! as InterpretedInstance).klass;
  return (
    fake: klass.isSubtypeOf(bridges.fake),
    real: klass.isSubtypeOf(bridges.root),
  );
}

/// 通过真实桥类型形参验证官方转换后的间接实现能正常绑定参数。
String _parameterScript() =>
    '''
import '$_rootUri';
abstract class I implements NativeRoot {}
class Indirect implements I {}
/// 接受桥类型参数并返回原对象，供宿主核对真实类型关系。
Object accepted(NativeRoot value) => value;
/// 将间接实现传入桥类型形参。
Object main() => accepted(Indirect());
''';

/// 组织 AST 解释器的间接桥接接口正反例。
void main() {
  setUp(D4rtRunner.debugResetPool);
  tearDown(D4rtRunner.debugResetPool);

  group('间接桥接接口', () {
    test('桥类型参数绑定接受间接接口实现并保留对象', () {
      final root = _rootBridge();
      final result = _executeTrue(root, _parameterScript());
      expect(result, isA<InterpretedInstance>());
      expect((result! as InterpretedInstance).klass.isSubtypeOf(root), isTrue);
    });

    test('原生 Dart 对照保留直接、间接、mixin、diamond 与无关类型关系', () {
      expect(
        _nativeTrueParity(),
        orderedEquals(<bool>[true, true, true, true, true, true, true, false]),
      );
      expect(_nativeFakeParity(), orderedEquals(<bool>[false, false, false]));
    });

    test('唯一真实桥的脚本 is 识别完整接口链并拒绝无关类型', () {
      final root = _rootBridge();
      expect(
        _executeTrue(root, _trueChecksScript()),
        orderedEquals(<bool>[true, true, true, true, true, true, true, false]),
      );
    });

    test('宿主 klass 使用注册真实桥对象遍历直接与间接接口链', () {
      final root = _rootBridge();
      for (final expression in <String>[
        'DirectInterface()',
        'DirectExtends()',
        'Indirect()',
        'TwoLayer()',
        'Child()',
        'Mixed()',
        'Diamond()',
      ]) {
        expect(_trueHostSubtype(root, expression), isTrue, reason: expression);
      }
      expect(_trueHostSubtype(root, 'Unrelated()'), isFalse);
      expect(root.nativeType, same(_NativeRoot));
      expect(root.isAssignable!(const _NativeRoot()), isTrue);
      expect(root.isAssignable!(const _OtherRoot()), isFalse);
    });

    test('同名假桥只在独立解释执行中生效，不能冒充未注册真实桥', () {
      final bridges = _BridgePair();
      expect(
        _executeFake(bridges.fake, _fakeChecksScript()),
        orderedEquals(<bool>[true, true, true]),
      );
      for (final expression in <String>[
        'FakeInterface()',
        'FakeExtends()',
        'FakeMixed()',
      ]) {
        final result = _fakeHostSubtype(bridges, expression);
        expect(result.fake, isTrue, reason: '$expression 必须属于假桥');
        expect(result.real, isFalse, reason: '$expression 不得属于真实桥');
      }
      expect(bridges.fake.nativeType, same(_OtherRoot));
      expect(bridges.root.nativeType, same(_NativeRoot));
    });

    test('手工循环和共享祖先的桥接类型图会终止且保留真实接口', () {
      final root = _rootBridge();
      final unrelated =
          _executeTrue(root, _trueScript('Unrelated()')) as InterpretedInstance;
      final direct =
          _executeTrue(root, _trueScript('DirectInterface()'))
              as InterpretedInstance;
      // 非法图只由宿主测试构造；合法脚本源码没有循环继承许可。
      unrelated.klass.interfaces = [unrelated.klass];
      expect(unrelated.klass.isSubtypeOf(root), isFalse);
      unrelated.klass.interfaces = [
        direct.klass,
        unrelated.klass,
        direct.klass,
      ];
      expect(unrelated.klass.isSubtypeOf(root), isTrue);
    });
  });
}
