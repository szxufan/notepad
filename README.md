# 记事本 (Notepad)

一个基于 Flutter 的桌面端纯文本记事本应用，支持多文件编辑、查找替换、草稿自动保存与恢复、大文件只读保护与 Windows 单实例集成。

## 功能特性

- **多文件编辑**：左侧文件列表，支持同时打开多个文件进行编辑
  - 打开对话框支持**多选**
  - 列表支持**拖拽排序**（顺序随草稿持久化）
  - 右键菜单：**重命名**磁盘文件、**关闭其他 / 关闭已保存 / 关闭全部**（未保存修改统一确认，可全部保存）
- **纯文本编辑**：右侧编辑区域，使用等宽字体
- **编码支持**：打开时自动检测 UTF-8 / UTF-8 BOM / UTF-16 LE/BE / GBK / Windows-1252，保存时沿用原编码；点击状态栏编码名可手动切换（GB18030 四字节字符暂不支持）
- **字体缩放**：`Ctrl+滚轮`（macOS 上支持 `Cmd+滚轮`）调节字体大小
- **查找替换**：支持查找、替换、全部替换、正则表达式，匹配高亮显示；选中文本后按 `Ctrl+F` / `Ctrl+H` 会自动填入查找框
- **全局搜索**：`Ctrl+Shift+F` 在所有打开的文件中搜索，点击结果跳转
- **拖拽打开**：将文件拖入窗口即可打开（支持多个文件）
- **大文件保护**：超过 10 MB 的文件以**只读模式**打开（不可编辑/保存），超过 50 MB 拒绝打开，避免卡顿与数据损坏
- **原子保存**：先写临时文件再重命名覆盖，写入中途崩溃不会损坏原文件
- **状态栏信息**：光标行列、字符数（含选区计数）、文件编码、字号、修改状态
- **外部修改监听**：文件被其他程序修改时，无本地修改自动重载，有未保存修改时询问是否重载；文件被外部删除时提示
- **AI 标题**：新建未保存文件内容超过阈值后自动生成标题（需在设置中配置 AI 接口）
- **AI 文本操作**：选中文本后右键菜单提供摘要、润色、翻译；结果先预览再应用，翻译可选「替换原文」或「保留原文插入」，目标语言在 AI 设置中配置；选区长度受「最大输入字数」限制
- **草稿自动保存**：每 30 秒自动保存草稿，防止掉电丢失
- **关闭窗口保留草稿**：关闭窗口时自动保存所有打开文件
- **启动自动恢复**：下次启动时自动加载上次打开的所有文件
- **命令行与单实例**（Windows）：`notepad.exe a.txt b.txt` 直接打开文件；重复启动时文件转发到已有窗口并前置
- **文件关联**（Windows）：安装时可选将 `.txt` 关联到本应用；始终注册到「打开方式」菜单
- **跨平台支持**：Linux、Windows、macOS

## 快捷键

| 快捷键 | 功能 |
|--------|------|
| `Ctrl+N` / `Cmd+N` | 新建文件 |
| `Ctrl+O` / `Cmd+O` | 打开文件（可多选） |
| `Ctrl+S` / `Cmd+S` | 保存文件 |
| `Ctrl+Shift+S` / `Cmd+Shift+S` | 另存为 |
| `Ctrl+F` / `Cmd+F` | 查找（选中文本自动填入） |
| `Ctrl+Shift+F` / `Cmd+Shift+F` | 全局搜索 |
| `Ctrl+H` / `Cmd+H` | 替换（选中文本自动填入） |
| `F3` / `Shift+F3` | 下一个 / 上一个匹配 |
| `Ctrl+F4` | 关闭当前文件 |
| `Ctrl+滚轮` / `Cmd+滚轮` | 调节字体大小 |

## 大文件说明

| 文件大小 | 行为 |
|----------|------|
| ≤ 10 MB | 正常打开编辑 |
| 10 MB ~ 50 MB | 只读模式打开：仅加载开头 1 MB 预览显示（避免全量渲染冻结 UI），顶部横幅提示，禁止编辑/保存/替换，草稿不持久化其内容，外部修改监听跳过该文件 |
| > 50 MB | 拒绝打开并提示 |

只读文件恢复会话时从磁盘重新读取预览。单文件搜索匹配上限 1000 条，超出部分不再高亮。

## 命令行与单实例（Windows）

```bash
notepad.exe a.txt b.txt     # 启动并打开文件（相对路径自动规范化）
notepad.exe c.txt           # 已有实例运行时：转发到已有窗口并前置，不新建窗口
```

安装包（Inno Setup）提供可选任务「将 .txt 文件关联到 Notepad」（默认不勾选，尊重系统现有关联）；无论是否勾选，应用都会注册到右键「打开方式」菜单。卸载时清理关联注册。

## 项目结构

```
lib/
├── main.dart                    # 应用入口（接收命令行参数）
├── models/
│   ├── note_file.dart           # 笔记文件数据模型
│   └── ai_config.dart           # AI 接口配置模型
├── providers/
│   ├── file_list_provider.dart  # 文件列表状态管理（含批量关闭/排序/重命名）
│   ├── editor_provider.dart     # 编辑器状态管理
│   └── cursor_provider.dart     # 光标位置状态（轻量通知器）
├── services/
│   ├── file_service.dart        # 文件读写服务（原子保存/大小分级/重命名）
│   ├── draft_service.dart       # 草稿管理服务
│   ├── encoding_service.dart    # 编码检测与编解码
│   ├── file_watch_service.dart  # 外部修改监听
│   ├── ai_config_service.dart   # AI 配置持久化
│   ├── ai_chat_client.dart      # AI 聊天接口通用客户端
│   ├── ai_title_service.dart    # AI 标题生成
│   └── ai_text_service.dart     # AI 摘要/润色/翻译
├── widgets/
│   ├── file_list_panel.dart     # 左侧文件列表面板
│   ├── editor_panel.dart        # 右侧编辑区域
│   ├── find_replace_bar.dart    # 查找替换栏
│   ├── global_search_panel.dart # 全局搜索面板
│   ├── status_bar.dart          # 底部状态栏
│   ├── ai_settings_dialog.dart  # AI 设置对话框
│   ├── ai_text_result_dialog.dart # AI 文本结果预览对话框
│   └── highlighting_controller.dart # 高亮文本控制器
└── pages/
    └── home_page.dart           # 主页面布局（快捷键/拖拽/文件转发通道）
```

Windows 单实例与文件转发位于 `windows/runner/single_instance.cpp`（命名互斥量 + 消息窗口 WM_COPYDATA），经 `notepad/app` MethodChannel 送达 Dart。

## 构建与运行

### 环境要求

- Flutter 3.x
- Dart SDK >= 3.0.0

### 安装依赖

```bash
flutter pub get
```

### 运行

```bash
# Linux
flutter run -d linux

# Windows
flutter run -d windows

# macOS
flutter run -d macos
```

### 构建

```bash
# Linux
flutter build linux

# Windows
flutter build windows

# macOS
flutter build macos
```

### 测试

```bash
flutter test
```

### 静态分析

```bash
flutter analyze
```

## 草稿机制说明

- 所有打开的文件（包括已保存和未保存的）都存储在应用数据目录下的 `drafts.json` 中
- 每 30 秒自动保存一次草稿
- 关闭窗口时同步保存草稿
- 启动时恢复上次打开的文件列表
- 对已保存文件，比较草稿时间与磁盘文件修改时间，草稿更新则用草稿内容，否则读取磁盘内容
- 未保存文件直接用草稿内容恢复
- 草稿包含文件编码字段，旧版草稿缺失时按 UTF-8 处理
- 只读大文件仅记录元信息（不存内容），恢复时从磁盘重读

## 技术栈

| 项目 | 选择 |
|------|------|
| 框架 | Flutter 3.x |
| 状态管理 | provider |
| 文件存储 | path_provider |
| 文件对话框 | file_selector |
| UUID 生成 | uuid |
| 编码检测/转换 | charset |
| 拖拽打开 | desktop_drop |
| 草稿持久化 | JSON 文件 |
| Windows 安装包 | Inno Setup 6 |
