[Setup]
AppName=SEVEN Language
AppVersion=1.0.0
AppPublisher=Tejas Chandivakar
AppPublisherURL=https://seven-language.github.io
AppSupportURL=https://github.com/tejas-chandivakar/seven-lang/issues
DefaultDirName={autopf}\SEVEN
DefaultGroupName=SEVEN Language
OutputDir=..\build
OutputBaseFilename=seven-setup-1.0.0-win64
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
ChangesEnvironment=yes
PrivilegesRequired=admin
WizardStyle=classic
LicenseFile=
MinVersion=10.0

[Files]
Source: "..\build\seven.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "C:\Program Files\LLVM\bin\LLVM-C.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\SEVEN Command Prompt"; Filename: "{cmd}"; Parameters: "/K set PATH={app};%PATH%"; WorkingDir: "{userdocs}"
Name: "{group}\Uninstall SEVEN"; Filename: "{uninstallexe}"

[Code]
function GetLLVMBinPath(): string;
begin
  if DirExists(ExpandConstant('{autopf}\LLVM\bin')) then
    Result := ExpandConstant('{autopf}\LLVM\bin')
  else if DirExists(ExpandConstant('{autopf32}\LLVM\bin')) then
    Result := ExpandConstant('{autopf32}\LLVM\bin')
  else
    Result := '';
end;

function PathContains(const Path, Dir: string): Boolean;
begin
  Result := Pos(';' + UpperCase(Dir) + ';', ';' + UpperCase(Path) + ';') > 0;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  OrigPath, AppDir, LLVMDir, NewPath: string;
begin
  if CurStep = ssPostInstall then
  begin
    if not RegQueryStringValue(HKEY_LOCAL_MACHINE,
      'SYSTEM\CurrentControlSet\Control\Session Manager\Environment',
      'Path', OrigPath) then
      OrigPath := '';

    AppDir := ExpandConstant('{app}');
    LLVMDir := GetLLVMBinPath();
    NewPath := OrigPath;

    if not PathContains(NewPath, AppDir) then
      NewPath := NewPath + ';' + AppDir;

    if (LLVMDir <> '') and not PathContains(NewPath, LLVMDir) then
      NewPath := NewPath + ';' + LLVMDir;

    if NewPath <> OrigPath then
      RegWriteStringValue(HKEY_LOCAL_MACHINE,
        'SYSTEM\CurrentControlSet\Control\Session Manager\Environment',
        'Path', NewPath);
  end;
end;

function InitializeSetup(): Boolean;
begin
  if not DirExists(ExpandConstant('{autopf}\LLVM\bin')) and not DirExists(ExpandConstant('{autopf32}\LLVM\bin')) then
  begin
    MsgBox('LLVM/Clang is required but was not found.' #13#10#13#10 'Please install LLVM first:' #13#10 '  winget install LLVM.LLVM' #13#10#13#10 'Then run this installer again.', mbError, MB_OK);
    Result := False;
  end else
    Result := True;
end;

[Run]
Filename: "{cmd}"; Parameters: "/C echo SEVEN Language installed! Open a new terminal and type: seven --help"; Flags: postinstall nowait skipifsilent runhidden

[UninstallDelete]
Type: filesandordirs; Name: "{app}"
