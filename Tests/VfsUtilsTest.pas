unit VfsUtilsTest;

(***)  interface  (***)

uses
  SysUtils, TestFramework,
  Utils, WinUtils, DataLib,
  VfsUtils;

type
  TestUtils = class (TTestCase)
   published
    procedure TestNativeDirScanning;
    procedure TestGetDirectoryListing;
  end;


(***)  implementation  (***)


procedure TestUtils.TestNativeDirScanning;
var
  RootDir:     string;
  FileInfo:    VfsUtils.TNativeFileInfo;
  DirItems:    DataLib.TStrList;
  DirContents: string;

begin
  DirItems := DataLib.NewStrList(not Utils.OWNS_ITEMS, DataLib.CASE_SENSITIVE);
  // * * * * * //
  RootDir := SysUtils.ExtractFileDir(WinUtils.GetExePath) + '\Tests\Fs';

  with SysScanDir(RootDir, '*') do begin
    while IterNext(FileInfo.FileName, @FileInfo.Base) do begin
      DirItems.Add(FileInfo.FileName);
    end;
  end;

  DirItems.Sort;
  DirContents := DirItems.ToText(#13#10);
  Check(DirContents = '.'#13#10'..'#13#10'503.html'#13#10'default'#13#10'Mods', 'Invalid directory listing. Got:'#13#10 + DirContents);
  // * * * * * //
  SysUtils.FreeAndNil(DirItems);
end; // .procedure TestNativeDirScanning

procedure TestUtils.TestGetDirectoryListing;
var
  DirListing: VfsUtils.TDirListing;
  Exclude:    DataLib.TDict {of not nil};
  RootDir:    string;
 
begin
  DirListing := VfsUtils.TDirListing.Create;
  Exclude    := DataLib.NewDict(not Utils.OWNS_ITEMS, DataLib.CASE_SENSITIVE);
  // * * * * * //
  RootDir := SysUtils.ExtractFileDir(WinUtils.GetExePath) + '\Tests\Fs';
  Exclude[VfsUtils.WideStrToCaselessKey('..')] := Ptr(1);

  VfsUtils.GetDirectoryListing(RootDir, '*', Exclude, DirListing);
  Check(DirListing.GetDebugDump() = '.'#13#10'503.html'#13#10'default'#13#10'Mods', 'Invalid directory listing. Got:'#13#10 + DirListing.GetDebugDump());
  // * * * * * //
  SysUtils.FreeAndNil(DirListing);
  SysUtils.FreeAndNil(Exclude);
end; // .procedure TestUtils.TestGetDirectoryListing

begin
  RegisterTest(TestUtils.Suite);
end.