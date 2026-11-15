# 记事本 (Notepad)

一个基于 Flutter 的桌面端纯文本记事本应用，支持多文件编辑、查找替换、草稿自动保存与恢复。

## 功能特性

- **多文件编辑**：左侧文件列表，支持同时打开多个文件进行编辑
- **纯文本编辑**：右侧编辑区域，使用等宽字体
- **字体缩放**：`Ctrl+滚轮`（macOS 上支持 `Cmd+滚轮`）调节字体大小
- **查找替换**：支持查找、替换、全部替换、正则表达式，匹配高亮显示；选中文本后按 `Ctrl+F` / `Ctrl+H` 会自动填入查找框
- **草稿自动保存**：每 30 秒自动保存草稿，防止掉电丢失
- **关闭窗口保留草稿**：关闭窗口时自动保存所有打开文件
- **启动自动恢复**：下次启动时自动加载上次打开的所有文件
- **跨平台支持**：Linux、Windows、macOS

## 快捷键

| 快捷键 | 功能 |
|--------|------|
| `Ctrl+N` / `Cmd+N` | 新建文件 |
| `Ctrl+O` / `Cmd+O` | 打开文件 |
| `Ctrl+S` / `Cmd+S` | 保存文件 |
| `Ctrl+Shift+S` / `Cmd+Shift+S` | 另存为 |
| `Ctrl+F` / `Cmd+F` | 查找（选中文本自动填入） |
| `Ctrl+H` / `Cmd+H` | 替换（选中文本自动填入） |
| `Ctrl+F4` | 关闭当前文件 |
| `Ctrl+滚轮` / `Cmd+滚轮` | 调节字体大小 |

## 项目结构

```
lib/
├── main.dart                    # 应用入口
├── models/
│   └── note_file.dart           # 笔记文件数据模型
├── providers/
│   ├── file_list_provider.dart  # 文件列表状态管理
│   └── editor_provider.dart     # 编辑器状态管理
├── services/
│   ├── file_service.dart        # 文件读写服务
│   └── draft_service.dart       # 草稿管理服务
├── widgets/
│   ├── file_list_panel.dart     # 左侧文件列表面板
│   ├── editor_panel.dart        # 右侧编辑区域
│   ├── find_replace_bar.dart    # 查找替换栏
│   ├── status_bar.dart          # 底部状态栏
│   └── highlighting_controller.dart # 高亮文本控制器
└── pages/
    └── home_page.dart           # 主页面布局
```

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

## 技术栈

| 项目 | 选择 |
|------|------|
| 框架 | Flutter 3.x |
| 状态管理 | provider |
| 文件存储 | path_provider |
| 文件对话框 | file_selector |
| UUID 生成 | uuid |
| 草稿持久化 | JSON 文件 |
