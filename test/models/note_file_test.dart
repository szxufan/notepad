import 'package:flutter_test/flutter_test.dart';
import 'package:notepad/models/note_file.dart';

void main() {
  group('NoteFile', () {
    test('fromJson 应正确反序列化', () {
      final json = {
        'id': 'test-id',
        'title': '测试文件.txt',
        'filePath': '/tmp/test.txt',
        'content': 'hello world',
        'diskContent': 'hello',
        'isDirty': true,
        'lastModified': '2024-01-01T00:00:00.000',
        'lastSavedAt': '2024-01-02T00:00:00.000',
        'isNew': false,
      };

      final note = NoteFile.fromJson(json);

      expect(note.id, 'test-id');
      expect(note.title, '测试文件.txt');
      expect(note.filePath, '/tmp/test.txt');
      expect(note.content, 'hello world');
      expect(note.diskContent, 'hello');
      expect(note.isDirty, true);
      expect(note.lastModified, DateTime.parse('2024-01-01T00:00:00.000'));
      expect(note.lastSavedAt, DateTime.parse('2024-01-02T00:00:00.000'));
      expect(note.isNew, false);
    });

    test('toJson 应正确序列化', () {
      final note = NoteFile(
        id: 'test-id',
        title: '测试.txt',
        filePath: '/tmp/test.txt',
        content: '内容',
        diskContent: '旧内容',
        isDirty: true,
        lastModified: DateTime.parse('2024-01-01T00:00:00.000'),
        lastSavedAt: DateTime.parse('2024-01-02T00:00:00.000'),
        isNew: false,
      );

      final json = note.toJson();

      expect(json['id'], 'test-id');
      expect(json['title'], '测试.txt');
      expect(json['filePath'], '/tmp/test.txt');
      expect(json['content'], '内容');
      expect(json['diskContent'], '旧内容');
      expect(json['isDirty'], true);
      expect(json['lastModified'], '2024-01-01T00:00:00.000');
      expect(json['lastSavedAt'], '2024-01-02T00:00:00.000');
      expect(json['isNew'], false);
    });

    test('fromJson/toJson 应可往返转换', () {
      final original = NoteFile(
        id: 'round-trip',
        title: '往返.txt',
        filePath: null,
        content: '测试内容',
        isDirty: true,
        lastModified: DateTime.parse('2024-03-01T12:00:00.000'),
        isNew: true,
      );

      final json = original.toJson();
      final restored = NoteFile.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.filePath, original.filePath);
      expect(restored.content, original.content);
      expect(restored.isDirty, original.isDirty);
      expect(restored.lastModified, original.lastModified);
      expect(restored.isNew, original.isNew);
    });

    test('copyWith 应正确复制并覆盖字段', () {
      final note = NoteFile(
        id: 'original',
        title: '原.txt',
        content: '原内容',
        isDirty: false,
        lastModified: DateTime.now(),
      );

      final copied = note.copyWith(
        content: '新内容',
        isDirty: true,
      );

      expect(copied.id, 'original');
      expect(copied.title, '原.txt');
      expect(copied.content, '新内容');
      expect(copied.isDirty, true);
    });

    test('相等性应基于 id', () {
      final now = DateTime.now();
      final a = NoteFile(
        id: 'same-id',
        title: 'A',
        content: 'a',
        isDirty: false,
        lastModified: now,
      );
      final b = NoteFile(
        id: 'same-id',
        title: 'B',
        content: 'b',
        isDirty: true,
        lastModified: now,
      );

      expect(a == b, true);
      expect(a.hashCode, b.hashCode);
    });
  });
}
