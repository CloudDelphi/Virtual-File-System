unit VfsControl;
(*
  Facade unit for high-level VFS API.
*)


(***)  interface  (***)

uses
  Windows, SysUtils,
  Utils, WinUtils, TypeWrappers, DataLib,
  Files, StrLib,
  VfsBase, VfsUtils, VfsHooks, DlgMes {FIXME DELETEME};

type
  (* Import *)
  TWideString = TypeWrappers.TWideString;

const
  (* Flag forces to skip directory names, starting with '#' *)
  SKIP_HASHTAGGED_MODS = 1;


(* Runs all VFS subsystems, unless VFS is already running *)
function RunVfs (DirListingOrder: VfsBase.TDirListingSortType): boolean; stdcall;


(***)  implementation  (***)


function RunVfs (DirListingOrder: VfsBase.TDirListingSortType): boolean; stdcall;
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

// function LoadModList (const ModListFilePath: WideString; {O} var {out} ModList: DataLib.TList {of (O) TWideString}): boolean;
// var
//   AbsFilePath:  WideString;
//   FileHandle:   integer;
//   FileContents: string;
//   Lines:        Utils.TArrayOfStr;
//   ModNameUtf8:  string;
//   ModName:      WideString;
//   i:            integer;

//   // FIXME ModList is not result

// begin
//   result := DataLib.NewList(Utils.OWNS_ITEMS);
//   // * * * * * //
//   AbsFilePath := VfsUtils.NormalizePath(ModListFilePath);
//   FileHandle  := Windows.CreateFileW(PWideChar(AbsFilePath), Windows.GENERIC_READ, Windows.FILE_SHARE_READ, nil, Windows.OPEN_EXISTING, 0, nil);
//   // Make available UNICODE path
//   // Make UTF8 BOM support EF BB BF

//   if (AbsFilePath <> '') and (Files.ReadFileContents(AbsFilePath, FileContents)) then begin
//     Lines := StrLib.Explode(FileContents, #10);

//     for i := 0 to High(Lines) do begin
//       ModNameUtf8 := Lines[i];
//       ModName     := StrLib.TrimW(StrLib.Utf8ToWide(ModNameUtf8, StrLib.FAIL_ON_ERROR));

//       if ValidateModName(ModName) then begin
//         result.Add(TWideString.Create(ModName));
//       end;
//     end;
//   end;
// end; // .function LoadModList

function MapModsFromList_ (const RootDir, ModsDir: WideString; ModList: TList {of (O) TWideString}; Flags: integer = 0): boolean;
var
  AbsRootDir:        WideString;
  AbsModsDir:        WideString;
  FileInfo:          VfsUtils.TNativeFileInfo;
  ModName:           WideString;
  ModPathPrefix:     WideString;
  NumFailedMappings: integer;
  i:                 integer;

begin
  {!} Assert(ModList <> nil);
  // * * * * * //
  AbsRootDir := VfsUtils.NormalizePath(RootDir);
  AbsModsDir := VfsUtils.NormalizePath(ModsDir);
  result     := (AbsRootDir <> '') and (AbsModsDir <> '') and VfsUtils.GetFileInfo(AbsRootDir, FileInfo);
  result     := result and Utils.HasFlag(Windows.FILE_ATTRIBUTE_DIRECTORY, FileInfo.Base.FileAttributes);
  result     := result and VfsUtils.GetFileInfo(AbsModsDir, FileInfo);
  result     := result and Utils.HasFlag(Windows.FILE_ATTRIBUTE_DIRECTORY, FileInfo.Base.FileAttributes);
  
  if result then begin
    ModPathPrefix     := VfsUtils.AddBackslash(AbsModsDir);
    NumFailedMappings := 0;

    for i := ModList.Count - 1 downto 0 do begin
      ModName := TWideString(ModList[i]).Value;

      if not VfsBase.MapDir(AbsRootDir, ModPathPrefix + ModName, not VfsBase.OVERWRITE_EXISTING, Flags) then begin
        Inc(NumFailedMappings);
      end;
    end;

    result := (NumFailedMappings = 0) or (NumFailedMappings < ModList.Count);
  end; // .if
end; // .function MapModsFromList

function MapModsFromList (const RootDir, ModsDir, ModListFile: WideString; Flags: integer = 0): boolean;
begin
  
end;

var
L: TList;
i: integer;

begin

end.