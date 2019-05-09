unit VfsControl;
(*
  Facade unit for high-level VFS API.
*)


(***)  interface  (***)

uses
  Windows, SysUtils,
  Utils, WinUtils,
  VfsBase, VfsUtils, VfsHooks;


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

end.