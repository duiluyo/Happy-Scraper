// 影片刮削器 —— 冒烟测试
//
// 直接放在 test/ 目录，`flutter test` 就能跑，不需要先拆分 main.dart：
// extractCode / codeTags / safeName / folderPartsFor / buildNfo / applyNfo /
// organizeInto / LocalFs / Movie / LibItem 都是公开的顶层声明。
//
// 覆盖四块最容易"改一处、坏一片"的纯逻辑：
//   1. 番号识别      —— 真实文件名里花样最多，出错会让整部影片刮错
//   2. 模板与文件名  —— 出错会把用户的影片整理进奇怪的目录
//   3. NFO 往返      —— 出错会让 Emby / Kodi 读不到元数据
//   4. 整理移动      —— 出错会丢字幕、丢 NFO

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_scraper/main.dart';

void main() {
  // ───────────────────────── 1. 番号识别 ─────────────────────────
  group('番号识别', () {
    const cases = <String, String?>{
      '[xxx] ssis00123 1080p.mp4': 'SSIS-123',
      'SSIS-123-C.mp4': 'SSIS-123',
      'abc.com@ABP-789-UC.mkv': 'ABP-789',
      'FC2-PPV-1234567.mp4': 'FC2-PPV-1234567',
      '010123_001.mp4': '010123_001',
      'HEYZO-1234.mp4': 'HEYZO-1234',
      'HD-[FHD] MIDE-123-C.mp4': 'MIDE-123',
      'WEB-DL.SSIS-00123.2160p.mkv': 'SSIS-123',
      '123456-789-1080p.mp4': '123456-789',
      'random_video.mp4': null,
      'holiday.mp4': null,
    };

    cases.forEach((name, expected) {
      test(name, () => expect(extractCode(name), expected));
    });

    test('后缀标记：-C / -U / -UC', () {
      expect(codeTags('SSIS-123-C.mp4'), contains('中文字幕'));
      expect(codeTags('SSIS-123-U.mp4'), contains('无码'));
      expect(
        codeTags('SSIS-123-UC.mp4'),
        containsAll(<String>['中文字幕', '无码']),
      );
    });

    test('分卷 -CD1 不能被误判成 -C（中文字幕）', () {
      expect(codeTags('SSIS-123-CD1.mp4'), isEmpty);
      expect(codeTags('SSIS-123-CD2.mp4'), isEmpty);
      expect(extractCode('SSIS-123-CD1.mp4'), 'SSIS-123');
    });
  });

  // ───────────────────── 2. 文件名清理与模板 ─────────────────────
  group('文件名清理', () {
    test('去掉文件系统非法字符', () {
      expect(safeName('a/b:c*d?'), 'a b c d');
      expect(safeName('a\\b|c'), 'a b c');
    });

    test('去掉结尾的点与空格（Windows 不允许）', () {
      expect(safeName('abc...'), 'abc');
      expect(safeName('abc   '), 'abc');
    });

    test('超长按码点截断，不切断 emoji', () {
      expect(safeName('あ' * 200).runes.length, 80);
      expect(safeName('😀' * 100).runes.length, 80);
    });
  });

  group('文件夹模板', () {
    test('单层：番号', () {
      expect(folderPartsFor(Movie('SSIS-123'), '{番号}', 'SSIS-123'), ['SSIS-123']);
    });

    test('多层：用 / 分层', () {
      final m = Movie('SSIS-123')
        ..title = 'テスト'
        ..date = '2021-05-01';
      expect(
        folderPartsFor(m, '{年份}/{番号} {标题}', 'SSIS-123'),
        ['2021', 'SSIS-123 テスト'],
      );
    });

    test('演员超过 3 位 → 多人作品；没有演员 → 未知演员', () {
      final many = Movie('X-1')..actors = ['A', 'B', 'C', 'D'];
      final none = Movie('X-1');
      expect(folderPartsFor(many, '{演员}', 'X-1'), ['多人作品']);
      expect(folderPartsFor(none, '{演员}', 'X-1'), ['未知演员']);
      many.actors = ['A'];
      expect(folderPartsFor(many, '{演员}', 'X-1'), ['A']);
    });

    test('模板为空时回退到番号', () {
      expect(folderPartsFor(Movie('X-1'), '   ', 'X-1'), ['X-1']);
    });

    test('译名优先于原标题', () {
      final m = Movie('X-1')
        ..title = '日本語タイトル'
        ..titleZh = '中文标题';
      expect(folderPartsFor(m, '{标题}', 'X-1'), ['中文标题']);
      expect(folderPartsFor(m, '{原标题}', 'X-1'), ['日本語タイトル']);
    });

    test('标题里的 / 不会意外多出一层目录', () {
      final m = Movie('X-1')..title = 'a/b';
      expect(folderPartsFor(m, '{番号} {标题}', 'X-1'), ['X-1 a b']);
    });
  });

  // ───────────────────────── 3. NFO 往返 ─────────────────────────
  group('NFO', () {
    Movie sample() => Movie('SSIS-123')
      ..title = 'タイトル & <tag> "quote"'
      ..date = '2021-05-01'
      ..runtime = 120
      ..studio = 'Studio & Co'
      ..director = '監督'
      ..series = 'シリーズ'
      ..genres = ['単体作品', 'ハイビジョン']
      ..actors = ['女優A', '女優B']
      ..urls = ['https://example.com/?a=1&b=2'];

    test('buildNfo → applyNfo 往返一致', () {
      final m = sample();
      final xml = buildNfo(m);
      final it = LibItem('/tmp/SSIS-123.mp4');
      applyNfo(it, xml);

      expect(it.num, 'SSIS-123');
      expect(it.title, m.title); // 标题前面的番号会被剥掉
      expect(it.origTitle, m.title);
      expect(it.date, '2021-05-01');
      expect(it.runtime, 120);
      expect(it.studio, m.studio);
      expect(it.director, m.director);
      expect(it.series, m.series);
      expect(it.genres, m.genres);
      expect(it.actors, m.actors);
      expect(it.tags, isEmpty); // genre 同时写成 tag，读回来要去重
      expect(it.hasNfo, isFalse); // applyNfo 不负责置这个标记
    });

    test('特殊字符被正确转义', () {
      final xml = buildNfo(sample());
      expect(xml, contains('&amp;'));
      expect(xml, contains('&lt;tag&gt;'));
      expect(xml, isNot(contains('<title>SSIS-123 タイトル & ')));
    });

    test('没有 NFO 时从文件名兜底', () {
      final it = LibItem('/tmp/SSIS-456.mp4');
      expect(extractCode(it.stem), 'SSIS-456');
    });
  });

  // ───────────────────────── 4. 整理移动 ─────────────────────────
  group('整理移动', () {
    late Directory root;
    late LocalFs fs;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('scraper_test_');
      fs = LocalFs();
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('视频与同名附属文件一起移动', () async {
      final src = Directory('${root.path}/src')..createSync();
      File('${src.path}/SSIS-123.mp4').writeAsBytesSync([1, 2, 3]);
      File('${src.path}/SSIS-123.srt').writeAsStringSync('sub');
      File('${src.path}/SSIS-123.nfo').writeAsStringSync('<movie/>');
      File('${src.path}/SSIS-999.mp4').writeAsBytesSync([9]);

      final dest = '${root.path}/SSIS-123';
      final moves = <List<String>>[];
      final out = await organizeInto(
        fs,
        '${src.path}/SSIS-123.mp4',
        dest,
        moves: moves,
      );

      expect(out, '$dest/SSIS-123.mp4');
      expect(File('$dest/SSIS-123.mp4').existsSync(), isTrue);
      expect(File('$dest/SSIS-123.srt').existsSync(), isTrue);
      expect(File('$dest/SSIS-123.nfo').existsSync(), isTrue);
      // 不相干的影片不能被带走
      expect(File('${src.path}/SSIS-999.mp4').existsSync(), isTrue);
      // 三个移动都要记进 journal，否则撤销会漏
      expect(moves.length, 3);
    });

    test('目标已有同名视频时抛错，源文件留在原地', () async {
      final src = Directory('${root.path}/src')..createSync();
      final dest = Directory('${root.path}/SSIS-123')..createSync();
      File('${src.path}/SSIS-123.mp4').writeAsBytesSync([1]);
      File('${dest.path}/SSIS-123.mp4').writeAsBytesSync([2, 2]);

      await expectLater(
        organizeInto(fs, '${src.path}/SSIS-123.mp4', dest.path),
        throwsA(anything),
      );
      expect(File('${src.path}/SSIS-123.mp4').existsSync(), isTrue);
      expect(File('${dest.path}/SSIS-123.mp4').lengthSync(), 2);
    });

    test('已经在目标文件夹里时不动文件', () async {
      final dest = Directory('${root.path}/SSIS-123')..createSync();
      File('${dest.path}/SSIS-123.mp4').writeAsBytesSync([1]);
      final moves = <List<String>>[];
      final out = await organizeInto(
        fs,
        '${dest.path}/SSIS-123.mp4',
        dest.path,
        moves: moves,
      );
      expect(out, '${dest.path}/SSIS-123.mp4');
      expect(moves, isEmpty);
    });
  });

  // ───────────────────────── 5. 影视库分页 ─────────────────────────
  group('分页', () {
    test('整除与不整除', () {
      final a = paginate(90, 1, 30);
      expect((a.pages, a.page, a.start, a.end), (3, 1, 0, 30));
      final b = paginate(95, 4, 30);
      expect((b.pages, b.page, b.start, b.end), (4, 4, 90, 95));
    });

    test('页码越界会被修正', () {
      expect(paginate(95, 99, 30).page, 4);
      expect(paginate(95, 0, 30).page, 1);
      expect(paginate(95, -5, 30).page, 1);
    });

    test('没有数据时仍是第 1 页，范围为空', () {
      final r = paginate(0, 3, 50);
      expect((r.pages, r.page, r.start, r.end), (1, 1, 0, 0));
    });

    test('每页 0 表示全部显示', () {
      final r = paginate(412, 5, 0);
      expect((r.pages, r.page, r.start, r.end), (1, 1, 0, 412));
    });

    test('每页数量大于总数时只有一页', () {
      final r = paginate(20, 1, 100);
      expect((r.pages, r.page, r.start, r.end), (1, 1, 0, 20));
    });
  });
}
