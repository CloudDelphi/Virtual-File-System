unit VfsIntegratedTest;

(***)  interface  (***)

uses
  SysUtils, TestFramework, Windows,
  Utils, WinUtils, ConsoleApi, Files, FilesEx,
  DataLib,
  VfsUtils, VfsBase, VfsDebug,
  VfsOpenFiles, VfsControl, VfsTestHelper;

type
  TestIntegrated = class (TTestCase)
   protected
    procedure SetUp; override;
    procedure TearDown; override;

   published
    procedure TestGetFileAttributes;
    procedure TestGetFileAttributesEx;
    procedure TestFilesOpenClose;
    procedure TestDirectoryListing;
  end;


(***)  implementation  (***)


var
  LogFile: Windows.THandle;

procedure LogSomething (Operation, Message: pchar); stdcall;
var
  OutputHandle: integer;

begin
  WriteLn('>> ', string(Operation), ': ', string(Message), #13#10);
  
  OutputHandle := pinteger(@System.Output)^;
  pinteger(@System.Output)^ := integer(LogFile);
  WriteLn('>> ', string(Operation), ': ', string(Message), #13#10);
  pinteger(@System.Output)^ := OutputHandle;
end;

procedure TestIntegrated.SetUp;
var
  RootDir: WideString;

begin
  RootDir := VfsTestHelper.GetTestsRootDir;
  VfsBase.ResetVfs();
  VfsBase.MapDir(RootDir, VfsUtils.MakePath([RootDir, 'Mods\FullyVirtual_2']), DONT_OVERWRITE_EXISTING);
  VfsBase.MapDir(RootDir, VfsUtils.MakePath([RootDir, 'Mods\FullyVirtual']), DONT_OVERWRITE_EXISTING);
  VfsBase.MapDir(RootDir, VfsUtils.MakePath([RootDir, 'Mods\B']), DONT_OVERWRITE_EXISTING);
  VfsBase.MapDir(RootDir, VfsUtils.MakePath([RootDir, 'Mods\A']), DONT_OVERWRITE_EXISTING);
  VfsBase.MapDir(RootDir, VfsUtils.MakePath([RootDir, 'Mods\Apache']), DONT_OVERWRITE_EXISTING);
  VfsDebug.SetLoggingProc(LogSomething);
  VfsControl.RunVfs(VfsBase.SORT_FIFO);
  Windows.MessageBoxA(0, '', '', 0);
end;

procedure TestIntegrated.TearDown;
begin
  VfsBase.ResetVfs();
  VfsDebug.SetLoggingProc(nil);
end;

procedure TestIntegrated.TestGetFileAttributes;
var
  RootDir: WideString;

  function HasValidAttrs (const Path: string; const RequiredAttrs: integer = 0; const ForbiddenAttrs: integer = 0): boolean;
  var
    Attrs: integer;

  begin
    Attrs  := Int(Windows.GetFileAttributes(pchar(Path)));
    result := Attrs <> -1;

    if result then begin
      if RequiredAttrs <> 0 then begin
        result := (Attrs and RequiredAttrs) = RequiredAttrs;
      end;

      if result and (ForbiddenAttrs <> 0) then begin
        result := (Attrs and ForbiddenAttrs) = 0;
      end;
    end;
  end; // .function HasValidAttrs

begin
  VfsDebug.WriteLog('TestGetFileAttributes', 'Started');
  RootDir := VfsTestHelper.GetTestsRootDir;
  Check(not HasValidAttrs(VfsUtils.MakePath([RootDir, 'non-existing.non'])), '{1}');
  Check(HasValidAttrs(VfsUtils.MakePath([RootDir, 'Hobbots\mms.cfg']), 0, Windows.FILE_ATTRIBUTE_DIRECTORY), '{2}');
  Check(HasValidAttrs(VfsUtils.MakePath([RootDir, '503.html']), 0, Windows.FILE_ATTRIBUTE_DIRECTORY), '{3}');
  Check(HasValidAttrs(VfsUtils.MakePath([RootDir, 'Hobbots\']), Windows.FILE_ATTRIBUTE_DIRECTORY), '{4}');
  Check(HasValidAttrs(VfsUtils.MakePath([RootDir, 'Mods']), Windows.FILE_ATTRIBUTE_DIRECTORY), '{5}');
  VfsDebug.WriteLog('TestGetFileAttributes', 'Ended');
end; // .procedure TestIntegrated.TestGetFileAttributes;

procedure TestIntegrated.TestGetFileAttributesEx;
var
  RootDir: WideString;

  function GetFileSize (const Path: string): integer;
  var
    FileData: Windows.TWin32FileAttributeData;

  begin
    result := -1;

    if Windows.GetFileAttributesExA(pchar(Path), Windows.GetFileExInfoStandard, @FileData) then begin
      result := Int(FileData.nFileSizeLow);
    end;
  end;

begin
  VfsDebug.WriteLog('TestGetFileAttributesEx', 'Started');
  RootDir := VfsTestHelper.GetTestsRootDir;
  CheckEquals(-1, GetFileSize(VfsUtils.MakePath([RootDir, 'non-existing.non'])), '{1}');
  CheckEquals(42, GetFileSize(VfsUtils.MakePath([RootDir, 'Hobbots\mms.cfg'])), '{2}');
  CheckEquals(22, GetFileSize(VfsUtils.MakePath([RootDir, '503.html'])), '{3}');
  CheckEquals(318, GetFileSize(VfsUtils.MakePath([RootDir, 'default'])), '{4}');
  VfsDebug.WriteLog('TestGetFileAttributesEx', 'Ended');
end; // .procedure TestIntegrated.TestGetFileAttributesEx;

procedure TestIntegrated.TestFilesOpenClose;
var
  CurrDir:  WideString;
  RootDir:  WideString;
  FileData: string;
  hFile:    integer;

  function OpenFile (const Path: string): integer;
  begin
    result := SysUtils.FileOpen(Path, fmOpenRead or fmShareDenyNone);
  end;

begin
  CurrDir := WinUtils.GetCurrentDirW;
  RootDir := VfsTestHelper.GetTestsRootDir;

  try
    VfsDebug.WriteLog('TestFilesOpenClose', 'Started');
    Check(WinUtils.SetCurrentDirW(RootDir), 'Setting current directory to real path must succeed. Path: ' + RootDir);
    CheckEquals(RootDir, WinUtils.GetCurrentDirW(), 'GetCurrentDirW must return virtual path, not redirected one');
    
    Check(OpenFile(VfsUtils.MakePath([RootDir, 'non-existing.non'])) <= 0, 'Opening non-existing file must fail');

    hFile := OpenFile(VfsUtils.MakePath([RootDir, 'Hobbots\mms.cfg']));
    Check(hFile > 0, 'Opening fully virtual file must succeed');
    CheckEquals(VfsUtils.MakePath([RootDir, 'Hobbots\mms.cfg']), VfsOpenFiles.GetOpenedFilePath(hFile), 'There must be created a corresponding TOpenedFile record for opened file handle with valid virtual path');
    SysUtils.FileClose(hFile);
    CheckEquals('', VfsOpenFiles.GetOpenedFilePath(hFile), 'TOpenedFile record must be destroyed on file handle closing {1}');

    hFile := OpenFile('Hobbots\mms.cfg');
    Check(hFile > 0, 'Opening fully virtual file using relative path must succeed');
    CheckEquals(VfsUtils.MakePath([RootDir, 'Hobbots\mms.cfg']), VfsOpenFiles.GetOpenedFilePath(hFile), 'There must be created a corresponding TOpenedFile record for opened file handle with valid virtual path when relative path was used');
    SysUtils.FileClose(hFile);
    CheckEquals('', VfsOpenFiles.GetOpenedFilePath(hFile), 'TOpenedFile record must be destroyed on file handle closing {2}');

    Check(WinUtils.SetCurrentDirW(VfsUtils.MakePath([RootDir, 'Hobbots'])), 'Setting current durectory to fully virtual must succeed');
    hFile := OpenFile('mms.cfg');
    Check(hFile > 0, 'Opening fully virtual file in fully virtual directory using relative path must succeed');
    CheckEquals(VfsUtils.MakePath([RootDir, 'Hobbots\mms.cfg']), VfsOpenFiles.GetOpenedFilePath(hFile), 'There must be created a corresponding TOpenedFile record for opened file handle with valid virtual path when relative path was used for fully virtual directory');
    SysUtils.FileClose(hFile);
    CheckEquals('', VfsOpenFiles.GetOpenedFilePath(hFile), 'TOpenedFile record must be destroyed on file handle closing {3}');

    Check(Files.ReadFileContents('mms.cfg', FileData), 'File mms.cfg must be readable');
    CheckEquals('It was a pleasure to override you, friend!', FileData);
  finally
    WinUtils.SetCurrentDirW(CurrDir);
  end; // .try

  VfsDebug.WriteLog('TestFilesOpenClose', 'Ended');
end; // .procedure TestIntegrated.TestFilesOpenClose;

procedure TestIntegrated.TestDirectoryListing;
const
  VALID_ROOT_DIR_LISTING          = 'Hobbots'#13#10'vcredist.bmp'#13#10'eula.1028.txt'#13#10'503.html'#13#10'.'#13#10'..'#13#10'default'#13#10'Mods';
  VALID_ROOT_DIR_MASKED_LISTING_1 = 'vcredist.bmp'#13#10'eula.1028.txt'#13#10'503.html';
  VALID_ROOT_DIR_MASKED_LISTING_2 = 'eula.1028.txt';

var
{O} FileList:    {U} DataLib.TStrList;
{O} DirListing:  VfsUtils.TDirListing;
    CurrDir:     WideString;
    RootDir:     WideString;
    DirContents: string;

  function GetDirListing (const Path: string): {O} DataLib.TStrList;
  var
    FoundData:    TWin32FindDataA;
    SearchHandle: Windows.THandle;

  begin
    result := DataLib.NewStrList(not Utils.OWNS_ITEMS, DataLib.CASE_SENSITIVE);
    // * * * * * //
    SearchHandle := Windows.FindFirstFileA(pchar(Path), FoundData);
    
    if SearchHandle <> Windows.INVALID_HANDLE_VALUE then begin
      result.Add(pchar(@FoundData.cFileName));

      while Windows.FindNextFileA(SearchHandle, FoundData) do begin
        result.Add(pchar(@FoundData.cFileName));
      end;

      Windows.FindClose(SearchHandle);
    end;
  end; // .function GetDirListing

  function GetDirListingLow (const Path, Mask: WideString): {O} DataLib.TStrList;
  var
    FileName: WideString;

  begin
    result := DataLib.NewStrList(not Utils.OWNS_ITEMS, DataLib.CASE_SENSITIVE);
    // * * * * * //
    with VfsUtils.SysScanDir(Path, Mask) do begin
      while IterNext(FileName) do begin
        result.Add(FileName);
      end;
    end;
  end; // .function GetDirListingLow

begin
  FileList   := nil;
  DirListing := VfsUtils.TDirListing.Create;
  // * * * * * //
  CurrDir := WinUtils.GetCurrentDirW;
  RootDir := VfsTestHelper.GetTestsRootDir;

  try
    VfsDebug.WriteLog('TestDirectoryListing', 'Started');
    FileList    := GetDirListing(VfsUtils.MakePath([RootDir, '*']));
    DirContents := FileList.ToText(#13#10);
    CheckEquals(VALID_ROOT_DIR_LISTING, DirContents);
    SysUtils.FreeAndNil(FileList);

    FileList    := GetDirListingLow(RootDir, '*.??*');
    DirContents := FileList.ToText(#13#10);
    CheckEquals(VALID_ROOT_DIR_MASKED_LISTING_1, DirContents);
    SysUtils.FreeAndNil(FileList);
    
    FileList    := GetDirListing(VfsUtils.MakePath([RootDir, '*.txt']));
    DirContents := FileList.ToText(#13#10);
    CheckEquals(VALID_ROOT_DIR_MASKED_LISTING_2, DirContents);
    SysUtils.FreeAndNil(FileList);
  finally
    WinUtils.SetCurrentDirW(CurrDir);
    SysUtils.FreeAndNil(FileList);
    SysUtils.FreeAndNil(DirListing);
  end; // .try

  VfsDebug.WriteLog('TestDirectoryListing', 'Ended');
end; // .procedure TestIntegrated.TestDirectoryListing;

begin
  RegisterTest(TestIntegrated.Suite);
  LogFile := SysUtils.FileCreate(SysUtils.ExtractFileDir(WinUtils.GetExePath()) + '\_LOG_.txt');
end.