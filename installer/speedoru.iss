; Instalador do Speedoru para Windows (Inno Setup 6).
;
; Instala só para o usuário atual, sem pedir administrador, em %LOCALAPPDATA%\Programs\Speedoru,
; com atalho no menu Iniciar (e na área de trabalho, se marcado). Instalar uma versão nova por cima
; atualiza no lugar; desinstalar remove o jogo, mas não o perfil, as configurações e a conta
; (%APPDATA%\Godot\app_userdata\F1 Gatcha), que continuam valendo se o jogo for reinstalado.
;
; Compilado pela action de release (.github/workflows/release.yml), a partir do que o Godot
; exportou em build\windows. Na mão:
;   godot --headless --path . --export-release "Windows Desktop" build/windows/Speedoru.exe
;   iscc /DAppVersion=0.1.0 installer\speedoru.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
; Identidade fixa: nunca mude (é o que faz uma versão nova atualizar a instalada)
AppId={{7C1E5A3B-2F4D-4B8E-9A61-5D0C3E7F9B24}
AppName=Speedoru
AppVersion={#AppVersion}
AppVerName=Speedoru {#AppVersion}
AppPublisher=Gabriel Campos
AppPublisherURL=https://github.com/gabrielcamposmartins/speedoru
AppSupportURL=https://github.com/gabrielcamposmartins/speedoru/issues
AppUpdatesURL=https://github.com/gabrielcamposmartins/speedoru/releases
DefaultDirName={localappdata}\Programs\Speedoru
DefaultGroupName=Speedoru
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\build\installer
OutputBaseFilename=Speedoru-{#AppVersion}-setup
UninstallDisplayName=Speedoru
UninstallDisplayIcon={app}\Speedoru.exe
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "ptbr"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\Speedoru.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\Speedoru.console.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\server.cfg.example"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Speedoru"; Filename: "{app}\Speedoru.exe"
Name: "{group}\{cm:UninstallProgram,Speedoru}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Speedoru"; Filename: "{app}\Speedoru.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Speedoru.exe"; Description: "{cm:LaunchProgram,Speedoru}"; Flags: nowait postinstall skipifsilent
