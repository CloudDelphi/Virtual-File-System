unit VfsOpenFilesTest;

(***)  interface  (***)

uses
  Windows, SysUtils, TestFramework,
  Utils, WinUtils, DataLib,
  VfsBase, VfsUtils, VfsOpenFiles,
  VfsTestHelper;

type
  TestOpenFiles = class (TTestCase)
   protected
    procedure SetUp; override;
    procedure TearDown; override;

   published
    procedure GetCombinedDirListing;
  end;


(***)  implementation  (***)


procedure TestOpenFiles.SetUp;
begin
  VfsBase.ResetVfs();
end;

procedure TestOpenFiles.TearDown;
begin
  VfsBase.ResetVfs();
end;

procedure TestOpenFiles.GetCombinedDirListing;
const
  VALID_FULLY_VIRT_DIR_LISTING  = 'mms.cfg'#13#10'.'#13#10'..';
  VALID_COMBINED_LISTING        = 'Hobbots'#13#10'vcredist.bmp'#13#10'.'#13#10'..'#13#10'503.html'#13#10'default'#13#10'Mods';
  VALID_COMBINED_MASKED_LISTING = '503.html';

var
{O} OpenedFile: VfsOpenFiles.TOpenedFile;
    DirPath:    WideString;
    RootDir:    WideString;

begin
  OpenedFile := nil;
  // * * * * * //
  RootDir := VfsTestHelper.GetTestsRootDir;
  VfsBase.MapDir(RootDir, VfsUtils.MakePath([RootDir, '\Mods\FullyVirtual']), DONT_OVERWRITE_EXISTING);
  VfsBase.MapDir(RootDir, VfsUtils.MakePath([RootDir, '\Mods\B']), DONT_OVERWRITE_EXISTING);
  VfsBase.RunVfs(SORT_FIFO);

  DirPath    := VfsUtils.NormalizePath(VfsUtils.MakePath([RootDir, '\Hobbots']));
  OpenedFile := VfsOpenFiles.TOpenedFile.Create(777, DirPath);
  OpenedFile.FillDirListing('*');
  Check(OpenedFile.DirListing <> nil, 'Directory listing must be assigned');
  CheckEquals(VALID_FULLY_VIRT_DIR_LISTING, OpenedFile.DirListing.GetDebugDump(), 'Invalid listing for fully virtual directory "' + DirPath + '"');
  FreeAndNil(OpenedFile);

  OpenedFile := VfsOpenFiles.TOpenedFile.Create(888, RootDir);
  OpenedFile.FillDirListing('*');
  Check(OpenedFile.DirListing <> nil, 'Directory listing must be assigned');
  CheckEquals(VALID_COMBINED_LISTING, OpenedFile.DirListing.GetDebugDump(), 'Invalid combined listing for directory "' + VfsUtils.MakePath([RootDir, '"']));
  FreeAndNil(OpenedFile);

  OpenedFile := VfsOpenFiles.TOpenedFile.Create(999, RootDir);
  OpenedFile.FillDirListing('*.????');
  Check(OpenedFile.DirListing <> nil, 'Directory listing must be assigned');
  CheckEquals(VALID_COMBINED_MASKED_LISTING, OpenedFile.DirListing.GetDebugDump(), 'Invalid combined masked listing for directory "' + VfsUtils.MakePath([RootDir, '"']));
  FreeAndNil(OpenedFile);
  // * * * * * //
  SysUtils.FreeAndNil(OpenedFile);
end;

begin
  RegisterTest(TestOpenFiles.Suite);
end.