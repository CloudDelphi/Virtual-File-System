unit VfsControl;
(*
  Facade unit for high-level VFS API.
*)


(***)  interface  (***)

uses
  Windows, SysUtils,
  Utils,
  VfsBase, VfsUtils, VfsHooks;


(* Runs all VFS subsystems, unless VFS is already running *)
function RunVfs (DirListingOrder: VfsBase.TDirListingSortType): boolean;


(***)  implementation  (***)


function GetCurrentDirW: WideString;
var
  Buf:    array [0..32767 - 1] of WideChar;
  ResLen: integer;

begin
  result := '';
  ResLen := Windows.GetCurrentDirectoryW(sizeof(Buf), @Buf);

  if ResLen > 0 then begin
    SetLength(result, ResLen);
    Utils.CopyMem(ResLen * sizeof(WideChar), @Buf, PWideChar(result));
  end;
end;

function SetCurrentDirW (const DirPath: WideString): boolean;
var
  AbsPath: WideString;

begin
  AbsPath := VfsUtils.NormalizePath(DirPath);
  result  := Windows.SetCurrentDirectoryW(PWideChar(AbsPath));
end;

function RunVfs (DirListingOrder: VfsBase.TDirListingSortType): boolean;
var
  CurrDir: WideString;

begin
  with VfsBase.VfsCritSection do begin
    Enter;

    result := VfsBase.RunVfs(DirListingOrder);
    
    if result then begin
      VfsHooks.InstallHooks;

      // Try to ensure, that current directory handle is tracked by VfsOpenFiles
      CurrDir := GetCurrentDirW;

      if CurrDir <> '' then begin
        SetCurrentDirW(CurrDir);
      end;
    end;

    Leave;
  end; // .with
end; // function RunVfs

end.