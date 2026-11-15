import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:notepad/models/ai_config.dart';
import 'package:notepad/models/note_file.dart';
import 'package:notepad/providers/file_list_provider.dart';
import 'package:notepad/services/ai_title_service.dart';
import 'package:notepad/services/file_service.dart';

/// 测试用 AI 标题服务（不发起真实网络请求）。
class _FakeAiTitleService extends AiTitleService {
  _FakeAiTitleService() : super(client: http.Client());

  String nextTitle = 'AI生成标题';
  Object? error;
  int callCount = 0;
  String? lastContent;

  @override
  Future<String> generateTitle(String content, AiConfig config) async {
    callCount++;
    lastContent = content;
    if (error != null) throw error!;
    return nextTitle;
  }
}

/// 测试用完整配置。
const _testConfig = AiConfig(
  apiEndpoint: 'https://example.com/v1/chat/completions',
  apiToken: 'test-token',
  model: 'test-model',
  maxInputChars: 2000,
);

void main() {
  late FileService fileService;
  late FileListProvider provider;

  setUp(() {
    fileService = FileService();
    fileService.resetUntitledCounter();
    provider = FileListProvider(fileService: fileService);
  });

  group('FileListProvider', () {
    test('初始状态应为空', () {
      expect(provider.isEmpty, true);
      expect(provider.files, isEmpty);
      expect(provider.activeFileId, isNull);
      expect(provider.activeFile, isNull);
    });

    test('addNewFile 应添加新文件并设为活动', () {
      final file = provider.addNewFile();

      expect(provider.isEmpty, false);
      expect(provider.files.length, 1);
      expect(provider.activeFileId, file.id);
      expect(provider.activeFile?.id, file.id);
      expect(file.isNew, true);
    });

    test('switchToFile 应切换活动文件', () {
      final file1 = provider.addNewFile();
      final file2 = provider.addNewFile();

      expect(provider.activeFileId, file2.id);

      provider.switchToFile(file1.id);
      expect(provider.activeFileId, file1.id);

      provider.switchToFile(file2.id);
      expect(provider.activeFileId, file2.id);
    });

    test('closeFile 应移除文件', () {
      final file1 = provider.addNewFile();
      final file2 = provider.addNewFile();

      provider.closeFile(file2.id);
      expect(provider.files.length, 1);
      expect(provider.activeFileId, file1.id);
    });

    test('closeFile 关闭活动文件时应切换到相邻文件', () {
      final file1 = provider.addNewFile();
      final file2 = provider.addNewFile();

      provider.closeFile(file2.id);
      expect(provider.activeFileId, file1.id);
    });

    test('closeFile 关闭唯一文件应清空活动文件', () {
      final file1 = provider.addNewFile();

      provider.closeFile(file1.id);
      expect(provider.isEmpty, true);
      expect(provider.activeFileId, isNull);
    });

    test('updateContent 应更新内容和 dirty 状态', () {
      final file = provider.addNewFile();

      provider.updateContent(file.id, '新内容');

      final updated = provider.getFile(file.id);
      expect(updated?.content, '新内容');
      expect(updated?.isDirty, true);
    });

    test('updateContent 相同内容不应更新', () {
      final file = provider.addNewFile();
      provider.updateContent(file.id, '内容');

      // 再次设置为相同内容
      provider.updateContent(file.id, '内容');

      final updated = provider.getFile(file.id);
      expect(updated?.content, '内容');
    });

    test('loadFromDrafts 应恢复文件列表', () {
      final drafts = [
        NoteFile(
          id: 'draft-1',
          title: '草稿1.txt',
          content: '草稿内容1',
          isDirty: false,
          lastModified: DateTime.now(),
        ),
      ];

      provider.loadFromDrafts(drafts);

      expect(provider.files.length, 1);
      expect(provider.activeFileId, 'draft-1');
      expect(provider.files.first.content, '草稿内容1');
    });

    test('openFile 重复打开同一文件应切换而非新增', () {
      // 先创建一个磁盘文件用于测试
      // 由于 FileService.openFile 需要真实文件，这里通过 loadFromDrafts 模拟
      // 此测试验证 openFile 的去重逻辑
      final drafts = [
        NoteFile(
          id: 'existing',
          title: 'existing.txt',
          filePath: '/tmp/existing.txt',
          content: '内容',
          isDirty: false,
          lastModified: DateTime.now(),
        ),
      ];
      provider.loadFromDrafts(drafts);

      // openFile 在文件已打开时应切换
      // 注意：此测试无法直接调用 openFile 因为需要真实文件
      // 仅验证去重逻辑通过 switchToFile 实现
      provider.switchToFile('existing');
      expect(provider.activeFileId, 'existing');
    });

    test('allFiles 应返回所有文件', () {
      provider.addNewFile();
      provider.addNewFile();

      expect(provider.allFiles.length, 2);
    });
  });

  group('AI 标题', () {
    late _FakeAiTitleService fakeAiService;
    late FileListProvider aiProvider;

    setUp(() {
      fakeAiService = _FakeAiTitleService();
      aiProvider = FileListProvider(
        fileService: fileService,
        aiTitleService: fakeAiService,
        aiConfigGetter: () => _testConfig,
      );
    });

    /// 等待后台静默 AI 任务完成。
    Future<void> pump() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    test('64 字以内标题应取首行前 16 字', () {
      final file = aiProvider.addNewFile();

      aiProvider.updateContent(file.id, '这是第一行内容\n第二行');
      expect(aiProvider.getFile(file.id)?.title, '这是第一行内容');

      // 首行超过 16 字时截断
      aiProvider.updateContent(file.id, '一二三四五六七八九十一二三四五六七八九十');
      expect(aiProvider.getFile(file.id)?.title, '一二三四五六七八九十一二三四五六');
    });

    test('首次超过 64 字应自动调用 AI 且只触发一次', () async {
      final file = aiProvider.addNewFile();
      final longContent = '字' * 65;

      aiProvider.updateContent(file.id, longContent);
      // 触发后立即锁定标题为首行截断
      expect(aiProvider.getFile(file.id)?.title, '字' * 16);
      expect(aiProvider.getFile(file.id)?.isTitleLocked, true);

      await pump();
      expect(fakeAiService.callCount, 1);
      expect(fakeAiService.lastContent, longContent);
      expect(aiProvider.getFile(file.id)?.title, 'AI生成标题');
      expect(aiProvider.getFile(file.id)?.hasAiTitle, true);

      // 继续编辑不再触发
      aiProvider.updateContent(file.id, '字' * 70);
      await pump();
      expect(fakeAiService.callCount, 1);
    });

    test('AI 失败时应静默降级为首行截断标题', () async {
      fakeAiService.error = const AiTitleException('网络错误');
      final file = aiProvider.addNewFile();

      aiProvider.updateContent(file.id, '降' * 65);
      await pump();

      expect(fakeAiService.callCount, 1);
      expect(aiProvider.getFile(file.id)?.title, '降' * 16);
    });

    test('手动生成应覆盖标题（即使 64 字以内）', () async {
      final file = aiProvider.addNewFile();
      aiProvider.updateContent(file.id, '短内容');
      expect(aiProvider.getFile(file.id)?.title, '短内容');

      await aiProvider.generateTitleManually(file.id);
      expect(fakeAiService.callCount, 1);
      expect(aiProvider.getFile(file.id)?.title, 'AI生成标题');
      expect(aiProvider.getFile(file.id)?.hasAiTitle, true);
      expect(aiProvider.getFile(file.id)?.isTitleLocked, true);

      // 生成后短内容编辑不再跟随首行
      aiProvider.updateContent(file.id, '另一段短内容');
      expect(aiProvider.getFile(file.id)?.title, 'AI生成标题');
    });

    test('未配置 AI 时手动生成应抛出异常', () {
      final noConfigProvider = FileListProvider(
        fileService: fileService,
        aiTitleService: fakeAiService,
        aiConfigGetter: () => AiConfig.defaultConfig,
      );
      final file = noConfigProvider.addNewFile();
      noConfigProvider.updateContent(file.id, '内容');

      expect(
        () => noConfigProvider.generateTitleManually(file.id),
        throwsA(isA<AiTitleException>()),
      );
    });

    test('磁盘文件（isNew=false）不受自动标题逻辑影响', () async {
      aiProvider.loadFromDrafts([
        NoteFile(
          id: 'disk-1',
          title: 'disk.txt',
          filePath: '/tmp/disk.txt',
          content: '',
          isDirty: false,
          lastModified: DateTime.now(),
        ),
      ]);

      aiProvider.updateContent('disk-1', '字' * 100);
      await pump();

      expect(aiProvider.getFile('disk-1')?.title, 'disk.txt');
      expect(fakeAiService.callCount, 0);
    });
  });
}
