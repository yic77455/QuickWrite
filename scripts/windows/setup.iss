; 基于用户原有的 quickwrite.iss 对齐，仅做 CI 适配：
; 1) 版本号由 workflow 通过 /dMyAppVersion= 传入，脚本里保留默认值兜底
; 2) 本机绝对路径改为相对脚本目录的路径，OutputDir 由 ISCC 的 /O 参数指定
; 其余 AppId、安装模式、语言等保持与原脚本一致，避免覆盖安装行为变化；
; 原脚本里向导误加的 .exe 文件关联已去掉。

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#define MyAppName "快码字"
#define MyAppPublisher "yic77455"
#define MyAppURL "https://github.com/yic77455/QuickWrite"
#define MyAppExeName "QuickWrite.exe"

[Setup]
AppId={{C249FB4B-F543-4351-AF29-D2D23F21C307}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
VersionInfoVersion={#MyAppVersion}.0
AppVerName={#MyAppName} v{#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\QuickWrite
UninstallDisplayIcon={app}\{#MyAppExeName}
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
LicenseFile=..\..\LICENSE
PrivilegesRequiredOverridesAllowed=commandline
OutputBaseFilename=quick-write-{#MyAppVersion}-windows-x64
SetupIconFile=..\..\assets\icon\icon_rounded.ico
SolidCompression=yes
WizardStyle=modern
DisableWelcomePage=no
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} Setup
VersionInfoCopyright=Copyright (C) 2026 {#MyAppPublisher}

[Languages]
; 中文语言文件随仓库提供（MessagesFile 相对脚本目录解析），
; 不依赖 runner 上的 Inno Setup 是否附带 Languages\ChineseSimplified.isl
Name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
