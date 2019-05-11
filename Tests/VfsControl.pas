unit VfsControl;
(*
  Facade unit for high-level VFS API.
*)


(***)  interface  (***)

uses
  Windows, SysUtils,
  Utils, WinUtils, TypeWrappers, DataLib,
  Files, StrLib,
  VfsBase, VfsUtils, VfsHooks, DlgMes;

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

function LoadModList (const ModListFilePath: WideString): {O} DataLib.TList {of (O) TWideString};
var
  AbsFilePath:  WideString;
  FileContents: string;
  Lines:        Utils.TArrayOfStr;
  ModNameUtf8:  string;
  ModName:      WideString;
  i:            integer;

begin
  result := DataLib.NewList(Utils.OWNS_ITEMS);
  // * * * * * //
  AbsFilePath := VfsUtils.NormalizePath(ModListFilePath);

  if (AbsFilePath <> '') and (Files.ReadFileContents(AbsFilePath, FileContents)) then begin
    Lines := StrLib.Explode(FileContents, #10);

    for i := 0 to High(Lines) do begin
      ModNameUtf8 := Lines[i];
      ModName     := StrLib.Utf8ToWide(ModNameUtf8);

      if ValidateModName(ModName) then begin
        result.Add(TWideString.Create(ModName));
      end;
    end;
  end;
end; // .function LoadModList

// function MapModsDir (const RootDir, ModsDir: WideString; Flags: integer = 0);
// var
//   AbsRootDir: WideString;
//   AbsModsDir: WideString;
//   FileInfo:   VfsUtils.TNativeFileInfo;
//   ModName:    WideString;


// begin
//   AbsRootDir := VfsUtils.NormalizePath(RootDir);
//   AbsModsDir := VfsUtils.NormalizePath(ModsDir);
//   result     := (AbsRootDir <> '') and (AbsModsDir <> '') and VfsUtils.GetFileInfo(AbsRootDir, FileInfo);
//   result     := result and Utils.HasFlag(Windows.FILE_ATTRIBUTE_DIRECTORY, FileInfo.Base.FileAttributes);
//   result     := result and VfsUtils.GetFileInfo(AbsModsDir, FileInfo);
//   result     := result and Utils.HasFlag(Windows.FILE_ATTRIBUTE_DIRECTORY, FileInfo.Base.FileAttributes);
  
//   if result then begin
//     with VfsUtils.SysScanDir(AbsModsDir, '*') do begin
//       while IterNext(ModName, @FileInfo.Base) do begin
//         if (ModName <> '.') and (ModName <> '..') and Utils.HasFlag(Windows.FILE_ATTRIBUTE_DIRECTORY, FileInfo.Base.FileAttributes) then begin
          
//         end;
//       end;
//     end;
//   end;
// end;

var
L: TList;
i: integer;

begin
  // L := LoadModList('D:\Heroes 3\Mods\list.txt');
  // for i := 0 to L.Count- 1 do begin
  //   VarDump([TWideString(L[i]).Value]);
  // end;
end.