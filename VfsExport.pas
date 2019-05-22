unit VfsExport;
(*
  
*)


(***)  interface  (***)

uses
  Windows,
  VfsDebug, VfsBase, VfsControl, DlgMes, Files, FilesEx;

exports
  VfsDebug.SetLoggingProc,
  VfsDebug.WriteLog_ name 'WriteLog',
  VfsControl.RunVfs,
  VfsBase.PauseVfs,
  VfsBase.ResetVfs,
  VfsBase.RefreshVfs,
  VfsBase.CallWithoutVfs;


(***)  implementation  (***)


function MapDir (const VirtPath, RealPath: PWideChar; OverwriteExisting: boolean; Flags: integer = 0): LONGBOOL; stdcall;
begin
  result := VfsBase.MapDir(WideString(VirtPath), WideString(RealPath), OverwriteExisting, Flags);
end;

function MapDirA (const VirtPath, RealPath: PAnsiChar; OverwriteExisting: boolean; Flags: integer = 0): LONGBOOL; stdcall;
begin
  result := VfsBase.MapDir(WideString(VirtPath), WideString(RealPath), OverwriteExisting, Flags);
end;

function MapModsFromList (const RootDir, ModsDir, ModListFile: PWideChar; Flags: integer = 0): LONGBOOL; stdcall;
begin
  result := VfsControl.MapModsFromList(WideString(RootDir), WideString(ModsDir), WideString(ModListFile), Flags);
end;

function MapModsFromListA (const RootDir, ModsDir, ModListFile: PAnsiChar; Flags: integer = 0): LONGBOOL; stdcall;
begin
  result := VfsControl.MapModsFromList(WideString(RootDir), WideString(ModsDir), WideString(ModListFile), Flags);
end;

exports
  MapDir,
  MapDirA,
  MapModsFromList,
  MapModsFromListA;

// var s: string;
// begin
//   assert(MapModsFromListA('D:\Heroes 3', 'D:\Heroes 3\Mods', 'D:\Heroes 3\Mods\list.txt'));
//   VfsControl.RunVfs(SORT_FIFO);
//   ReadFileContents('D:\Heroes 3\Data\s\pHoenix.erm', s);
//   VarDump([GetFileList('D:\Heroes 3\Data\s\*', FILES_AND_DIRS).ToText(#13#10)]);
end.
