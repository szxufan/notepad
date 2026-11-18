; Notepad Windows 安装包脚本（Inno Setup 6）
; 用法：iscc notepad.iss /DAppVersion=1.0.0

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#define AppName "Notepad"
#define AppExeName "notepad.exe"

[Setup]
AppId={{6F0E60BA-5F2D-4844-BD6F-CF93287A6A41}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=szxufan
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\..\build\windows\installer
OutputBaseFilename={#AppName}-{#AppVersion}-setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#AppExeName}
ChangesAssociations=yes

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "fileassoc"; Description: "将 .txt 文件关联到 Notepad"; GroupDescription: "文件关联:"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; VC++ 2015-2022 运行库（构建时由 CI 下载），Flutter Windows 应用动态链接 MSVCP140.dll 等
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Registry]
; 「打开方式」菜单注册（始终执行，不改变现有默认关联）
Root: HKCR; Subkey: "Applications\{#AppExeName}"; ValueType: string; ValueName: ""; ValueData: "{#AppName}"; Flags: uninsdeletekey
Root: HKCR; Subkey: "Applications\{#AppExeName}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" ""%1"""
; .txt 默认关联（可选任务，卸载时清除默认值回退系统处理）
Root: HKCR; Subkey: ".txt"; ValueType: string; ValueName: ""; ValueData: "Notepad.txt"; Tasks: fileassoc; Flags: uninsclearvalue
Root: HKCR; Subkey: "Notepad.txt"; ValueType: string; ValueName: ""; ValueData: "文本文档"; Tasks: fileassoc; Flags: uninsdeletekey
Root: HKCR; Subkey: "Notepad.txt\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#AppExeName},0"; Tasks: fileassoc
Root: HKCR; Subkey: "Notepad.txt\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExeName}"" ""%1"""; Tasks: fileassoc

[Run]
; 目标机器缺少 VC++ 运行库时静默安装（已装则跳过）
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "正在安装 VC++ 运行库..."; Flags: waituntilterminated; Check: not VCRedistInstalled
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[Code]
function VCRedistInstalled: Boolean;
var
  installed: Cardinal;
begin
  Result :=
    RegQueryDWordValue(HKLM, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
      'Installed', installed) and (installed = 1);
end;
