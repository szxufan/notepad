/// 应用入口。
///
/// 初始化草稿服务、加载草稿、注册 Provider、
/// 监听窗口关闭事件保存草稿。
library main;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/home_page.dart';
import 'providers/cursor_provider.dart';
import 'providers/editor_provider.dart';
import 'providers/file_list_provider.dart';
import 'services/ai_config_service.dart';
import 'services/ai_text_service.dart';
import 'services/ai_title_service.dart';
import 'services/draft_service.dart';
import 'services/encoding_service.dart';
import 'services/file_service.dart';
import 'services/file_watch_service.dart';

/// 草稿服务实例（全局引用，用于窗口关闭时保存）。
late DraftService _draftService;

/// 文件列表 Provider 实例（全局引用，用于窗口关闭时获取文件列表）。
late FileListProvider _fileListProvider;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化服务
  const encodingService = EncodingService();
  _draftService = DraftService(encodingService: encodingService);
  final fileService = FileService(encodingService: encodingService);
  final fileWatchService = FileWatchService(encodingService: encodingService);
  final aiConfigService = AiConfigService();
  final aiTitleService = AiTitleService();
  final aiTextService = AiTextService();
  await aiConfigService.load();
  _fileListProvider = FileListProvider(
    fileService: fileService,
    aiTitleService: aiTitleService,
    aiConfigGetter: () => aiConfigService.config,
  );

  // 加载草稿
  final drafts = await _draftService.loadDrafts();
  _fileListProvider.loadFromDrafts(drafts);

  // 启动自动保存
  _draftService.startAutoSave(() async => _fileListProvider.allFiles);

  // 注册窗口关闭监听
  // AppLifecycleListener 通过构造注册到 WidgetsBinding，不会被 GC
  AppLifecycleListener(
    onHide: () {
      // 双保险：窗口隐藏时立即保存草稿
      _draftService.saveDrafts(_fileListProvider.allFiles);
    },
    onExitRequested: () async {
      // 窗口关闭请求时同步保存草稿
      await _draftService.saveDrafts(_fileListProvider.allFiles);
      _draftService.stopAutoSave();
      return AppExitResponse.exit;
    },
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<FileListProvider>.value(
          value: _fileListProvider,
        ),
        ChangeNotifierProvider<EditorProvider>(
          create: (_) => EditorProvider(),
        ),
        ChangeNotifierProvider<CursorProvider>(
          create: (_) => CursorProvider(),
        ),
        Provider<DraftService>.value(value: _draftService),
        Provider<FileService>.value(value: fileService),
        Provider<EncodingService>.value(value: encodingService),
        Provider<FileWatchService>.value(value: fileWatchService),
        Provider<AiConfigService>.value(value: aiConfigService),
        Provider<AiTitleService>.value(value: aiTitleService),
        Provider<AiTextService>.value(value: aiTextService),
      ],
      child: const NotepadApp(),
    ),
  );
}

/// 应用根 Widget。
class NotepadApp extends StatelessWidget {
  const NotepadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '记事本',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2196F3),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF2196F3),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const HomePage(),
    );
  }
}
