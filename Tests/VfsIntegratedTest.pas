unit VfsIntegratedTest;

(***)  interface  (***)

uses
  SysUtils, TestFramework, Windows,
  Utils, WinUtils, ConsoleApi,
  VfsUtils, VfsBase, VfsDebug,
  VfsControl;

type
  TestIntegrated = class (TTestCase)
   private
    Inited: boolean;

    function GetRootDir: string;

   protected
    procedure SetUp; override;
    procedure TearDown; override;

   published
    procedure TestGetFileAttributes;
    procedure TestGetFileAttributesEx;
  end;

(***)  implementation  (***)


procedure LogSomething (Operation, Message: pchar); stdcall;
begin
  WriteLn('>> ', string(Operation), ': ', string(Message), #13#10);
end;

function TestIntegrated.GetRootDir: string;
begin
  result := SysUtils.ExtractFileDir(WinUtils.GetExePath) + '\Tests\Fs';
end;

procedure TestIntegrated.SetUp;
var
  RootDir: string;

begin
  if not Inited then begin
    Inited  := true;
    RootDir := Self.GetRootDir;
    VfsBase.ResetVfs();
    VfsBase.MapDir(RootDir, RootDir + '\Mods\FullyVirtual', DONT_OVERWRITE_EXISTING);
    VfsBase.MapDir(RootDir, RootDir + '\Mods\B', DONT_OVERWRITE_EXISTING);
    VfsBase.MapDir(RootDir, RootDir + '\Mods\A', DONT_OVERWRITE_EXISTING);
    VfsBase.MapDir(RootDir, RootDir + '\Mods\Apache', DONT_OVERWRITE_EXISTING);
    VfsDebug.SetLoggingProc(LogSomething);
    VfsControl.RunVfs(VfsBase.SORT_FIFO);
  end;
end;

procedure TestIntegrated.TearDown;
begin
  VfsBase.PauseVfs();
  VfsDebug.SetLoggingProc(nil);
end;

procedure TestIntegrated.TestGetFileAttributes;
var
  RootDir: string;

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
  RootDir := Self.GetRootDir;
  Check(not HasValidAttrs(RootDir + '\non-existing.non'), '{1}');
  Check(HasValidAttrs(RootDir + '\Hobbots\mms.cfg', 0, Windows.FILE_ATTRIBUTE_DIRECTORY), '{2}');
  Check(HasValidAttrs(RootDir + '\503.html', 0, Windows.FILE_ATTRIBUTE_DIRECTORY), '{3}');
  Check(HasValidAttrs(RootDir + '\Hobbots\', Windows.FILE_ATTRIBUTE_DIRECTORY), '{4}');
  Check(HasValidAttrs(RootDir + '\Mods', Windows.FILE_ATTRIBUTE_DIRECTORY), '{5}');
end; // .procedure TestIntegrated.TestGetFileAttributes;

procedure TestIntegrated.TestGetFileAttributesEx;
var
  RootDir: string;

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
  RootDir := Self.GetRootDir;
  CheckEquals(-1, GetFileSize(RootDir + '\non-existing.non'), '{1}');
  CheckEquals(47, GetFileSize(RootDir + '\Hobbots\mms.cfg'), '{2}');
  CheckEquals(22, GetFileSize(RootDir + '\503.html'), '{3}');
  CheckEquals(318, GetFileSize(RootDir + '\default'), '{4}');
end; // .procedure TestIntegrated.TestGetFileAttributesEx;

begin
  RegisterTest(TestIntegrated.Suite);
end.