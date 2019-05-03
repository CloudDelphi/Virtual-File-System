unit VfsBaseTest;

(***)  interface  (***)

uses
  SysUtils, TestFramework,
  Utils, WinUtils,
  VfsUtils, VfsBase;

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
  RootDir:    string;
  FileInfo:   TFileInfo;
  i:          integer;

begin
  DirListing := TDirListing.Create;
  FileInfo   := nil;
  // * * * * * //
  RootDir := SysUtils.ExtractFileDir(WinUtils.GetExePath) + '\Tests\Fs';
  VfsBase.MapDir(RootDir, RootDir + '\Mods\B', DONT_OVERWRITE_EXISTING);
  VfsBase.MapDir(RootDir, RootDir + '\Mods\A', DONT_OVERWRITE_EXISTING);
  VfsBase.RunVfs(SORT_FIFO);

  VfsBase.PauseVfs;
  VfsBase.GetVfsDirInfo(RootDir, '*', DirInfo, DirListing);
  DirListing.Rewind;
  Check(DirListing.GetDebugDump() = '', 'Virtual directory listing must be empty when VFS is paused. Got: ' + DirListing.GetDebugDump());

  VfsBase.RunVfs(SORT_FIFO);
  VfsBase.GetVfsDirInfo(RootDir, '*', DirInfo, DirListing);
  DirListing.Rewind;
  Check(DirListing.GetDebugDump() = 'vcredist.bmp'#13#10'eula.1028.txt', 'Invalid virtual directoring listing. Got: ' + DirListing.GetDebugDump());

  DirListing.Rewind;
  
  for i := 0 to DirListing.Count - 1 do begin
    DirListing.GetNextItem(FileInfo);

    if FileInfo.Data.FileName = 'vcredist.bmp' then begin
      Check(FileInfo.Data.GetFileSize() = 5686, 'File from A mod must not override same file from B mod');
    end;
  end;
  // * * * * * //
  SysUtils.FreeAndNil(DirListing);
end;

begin
  RegisterTest(TestBase.Suite);
end.