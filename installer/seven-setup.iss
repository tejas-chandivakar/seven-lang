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

[Registry]
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}"; Check: NeedsAddPath('{app}')
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{code:GetLLVMBinPath}"; Check: NeedsAddPath('{code:GetLLVMBinPath}')

[Code]
function GetLLVMBinPath(Param: string): string;
begin
  if DirExists(ExpandConstant('{autopf}\LLVM\bin')) then
    Result := ExpandConstant('{autopf}\LLVM\bin')
  else if DirExists(ExpandConstant('{autopf32}\LLVM\bin')) then
    Result := ExpandConstant('{autopf32}\LLVM\bin')
  else
    Result := '';
end;

function NeedsAddPath(Param: string): Boolean;
var
  OrigPath: string;
begin
  if Param = '' then begin
    Result := False;
    exit;
  end;
  if not RegQueryStringValue(HKEY_LOCAL_MACHINE,
    'SYSTEM\CurrentControlSet\Control\Session Manager\Environment',
    'Path', OrigPath)
  then begin
    Result := True;
    exit;
  end;
  Result := Pos(';' + UpperCase(Param) + ';', ';' + UpperCase(OrigPath) + ';') = 0;
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
