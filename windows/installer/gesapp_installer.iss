; Script Inno Setup pour générer l'installeur Windows (.exe) de GesApp.
; Utilisé par le workflow GitHub Actions .github/workflows/build_windows.yml
;
; Pour compiler localement :
;   1. flutter build windows --release
;   2. Installer Inno Setup (https://jrsoftware.org/isinfo.php)
;   3. Ouvrir ce fichier avec ISCC.exe ou l'IDE Inno Setup, en définissant
;      GesAppReleaseDir vers le dossier build\windows\x64\runner\Release
;      (ex: ISCC.exe /DGesAppReleaseDir="C:\chemin\vers\build\windows\x64\runner\Release" gesapp_installer.iss)

#define MyAppName "GesApp"
#define MyAppVersion "1.4.1"
#define MyAppPublisher "GesApp"
#define MyAppExeName "gesapp.exe"

#ifndef GesAppReleaseDir
  #define GesAppReleaseDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{9E4B9E3E-6C0A-4C1E-8B0A-6B7B6D8E2F41}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppSupportURL=
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename=GesApp_Setup_{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer un raccourci sur le Bureau"; GroupDescription: "Raccourcis :"; Flags: unchecked

[Files]
Source: "{#GesAppReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Désinstaller {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Lancer {#MyAppName}"; Flags: nowait postinstall skipifsilent
