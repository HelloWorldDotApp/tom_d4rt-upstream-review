import 'package:test/test.dart';
import 'mirror_normalisation.dart';

/// 前缀包装差异交给具体方法的精确签名记录，不扩大通用镜像归一规则。
void main() {
  test('任何局部接收者的前缀包装差异都保留', () {
    for (final receiver in ['other', 'node', 'typeNode']) {
      final tokens = [receiver, '.', 'importPrefix', '?.', 'name', '.', 'name'];
      expect(normaliseAccessorVocabulary(tokens), tokens);
    }
  });
  test('普通成员链的前缀差异保留', () {
    for (final access in ['.', '?.', '..', '?..']) {
      final tokens = [
        'owner',
        access,
        'node',
        '.',
        'importPrefix',
        '?.',
        'name',
        '.',
        'name',
      ];
      expect(normaliseAccessorVocabulary(tokens), tokens);
    }
  });
  test('实际关系查找的差异只包含 analyzer 的 Token 包装', () {
    expect(
      tokenDivergence(
        normaliseAccessorVocabulary([
          'final',
          'prefix',
          '=',
          'node',
          '.',
          'importPrefix',
          '?.',
          'name',
          '.',
          'lexeme',
        ]),
        normaliseAccessorVocabulary([
          'final',
          'prefix',
          '=',
          'node',
          '.',
          'importPrefix',
          '?.',
          'name',
        ]),
      ),
      ('. name', ''),
    );
  });
}
