; Instalador de Claude Meter (Inno Setup 6).
; Compilar con installer\build.ps1, que primero genera los binarios.

#define AppName "Claude Meter"
#define AppVersion "1.1.0"
#define AppExe "claude_meter.exe"
#define Release "..\build\windows\x64\runner\Release"
#define Extra "..\build\installer"

[Setup]
AppId={{6F1B7E2A-3C4D-4E8F-9A21-C1A5D0E7B342}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Claude Meter
DefaultDirName={localappdata}\Programs\ClaudeMeter
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; Instalación por usuario: no pide permisos de administrador.
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\build\installer_output
OutputBaseFilename=ClaudeMeter-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
es.Startup=Abrir el medidor al iniciar Windows
en.Startup=Open the meter when Windows starts
es.Launch=Abrir Claude Meter ahora
en.Launch=Open Claude Meter now

[Tasks]
Name: "startup"; Description: "{cm:Startup}"
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked

[Files]
Source: "{#Release}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Runtime de Visual C++ junto al exe (por si el PC no lo tiene instalado).
Source: "{#Extra}\msvcp140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Extra}\vcruntime140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Extra}\vcruntime140_1.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon
Name: "{userstartup}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: startup

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:Launch}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/f /im {#AppExe}"; Flags: runhidden; RunOnceId: "KillApp"
