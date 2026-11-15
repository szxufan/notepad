import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/models/note_file.dart';
import 'package:notepad/services/draft_service.dart';

void main() {
  late Directory tempDir;
  late DraftService draftService;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('notepad_draft_test_');
    draftService = DraftService();
    draftService.testDraftDir = tempDir.path;
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('DraftService', () {
    test('saveDrafts 和 loadDrafts 应可往返', () async {
      final files = [
        NoteFile(
          id: 'file-1',
          title: '文件1.txt',
          filePath: null,
          content: '内容1',
          isDirty: true,
          lastModified: DateTime.parse('2024-01-01T00:00:00.000'),
          isNew: true,
        ),
        NoteFile(
          id: 'file-2',
          title: '文件2.txt',
          filePath: '/tmp/file2.txt',
          content: '内容2',
          diskContent: '内容2',
          isDirty: false,
          lastModified: DateTime.parse('2024-02-01T00:00:00.000'),
          lastSavedAt: DateTime.parse('2024-02-01T00:00:00.000'),
          isNew: false,
        ),
      ];

      await draftService.saveDrafts(files);
      final loaded = await draftService.loadDrafts();

      expect(loaded.length, 2);
      // file-2 的磁盘文件不存在，应直接用草稿内容
      expect(loaded[0].id, 'file-1');
      expect(loaded[0].content, '内容1');
      expect(loaded[0].isDirty, true);
      expect(loaded[1].id, 'file-2');
      expect(loaded[1].content, '内容2');
    });

    test('loadDrafts 草稿文件不存在应返回空列表', () async {
      final loaded = await draftService.loadDrafts();
      expect(loaded, isEmpty);
    });

    test('loadDrafts 草稿更新应优先使用草稿内容', () async {
      // 创建磁盘文件
      final diskPath = '${tempDir.path}/disk_file.txt';
      final diskFile = File(diskPath);
      await diskFile.writeAsString('磁盘内容');
      // 等待确保草稿时间更晚
      await Future.delayed(const Duration(milliseconds: 50));

      // 创建草稿（内容与磁盘不同，时间更新）
      final draft = NoteFile(
        id: 'test-id',
        title: 'disk_file.txt',
        filePath: diskPath,
        content: '草稿内容（未保存）',
        diskContent: '磁盘内容',
        isDirty: true,
        lastModified: DateTime.now(),
        lastSavedAt: DateTime.now().subtract(const Duration(minutes: 1)),
        isNew: false,
      );

      await draftService.saveDrafts([draft]);
      final loaded = await draftService.loadDrafts();

      expect(loaded.length, 1);
      expect(loaded[0].content, '草稿内容（未保存）');
      expect(loaded[0].isDirty, true);
    });

    test('clearDrafts 应删除草稿文件', () async {
      final file = NoteFile(
        id: 'clear-test',
        title: '测试.txt',
        content: '内容',
        isDirty: false,
        lastModified: DateTime.now(),
      );

      await draftService.saveDrafts([file]);
      await draftService.clearDrafts();

      final loaded = await draftService.loadDrafts();
      expect(loaded, isEmpty);
    });

    test('startAutoSave 和 stopAutoSave 应正常工作', () {
      draftService.startAutoSave(() async => []);
      draftService.stopAutoSave();
      // 无异常即通过
    });
  });
}
