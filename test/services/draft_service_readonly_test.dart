/// 只读大文件草稿测试：轻量条目持久化与恢复时重读磁盘。
library services.draft_service_readonly_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/models/note_file.dart';
import 'package:notepad/services/draft_service.dart';
import 'package:notepad/services/file_service.dart';

void main() {
  late Directory tempDir;
  late DraftService draftService;
  late FileService fileService;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('notepad_draft_ro_test_');
    // 注入小阈值，使小文件也能触发只读逻辑
    fileService = FileService(readOnlyThresholdBytes: 5, maxFileBytes: 100);
    draftService = DraftService(fileService: fileService);
    draftService.testDraftDir = tempDir.path;
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {
      // Windows 下临时目录可能被短暂占用，忽略清理失败
    }
  });

  NoteFile readOnlyDraft(String id, String path, String content) {
    return NoteFile(
      id: id,
      title: path.split('/').last,
      filePath: path,
      content: content,
      diskContent: content,
      lastModified: DateTime.now(),
      isReadOnly: true,
    );
  }

  test('只读大文件草稿不应包含内容', () async {
    final diskPath = '${tempDir.path}/big.txt';
    File(diskPath).writeAsStringSync('0123456789');

    await draftService
        .saveDrafts([readOnlyDraft('ro', diskPath, '0123456789')]);

    final jsonStr = File('${tempDir.path}/drafts.json').readAsStringSync();
    expect(jsonStr.contains('0123456789'), false);
    expect(jsonStr.contains('"isReadOnly":true'), true);
  });

  test('只读草稿恢复应从磁盘重读内容并保留 id', () async {
    final diskPath = '${tempDir.path}/big.txt';
    File(diskPath).writeAsStringSync('0123456789');

    await draftService
        .saveDrafts([readOnlyDraft('ro', diskPath, '0123456789')]);
    final loaded = await draftService.loadDrafts();

    expect(loaded.single.id, 'ro');
    expect(loaded.single.content, '0123456789');
    expect(loaded.single.isReadOnly, true);
    expect(loaded.single.isDirty, false);
  });

  test('只读草稿的磁盘文件已删除时应保留空内容条目', () async {
    final draft = readOnlyDraft('ro', '${tempDir.path}/gone.txt', '');

    await draftService.saveDrafts([draft]);
    final loaded = await draftService.loadDrafts();

    expect(loaded.single.id, 'ro');
    expect(loaded.single.content, '');
    expect(loaded.single.isReadOnly, true);
  });

  test('普通文件草稿仍应包含内容', () async {
    final file = NoteFile(
      id: 'n',
      title: '无标题',
      content: '未保存内容',
      isDirty: true,
      lastModified: DateTime.now(),
      isNew: true,
    );

    await draftService.saveDrafts([file]);
    final loaded = await draftService.loadDrafts();

    expect(loaded.single.content, '未保存内容');
    expect(loaded.single.isReadOnly, false);
  });

  test('普通文件草稿恢复时磁盘已增大应切换为只读', () async {
    final diskPath = '${tempDir.path}/grown.txt';
    File(diskPath).writeAsStringSync('旧');
    final draft = NoteFile(
      id: 'grown',
      title: 'grown.txt',
      filePath: diskPath,
      content: '旧',
      diskContent: '旧',
      lastModified: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    await draftService.saveDrafts([draft]);
    File(diskPath).writeAsStringSync('0123456789');
    File(diskPath)
        .setLastModifiedSync(DateTime.now().add(const Duration(seconds: 2)));

    final loaded = await draftService.loadDrafts();

    expect(loaded.single.id, 'grown');
    expect(loaded.single.content, '0123456789');
    expect(loaded.single.isReadOnly, true);
  });

  test('普通文件草稿恢复时磁盘超过上限应保留旧草稿', () async {
    final diskPath = '${tempDir.path}/too_large.txt';
    File(diskPath).writeAsStringSync('旧');
    final draft = NoteFile(
      id: 'large',
      title: 'too_large.txt',
      filePath: diskPath,
      content: '旧',
      diskContent: '旧',
      lastModified: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    await draftService.saveDrafts([draft]);
    File(diskPath).writeAsStringSync('x' * 120);
    File(diskPath)
        .setLastModifiedSync(DateTime.now().add(const Duration(seconds: 2)));

    final loaded = await draftService.loadDrafts();

    expect(loaded.single.id, 'large');
    expect(loaded.single.content, '旧');
    expect(loaded.single.isReadOnly, false);
  });

  test('只读与普通文件混合草稿应各自正确恢复', () async {
    final diskPath = '${tempDir.path}/big.txt';
    File(diskPath).writeAsStringSync('0123456789');
    final normal = NoteFile(
      id: 'n',
      title: '无标题',
      content: '普通草稿',
      isDirty: true,
      lastModified: DateTime.now(),
      isNew: true,
    );

    await draftService
        .saveDrafts([readOnlyDraft('ro', diskPath, '0123456789'), normal]);
    final loaded = await draftService.loadDrafts();

    expect(loaded, hasLength(2));
    expect(loaded[0].id, 'ro');
    expect(loaded[0].content, '0123456789');
    expect(loaded[1].id, 'n');
    expect(loaded[1].content, '普通草稿');
  });
}
