unit VfsBaseTest;

(***)  interface  (***)

uses
  SysUtils, TestFramework,
  Utils, WinUtils,
  VfsUtils, VfsBase, VfsTestHelper;

type
  TestBase = class (TTestCase)
   protected
    procedure SetUp; override;
    procedure TearDown; override;

   published
    procedure TestVirtualDirMapping;
  end;

(***)  implementation  (***)


procedure TestBase.SetUp;
begin
  VfsBase.ResetVfs();
end;

procedure TestBase.TearDown;
begin
  VfsBase.ResetVfs();
end;

procedure TestBase.TestVirtualDirMapping;
var
  DirListing: TDirListing;
  DirInfo:    TNativeFileInfo;
  RootDir:    WideString;
  FileInfo:   TFileInfo;
  i:          integer;

begin
  DirListing := TDirListing.Create;
  FileInfo   := nil;
  // * * * * * //
  RootDir := VfsTestHelper.GetTestsRootDir;
  VfsBase.MapDir(RootDir, VfsUtils.MakePath([RootDir, 'Mods\B']), DONT_OVERWRITE_EXISTING);
  VfsBase.MapDir(RootDir, VfsUtils.MakePath([RootDir, 'Mods\A']), DONT_OVERWRITE_EXISTING);
  VfsBase.RunVfs(SORT_FIFO);

  VfsBase.PauseVfs;
  VfsBase.GetVfsDirInfo(RootDir, '*', DirInfo, DirListing);
  DirListing.Rewind;
  CheckEquals('', DirListing.GetDebugDump(), 'Virtual directory listing must be empty when VFS is paused');

  VfsBase.RunVfs(SORT_FIFO);
  VfsBase.GetVfsDirInfo(RootDir, '*', DirInfo, DirListing);
  DirListing.Rewind;
  CheckEquals('vcredist.bmp'#13#10'eula.1028.txt', DirListing.GetDebugDump(), 'Invalid virtual directoring listing');

  DirListing.Rewind;
  
  for i := 0 to DirListing.Count - 1 do begin
    DirListing.GetNextItem(FileInfo);

    if FileInfo.Data.FileName = 'vcredist.bmp' then begin
      CheckEquals(5686, FileInfo.Data.GetFileSize(), 'File from A mod must not override same file from B mod');
    end;
  end;
  // * * * * * //
  SysUtils.FreeAndNil(DirListing);
end;

begin
  RegisterTest(TestBase.Suite);
end.