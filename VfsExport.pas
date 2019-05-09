unit VfsExport;
(*
  
*)


(***)  interface  (***)

uses
  VfsDebug, VfsBase, VfsControl;

exports
  VfsDebug.SetLoggingProc,
  VfsDebug.WriteLog_ name 'WriteLog',
  VfsControl.RunVfs,
  VfsBase.PauseVfs,
  VfsBase.ResetVfs,
  VfsBase.CallWithoutVfs;


(***)  implementation  (***)


function MapDir (const VirtPath, RealPath: PWideChar; OverwriteExisting: boolean; Flags: integer = 0): boolean; stdcall;
begin
  result := VfsBase.MapDir(WideString(VirtPath), WideString(RealPath), OverwriteExisting, Flags);
end;

exports
  MapDir;

end.
