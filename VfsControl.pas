unit VfsControl;
(*
  Facade unit for high-level VFS API.
*)


(***)  interface  (***)

uses
  Windows, SysUtils,
  Utils, WinUtils, TypeWrappers, DataLib, Files, StrLib,
  VfsBase, VfsUtils, VfsHooks, VfsWatching, DlgMes, FilesEx {FIXME DELETEME};

type
  (* Import *)
  TWideString = TypeWrappers.TWideString;


(* Runs all VFS subsystems, unless VFS is already running *)
function RunVfs (DirListingOrder: VfsBase.TDirListingSortType): LONGBOOL; stdcall;

(* Loads mod list from file and maps each mod directory to specified root directory.
   File with mod list is treated as (BOM or BOM-less) UTF-8 plain text file, where each mod name is separated
   from another one via Line Feed (#10) character. Each mod named is trimmed, converted to UCS16 and validated before
   adding to list. Invalid or empty mods will be skipped. Mods are mapped in reverse order, as compared to their order in file.
   Returns true if root and mods directory existed and file with mod list was loaded successfully *)
function MapModsFromList (const RootDir, ModsDir, ModListFile: WideString; Flags: integer = 0): boolean;


(***)  implementation  (***)


type
  TModList = DataLib.TList {of (O) TWideString};


function RunVfs (DirListingOrder: VfsBase.TDirListingSortType): LONGBOOL; stdcall;
var
  CurrDir: WideString;

begin
  with VfsBase.VfsCritSection do begin
    Enter;

    result := VfsBase.RunVfs(DirListingOrder);
    
    if result then begin
      VfsHooks.InstallHooks;

      // Try to ensure, that current directory handle is tracked by VfsOpenFiles
      CurrDir := WinUtils.GetCurrentDirW;

      if CurrDir <> '' then begin
        WinUtils.SetCurrentDirW(CurrDir);
      end;
    end;

    Leave;
  end; // .with
end; // function RunVfs

function ValidateModName (const ModName: WideString): boolean;
const
  DISALLOWED_CHARS = ['<', '>', '"', '?', '*', '\', '/', '|', ':', #0];

var
  StrLen: integer;
  i:      integer;

begin
  StrLen := Length(ModName);
  i      := 1;

  while (i <= StrLen) and ((ord(ModName[i]) > 255) or not (AnsiChar(ModName[i]) in DISALLOWED_CHARS)) do begin
    Inc(i);
  end;

  result := (i > StrLen) and (ModName <> '') and (ModName <> '.') and (ModName <> '..');
end;

function LoadModList (const ModListFilePath: WideString; {O} var {out} ModList: TModList): boolean;
const
  UTF8_BOM = #$EF#$BB#$BF;

var
  AbsFilePath:  WideString;
  FileHandle:   integer;
  FileContents: string;
  Lines:        Utils.TArrayOfStr;
  ModNameUtf8:  string;
  ModName:      WideString;
  i:            integer;

begin
  AbsFilePath := VfsUtils.NormalizePath(ModListFilePath);
  FileHandle  := integer(Windows.INVALID_HANDLE_VALUE);
  result      := AbsFilePath <> '';

  if result then begin
    FileHandle := Windows.CreateFileW(PWideChar(AbsFilePath), Windows.GENERIC_READ, Windows.FILE_SHARE_READ, nil, Windows.OPEN_EXISTING, 0, 0);
    result     := FileHandle <> integer(Windows.INVALID_HANDLE_VALUE);
  end;

  if result then begin
    result := Files.ReadFileContents(FileHandle, FileContents);

    if result then begin
      SysUtils.FreeAndNil(ModList);
      ModList := DataLib.NewList(Utils.OWNS_ITEMS);

      if (Length(FileContents) >= 3) and (FileContents[1] = UTF8_BOM[1]) and (FileContents[2] = UTF8_BOM[2]) and (FileContents[3] = UTF8_BOM[3]) then begin
        FileContents := Copy(FileContents, Length(UTF8_BOM) + 1);
      end;

      Lines := StrLib.Explode(FileContents, #10);

      for i := 0 to High(Lines) do begin
        ModNameUtf8 := Lines[i];
        ModName     := StrLib.TrimW(StrLib.Utf8ToWide(ModNameUtf8, StrLib.FAIL_ON_ERROR));

        if ValidateModName(ModName) then begin
          ModList.Add(TWideString.Create(ModName));
        end;
      end;
    end;

    Windows.CloseHandle(FileHandle);
  end; // .if
end; // .function LoadModList

function MapModsFromList_ (const RootDir, ModsDir: WideString; ModList: TModList; Flags: integer = 0): boolean;
var
  AbsRootDir:    WideString;
  AbsModsDir:    WideString;
  FileInfo:      VfsUtils.TNativeFileInfo;
  ModName:       WideString;
  ModPathPrefix: WideString;
  i:             integer;

begin
  {!} Assert(ModList <> nil);
  // * * * * * //
  AbsRootDir := VfsUtils.NormalizePath(RootDir);
  AbsModsDir := VfsUtils.NormalizePath(ModsDir);
  result     := (AbsRootDir <> '') and (AbsModsDir <> '')  and
                VfsUtils.GetFileInfo(AbsRootDir, FileInfo) and Utils.HasFlag(Windows.FILE_ATTRIBUTE_DIRECTORY, FileInfo.Base.FileAttributes) and
                VfsUtils.GetFileInfo(AbsModsDir, FileInfo) and Utils.HasFlag(Windows.FILE_ATTRIBUTE_DIRECTORY, FileInfo.Base.FileAttributes);
  
  if result then begin
    ModPathPrefix := VfsUtils.AddBackslash(AbsModsDir);

    for i := ModList.Count - 1 downto 0 do begin
      ModName := TWideString(ModList[i]).Value;
      VfsBase.MapDir(AbsRootDir, ModPathPrefix + ModName, not VfsBase.OVERWRITE_EXISTING, Flags);
    end;
  end; // .if
end; // .function MapModsFromList

function MapModsFromList (const RootDir, ModsDir, ModListFile: WideString; Flags: integer = 0): boolean;
var
{O} ModList: TModList;

begin
  ModList := nil;
  // * * * * * //
  result := VfsBase.EnterVfsConfig;

  if result then begin
    try
      result := LoadModList(ModListFile, ModList) and MapModsFromList_(RootDir, ModsDir, ModList, Flags);
    finally
      VfsBase.LeaveVfsConfig;
    end;
  end;
  // * * * * * //
  SysUtils.FreeAndNil(ModList);
end; // .function MapModsFromList

var s: string;
begin
  // MapModsFromList('D:\Heroes 3', 'D:\heroes 3\Mods', 'd:\heroes 3\mods\list.txt');
  // RunVfs(SORT_FIFO);
  // ReadFileContents('D:\heroes 3\data\s\__T.erm', s);
  // s := copy(s, 1, 100);
  // VarDump([s]);
  // VfsBase.PauseVfs;
  // VfsBase.RefreshVfs;
  // VfsBase.RunVfs(SORT_FIFO);
  // ReadFileContents('D:\heroes 3\data\s\__T.erm', s);
  // s := copy(s, 1, 100);
  // VarDump([s]);
  // exit;
end.