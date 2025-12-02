; RetailPOS Print Helper - Inno Setup Script
; This creates a complete Windows installer

#define MyAppName "RetailPOS Print Helper"
#define MyAppVersion "1.0.2"
#define MyAppPublisher "RetailPOS"
#define MyAppURL "https://retailpos.com"

[Setup]
AppId={{E8A7F9B2-3C4D-5E6F-7A8B-9C0D1E2F3A4B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\RetailPOS Print Helper
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=installer_output
OutputBaseFilename=RetailPOS-PrintHelper-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "autostart"; Description: "Start automatically with Windows"; GroupDescription: "Startup Options:"; Flags: checkedonce

[Files]
; Node.js portable
Source: "node\*"; DestDir: "{app}\node"; Flags: ignoreversion recursesubdirs createallsubdirs
; Server files
Source: "server.js"; DestDir: "{app}"; Flags: ignoreversion
Source: "package.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "package-lock.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "node_modules\*"; DestDir: "{app}\node_modules"; Flags: ignoreversion recursesubdirs createallsubdirs
; VBS Launcher (runs hidden)
Source: "PrintHelper.vbs"; DestDir: "{app}"; Flags: ignoreversion
; Config template
Source: "config.json"; DestDir: "{app}"; Flags: ignoreversion onlyifdoesntexist

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "wscript.exe"; Parameters: """{app}\PrintHelper.vbs"""; WorkingDir: "{app}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 13
Name: "{group}\Stop Print Helper"; Filename: "{cmd}"; Parameters: "/c taskkill /f /im node.exe 2>nul"; IconFilename: "{sys}\shell32.dll"; IconIndex: 131
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "wscript.exe"; Parameters: """{app}\PrintHelper.vbs"""; WorkingDir: "{app}"; Tasks: desktopicon; IconFilename: "{sys}\shell32.dll"; IconIndex: 13
Name: "{userstartup}\{#MyAppName}"; Filename: "wscript.exe"; Parameters: """{app}\PrintHelper.vbs"""; WorkingDir: "{app}"; Tasks: autostart

[Run]
Filename: "wscript.exe"; Parameters: """{app}\PrintHelper.vbs"""; WorkingDir: "{app}"; Description: "Start Print Helper now"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{cmd}"; Parameters: "/c taskkill /f /im node.exe 2>nul"; Flags: runhidden

[Code]
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    ForceDirectories(ExpandConstant('{userappdata}\RetailPOS-PrintHelper'));
  end;
end;

function InitializeUninstall(): Boolean;
var
  ResultCode: Integer;
begin
  Exec('cmd.exe', '/c taskkill /f /im node.exe 2>nul', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := True;
end;
