unit VfsImport;
(*
  
*)


(***)  interface  (***)

uses
  SysUtils, Utils;

type
  (*
    Specifies the order, in which files from different mapped directories will be listed in virtual directory.
    Virtual directory sorting is performed by priorities firstly and lexicographically secondly.
    SORT_FIFO - Items of the first mapped directory will be listed before the second mapped directory items.
    SORT_LIFO - Items of The last mapped directory will be listed before all other mapped directory items.
  *)
  TDirListingSortType = (SORT_FIFO = 0, SORT_LIFO = 1);

(* Loads mod list from file and maps each mod directory to specified root directory.
   File with mod list is treated as (BOM or BOM-less) UTF-8 plain text file, where each mod name is separated
   from another one via Line Feed (#10) character. Each mod named is trimmed, converted to UCS16 and validated before
   adding to list. Invalid or empty mods will be skipped. Mods are mapped in reverse order, as compared to their order in file.
   Returns true if root and mods directory existed and file with mod list was loaded successfully *)
function MapModsFromList (const RootDir, ModsDir, ModListFile: PWideChar; Flags: integer = 0): LONGBOOL; stdcall; external 'vfs.dll';

(* Runs all VFS subsystems, unless VFS is already running *)
function RunVfs (DirListingOrder: TDirListingSortType): LONGBOOL; stdcall; external 'vfs.dll';

(* Spawns separate thread, which starts recursive monitoring for changes in specified directory.
   VFS will be fully refreshed or smartly updated on any change. Debounce interval specifies
   time in msec to wait after last change before running full VFS rescanning routine *)
function RunWatcher (const WatchDir: PWideChar; DebounceInterval: integer): LONGBOOL; stdcall; external 'vfs.dll';

(* Frees buffer, that was transfered to client earlier using other VFS API *)
procedure MemFree ({O} Buf: pointer); stdcall; external 'vfs.dll';

(* Returns text with all applied mappings, separated via #13#10. If ShortenPaths is true, common part
   of real and virtual paths is stripped. Call MemFree to release result buffer *)
function GetMappingsReport: {O} PWideChar; stdcall; external 'vfs.dll';
function GetMappingsReportA: {O} pchar; stdcall; external 'vfs.dll';

(* Allocates console and install logger, writing messages to console *)
procedure InstallConsoleLogger; stdcall; external 'vfs.dll';


(***)  implementation  (***)


end.