import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/models/note_file.dart';
import 'package:notepad/services/encoding_service.dart';
import 'package:notepad/services/file_service.dart';
import 'package:notepad/services/file_watch_service.dart';

void main() {
  late Directory tempDir;
  late FileService fileService;
  late FileWatchService watchService;
  late List<NoteFile> files;
  late List<String> changedIds;
  late List<String> changedContents;
  late List<String> deletedIds;
  late bool failNextRead;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('notepad_watch_test_');
    fileService = FileService();
    failNextRead = false;
    watchService = FileWatchService(
      encodingService: const EncodingService(),
      readBytes: (path) async {
        if (failNextRead) {
          failNextRead = false;
          throw FileSystemException('模拟临时读取失败', path);
        }
        return File(path).readAsBytes();
      },
    );
    files = [];
    changedIds = [];
    changedContents = [];
    deletedIds = [];
    watchService.onExternalChange = (file, content) {
      changedIds.add(file.id);
      changedContents.add(content);
    };
    watchService.onFileDeleted = (file) => deletedIds.add(file.id);
  });

  tearDown(() {
    watchService.stop();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  /// 创建磁盘文件并打开，加入监听列表。
  NoteFile openTempFile(String name, String content) {
    final path = '${tempDir.path}/$name';
    File(path).writeAsStringSync(content);
    final file = fileService.openFile(path);
    files.add(file);
    return file;
  }

  /// 修改磁盘内容并确保 mtime 变化。
  void modifyOnDisk(NoteFile file, String content) {
    final f = File(file.filePath!);
    f.writeAsStringSync(content);
    f.setLastModifiedSync(DateTime.now().add(const Duration(seconds: 5)));
  }

  group('FileWatchService', () {
    test('启动后首次检查不应对已有文件误报', () async {
      openTempFile('a.txt', '原内容');
      watchService.start(() => files);

      await watchService.checkNow();

      expect(changedIds, isEmpty);
      expect(deletedIds, isEmpty);
    });

    test('外部修改应触发回调并携带新内容', () async {
      final file = openTempFile('a.txt', '原内容');
      watchService.start(() => files);

      modifyOnDisk(file, '外部新内容');
      await watchService.checkNow();

      expect(changedIds, [file.id]);
      expect(changedContents, ['外部新内容']);
    });

    test('自身保存（内容与快照一致）不应触发回调', () async {
      final file = openTempFile('a.txt', '原内容');
      watchService.start(() => files);

      // 模拟本应用保存：磁盘内容与 diskContent 快照一致，仅 mtime 变化
      modifyOnDisk(file, file.diskContent!);
      await watchService.checkNow();

      expect(changedIds, isEmpty);
    });

    test('用户保留本地修改后不应重复触发', () async {
      final file = openTempFile('a.txt', '原内容');
      watchService.start(() => files);

      modifyOnDisk(file, '外部新内容');
      await watchService.checkNow();
      expect(changedIds.length, 1);

      // 模拟用户选择「保留我的修改」：不更新快照，再次检查不应再触发
      await watchService.checkNow();
      expect(changedIds.length, 1);
    });

    test('文件删除应只触发一次', () async {
      final file = openTempFile('a.txt', '原内容');
      watchService.start(() => files);

      File(file.filePath!).deleteSync();
      await watchService.checkNow();
      expect(deletedIds, [file.id]);

      await watchService.checkNow();
      expect(deletedIds.length, 1);
    });

    test('未保存新文件不应参与监听', () async {
      files.add(fileService.createNewFile());
      watchService.start(() => files);

      await watchService.checkNow();

      expect(changedIds, isEmpty);
      expect(deletedIds, isEmpty);
    });

    test('stop 后不应继续监听', () async {
      final file = openTempFile('a.txt', '原内容');
      watchService.start(() => files);
      watchService.stop();

      modifyOnDisk(file, '外部新内容');
      await watchService.checkNow();

      expect(changedIds, isEmpty);
    });

    test('监听启动后新打开的文件不应漏掉首次轮询前的修改', () async {
      watchService.start(() => files);
      final file = openTempFile('a.txt', '原内容');

      modifyOnDisk(file, '首次轮询前的外部修改');
      await watchService.checkNow();

      expect(changedIds, [file.id]);
      expect(changedContents, ['首次轮询前的外部修改']);
    });

    test('mtime 与内容长度不变时仍应检测外部修改', () async {
      final file = openTempFile('a.txt', 'aa');
      watchService.start(() => files);
      final originalModified = FileStat.statSync(file.filePath!).modified;

      File(file.filePath!).writeAsStringSync('bb');
      File(file.filePath!).setLastModifiedSync(originalModified);
      await watchService.checkNow();

      expect(changedIds, [file.id]);
      expect(changedContents, ['bb']);
    });

    test('临时读取失败后应重试而不是吞掉外部修改', () async {
      final file = openTempFile('a.txt', '原内容');
      watchService.start(() => files);
      modifyOnDisk(file, '外部新内容');

      failNextRead = true;
      await watchService.checkNow();
      expect(changedIds, isEmpty);

      await watchService.checkNow();
      expect(changedIds, [file.id]);
      expect(changedContents, ['外部新内容']);
    });

    test('已打开文件增大超过阈值后不应全量读取且只提示一次', () async {
      fileService = FileService(readOnlyThresholdBytes: 5, maxFileBytes: 20);
      var readCount = 0;
      watchService = FileWatchService(
        encodingService: const EncodingService(),
        fileService: fileService,
        readBytes: (path) async {
          readCount++;
          return File(path).readAsBytes();
        },
      );
      watchService.onExternalChange = (file, content) {
        changedIds.add(file.id);
        changedContents.add(content);
      };
      final oversizedIds = <String>[];
      watchService.onFileTooLarge = (file, size) => oversizedIds.add(file.id);
      final file = openTempFile('grown.txt', 'aa');
      watchService.start(() => files);

      modifyOnDisk(file, '0123456789');
      await watchService.checkNow();
      await watchService.checkNow();

      expect(readCount, 0);
      expect(changedIds, isEmpty);
      expect(oversizedIds, [file.id]);
    });

    test('GBK 文件外部修改应按文件编码解码', () async {
      final path = '${tempDir.path}/gbk.txt';
      // '中文' 的 GBK 字节
      File(path).writeAsBytesSync([0xD6, 0xD0, 0xCE, 0xC4]);
      final file = fileService.openFile(path);
      files.add(file);
      expect(file.encoding, EncodingService.gbkName);
      watchService.start(() => files);

      // 外部改为 '测试' 的 GBK 字节
      final f = File(path);
      f.writeAsBytesSync([0xB2, 0xE2, 0xCA, 0xD4]);
      f.setLastModifiedSync(DateTime.now().add(const Duration(seconds: 5)));
      await watchService.checkNow();

      expect(changedContents, ['测试']);
    });
  });
}
