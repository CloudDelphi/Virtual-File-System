unit VfsExport;
(*
  
*)


(***)  interface  (***)

uses
  Windows,
  VfsDebug, VfsBase, VfsControl, VfsWatching;

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

function RunWatcher (const WatchDir: PWideChar; DebounceInterval: integer): LONGBOOL; stdcall;
begin
  result := VfsWatching.RunWatcher(WatchDir, DebounceInterval);
end;

procedure ConsoleLoggingProc (Operation, Message: pchar); stdcall;
begin
  WriteLn('>> ', string(Operation), ': ', string(Message), #13#10);
end;

(* Allocates console and install logger, writing messages to console *)
procedure InstallConsoleLogger; stdcall;
var
  Rect:    TSmallRect;
  BufSize: TCoord;
  hIn:     THandle;
  hOut:    THandle;

begin
  AllocConsole;
  SetConsoleCP(GetACP);
  SetConsoleOutputCP(GetACP);
  hIn                       := GetStdHandle(STD_INPUT_HANDLE);
  hOut                      := GetStdHandle(STD_OUTPUT_HANDLE);
  pinteger(@System.Input)^  := hIn;
  pinteger(@System.Output)^ := hOut;
  BufSize.x                 := 120;
  BufSize.y                 := 1000;
  SetConsoleScreenBufferSize(hOut, BufSize);
  Rect.Left                 := 0;
  Rect.Top                  := 0;
  Rect.Right                := 120 - 1;
  Rect.Bottom               := 50 - 1;
  SetConsoleWindowInfo(hOut, true, Rect);
  SetConsoleTextAttribute(hOut, (0 shl 4) or $0F);

  VfsDebug.SetLoggingProc(@ConsoleLoggingProc);
end; // .procedure InitConsole;

exports
  MapDir,
  MapDirA,
  MapModsFromList,
  MapModsFromListA,
  RunWatcher,
  InstallConsoleLogger;

end.
