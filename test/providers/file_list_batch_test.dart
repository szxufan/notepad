/// 文件列表批量操作测试：批量关闭、拖拽排序、重命名、只读守卫。
library providers.file_list_batch_test;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/models/note_file.dart';
import 'package:notepad/providers/file_list_provider.dart';
import 'package:notepad/services/file_service.dart';
import 'package:path/path.dart' as p;

class _DeferredSaveRequest {
  _DeferredSaveRequest(this.file);

  final NoteFile file;
  final completer = Completer<NoteFile>();

  void complete({String? path}) {
    final now = DateTime.now();
    completer.complete(file.copyWith(
      filePath: path,
      title: path == null ? file.title : p.basename(path),
      diskContent: file.content,
      isDirty: false,
      lastModified: now,
      lastSavedAt: now,
      isNew: false,
    ));
  }
}

class _DeferredSaveService extends FileService {
  final requests = <_DeferredSaveRequest>[];

  @override
  Future<NoteFile> saveFile(NoteFile file) {
    final request = _DeferredSaveRequest(file);
    requests.add(request);
    return request.completer.future;
  }

  @override
  Future<NoteFile?> saveFileAs(NoteFile file) async {
    final request = _DeferredSaveRequest(file);
    requests.add(request);
    return request.completer.future;
  }
}

void main() {
  late FileService fileService;
  late FileListProvider provider;
  late Directory tempDir;

  setUp(() {
    fileService = FileService();
    fileService.resetUntitledCounter();
    provider = FileListProvider(fileService: fileService);
    tempDir = Directory.systemTemp.createTempSync('notepad_batch_test_');
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

  NoteFile makeFile(
    String id, {
    bool dirty = false,
    String? path,
    bool readOnly = false,
  }) {
    return NoteFile(
      id: id,
      title: '$id.txt',
      filePath: path,
      content: dirty ? '本地修改' : '内容',
      diskContent: '内容',
      isDirty: dirty,
      lastModified: DateTime.now(),
      isReadOnly: readOnly,
    );
  }

  group('批量关闭', () {
    test('closeFiles 应只关闭指定 ID', () {
      provider.loadFromDrafts([makeFile('a'), makeFile('b'), makeFile('c')]);

      final removed = provider.closeFiles(['a', 'c', 'missing']);

      expect(removed.map((f) => f.id), ['a', 'c']);
      expect(provider.files.single.id, 'b');
    });

    test('closeFiles 空列表应返回空列表', () {
      provider.loadFromDrafts([makeFile('a')]);

      expect(provider.closeFiles([]), isEmpty);
      expect(provider.files.length, 1);
    });

    test('closeFiles 活动文件被移除时应切换到剩余首个', () {
      provider.loadFromDrafts([
        makeFile('a'),
        makeFile('b', dirty: true),
        makeFile('c'),
      ]);
      provider.switchToFile('a');

      final removed = provider.closeFiles(['a', 'c']);

      expect(removed.map((f) => f.id), ['a', 'c']);
      expect(provider.files.single.id, 'b');
      expect(provider.activeFileId, 'b');
    });

    test('closeFiles 关闭全部应清空活动', () {
      provider.loadFromDrafts([makeFile('a'), makeFile('b', dirty: true)]);

      final removed = provider.closeFiles(['a', 'b']);

      expect(removed.map((f) => f.id), ['a', 'b']);
      expect(provider.isEmpty, true);
      expect(provider.activeFileId, isNull);
    });

    test('closeFiles 未移除活动文件时应保持活动', () {
      provider.loadFromDrafts([makeFile('a'), makeFile('b', dirty: true)]);
      provider.switchToFile('b');

      provider.closeFiles(['a']);

      expect(provider.activeFileId, 'b');
    });
  });

  group('reorderFiles', () {
    test('前移应直接使用目标索引', () {
      provider.loadFromDrafts([makeFile('a'), makeFile('b'), makeFile('c')]);

      provider.reorderFiles(2, 0);

      expect(provider.files.map((f) => f.id), ['c', 'a', 'b']);
    });

    test('后移应使用移除后的目标索引', () {
      provider.loadFromDrafts([makeFile('a'), makeFile('b'), makeFile('c')]);

      provider.reorderFiles(0, 2);

      expect(provider.files.map((f) => f.id), ['b', 'c', 'a']);
    });

    test('相同索引不应改变顺序', () {
      provider.loadFromDrafts([makeFile('a'), makeFile('b'), makeFile('c')]);

      provider.reorderFiles(1, 1);

      expect(provider.files.map((f) => f.id), ['a', 'b', 'c']);
    });

    test('非法 oldIndex 不应改变顺序', () {
      provider.loadFromDrafts([makeFile('a'), makeFile('b')]);

      provider.reorderFiles(5, 0);
      provider.reorderFiles(-1, 0);

      expect(provider.files.map((f) => f.id), ['a', 'b']);
    });

    test('排序不应改变活动文件', () {
      provider.loadFromDrafts([makeFile('a'), makeFile('b'), makeFile('c')]);
      provider.switchToFile('b');

      provider.reorderFiles(0, 2);

      expect(provider.activeFileId, 'b');
    });
  });

  group('renameFile', () {
    test('应重命名磁盘文件并更新列表', () {
      final path = '${tempDir.path}/old.txt';
      File(path).writeAsStringSync('内容');
      provider.openFile(path);
      final id = provider.activeFileId!;

      provider.renameFile(id, 'new.txt');

      expect(provider.getFile(id)!.title, 'new.txt');
      expect(provider.getFile(id)!.filePath, p.join(tempDir.path, 'new.txt'));
      expect(File('${tempDir.path}/new.txt').existsSync(), true);
    });

    test('目标已存在应抛出异常且列表不变', () {
      final path = '${tempDir.path}/old.txt';
      File(path).writeAsStringSync('内容');
      File('${tempDir.path}/new.txt').writeAsStringSync('占用');
      provider.openFile(path);
      final id = provider.activeFileId!;

      expect(
        () => provider.renameFile(id, 'new.txt'),
        throwsA(isA<FileSystemException>()),
      );
      expect(provider.getFile(id)!.title, 'old.txt');
    });
  });

  group('异步保存', () {
    test('保存期间排序后应按 ID 合并结果', () async {
      final service = _DeferredSaveService();
      provider = FileListProvider(fileService: service);
      provider.loadFromDrafts([
        makeFile('a', dirty: true, path: '${tempDir.path}/a.txt'),
        makeFile('b'),
      ]);

      final saving = provider.saveFile('a');
      provider.reorderFiles(0, 1);
      service.requests.single.complete();
      await saving;

      expect(provider.files.map((f) => f.id), ['b', 'a']);
      expect(provider.getFile('b')!.content, '内容');
      expect(provider.getFile('a')!.isDirty, false);
    });

    test('保存期间的新编辑不应被旧快照覆盖', () async {
      final service = _DeferredSaveService();
      provider = FileListProvider(fileService: service);
      provider.loadFromDrafts([
        makeFile('a', dirty: true, path: '${tempDir.path}/a.txt'),
      ]);

      final saving = provider.saveFile('a');
      provider.updateContent('a', '保存期间的新修改');
      service.requests.single.complete();
      await saving;

      final file = provider.getFile('a')!;
      expect(file.content, '保存期间的新修改');
      expect(file.diskContent, '本地修改');
      expect(file.isDirty, true);
    });

    test('另存为期间排序和编辑仍应保留最新内容', () async {
      final service = _DeferredSaveService();
      provider = FileListProvider(fileService: service);
      provider.loadFromDrafts([makeFile('a', dirty: true), makeFile('b')]);

      final saving = provider.saveFileAs('a');
      provider.reorderFiles(0, 1);
      provider.updateContent('a', '另存为期间的新修改');
      final path = '${tempDir.path}/saved.txt';
      service.requests.single.complete(path: path);

      expect(await saving, true);
      expect(provider.files.map((f) => f.id), ['b', 'a']);
      final file = provider.getFile('a')!;
      expect(file.filePath, path);
      expect(file.content, '另存为期间的新修改');
      expect(file.diskContent, '本地修改');
      expect(file.isDirty, true);
    });

    test('保存等待期间关闭文件不应回写其他条目', () async {
      final service = _DeferredSaveService();
      provider = FileListProvider(fileService: service);
      provider.loadFromDrafts([
        makeFile('a', dirty: true, path: '${tempDir.path}/a.txt'),
        makeFile('b'),
      ]);

      final saving = provider.saveFile('a');
      provider.closeFile('a');
      service.requests.single.complete();
      await saving;

      expect(provider.files.single.id, 'b');
    });
  });

  group('只读守卫', () {
    test('updateContent 应忽略只读文件的内容变更', () {
      provider.loadFromDrafts([makeFile('r', readOnly: true)]);

      provider.updateContent('r', '尝试修改');

      expect(provider.getFile('r')!.content, '内容');
      expect(provider.getFile('r')!.isDirty, false);
    });

    test('saveFile 不应写入只读文件', () async {
      final path = '${tempDir.path}/ro.txt';
      File(path).writeAsStringSync('磁盘内容');
      provider.loadFromDrafts([makeFile('r', path: path, readOnly: true)]);

      await provider.saveFile('r');

      expect(File(path).readAsStringSync(), '磁盘内容');
    });

    test('saveFileAs 对只读文件应返回 false', () async {
      provider.loadFromDrafts([makeFile('r', readOnly: true)]);

      expect(await provider.saveFileAs('r'), false);
    });

    test('普通文件的内容变更不受影响', () {
      provider.loadFromDrafts([makeFile('n')]);

      provider.updateContent('n', '新内容');

      expect(provider.getFile('n')!.content, '新内容');
      expect(provider.getFile('n')!.isDirty, true);
    });
  });
}
