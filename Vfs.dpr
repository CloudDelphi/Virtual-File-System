library Vfs;
(*
  Author: Alexander Shostak aka Berserker aka EtherniDee.
*)

uses Windows;

procedure DLLEntryPoint (Reason: DWORD);
begin
  // Stop VFS globally!!!!!!!!!
end;

begin
  if System.DllProc = nil then begin
    System.DllProc := @DLLEntryPoint;
    DllEntryPoint(Windows.DLL_PROCESS_ATTACH);
  end;
end.
