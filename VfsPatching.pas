unit VfsPatching;
(*
  Description: Code patching facilities, based on PatchForge library.
               All hooks are thread-safe.
*)

(***)  interface  (***)

uses
  Windows, SysUtils, Utils, PatchForge, Concur;

type
  PAppliedPatch = ^TAppliedPatch;
  TAppliedPatch = record
    Addr:  pointer;
    Bytes: Utils.TArrayOfByte;

    procedure Rollback;
  end;


(* Replaces original STDCALL function with the new one with the same prototype and one extra argument.
   The argument is callable pointer, used to execute original function. The pointer is passed as THE FIRST
   argument before other arguments. *)
function SpliceWinApi (OrigFunc, HandlerFunc: pointer; {n} AppliedPatch: PAppliedPatch = nil): pointer;


(***)  implementation  (***)


type
  (* Import *)
  TPatchMaker  = PatchForge.TPatchMaker;
  TPatchHelper = PatchForge.TPatchHelper;

const
  PERSISTENT_MEM_CAPACITY = 100 * 1024;

var
  PersistentMemCritSection: Concur.TCritSection;
  PersistentMem:            array [0..PERSISTENT_MEM_CAPACITY - 1] of byte;
  PersistentMemPos:         integer;


procedure AllocPersistentMem (var Addr; Size: integer);
begin
  {!} Assert(@Addr <> nil);
  {!} Assert(Size >= 0);

  with PersistentMemCritSection do begin
    Enter;
    pointer(Addr) := nil;

    try
      if PersistentMemPos + Size > High(PersistentMem) then begin
        raise EOutOfMemory.Create('Failed to allocate another persistent memory block of size ' + SysUtils.IntToStr(Size));
      end;

      pointer(Addr) := @PersistentMem[PersistentMemPos];
      Inc(PersistentMemPos, Size);
    finally
      Leave;
    end;
  end; // .with
end; // .procedure AllocPersistentMem

(* Writes arbitrary data to any write-protected section *)
function WriteAtCode (NumBytes: integer; {n} Src, {n} Dst: pointer): boolean;
var
  OldPageProtect: integer;

begin
  {!} Assert(Utils.IsValidBuf(Src, NumBytes));
  {!} Assert(Utils.IsValidBuf(Dst, NumBytes));
  result := NumBytes = 0;

  if not result then begin
    try
      result := Windows.VirtualProtect(Dst, NumBytes, Windows.PAGE_EXECUTE_READWRITE, @OldPageProtect);
      
      if result then begin
        Utils.CopyMem(NumBytes, Src, Dst);
        Windows.VirtualProtect(Dst, NumBytes, OldPageProtect, @OldPageProtect);
      end;
    except
      result := false;
    end;
  end; // .if
end; // .function WriteAtCode

(* Writes patch to any write-protected section *)
function WritePatchAtCode (PatchMaker: TPatchMaker; {n} Dst: pointer): boolean;
var
  Buf: Utils.TArrayOfByte;

begin
  {!} Assert(PatchMaker <> nil);
  {!} Assert((Dst <> nil) or (PatchMaker.Size = 0));
  // * * * * * //
  result := true;

  if PatchMaker.Size > 0 then begin
    SetLength(Buf, PatchMaker.Size);
    PatchMaker.ApplyPatch(pointer(Buf), Dst);
    result := WriteAtCode(Length(Buf), pointer(Buf), Dst);
  end;
end; // .function WritePatchAtCode

function SpliceWinApi (OrigFunc, HandlerFunc: pointer; {n} AppliedPatch: PAppliedPatch = nil): pointer;
const
  CODE_ADDR_ALIGNMENT = 8;

var
{O}  p:                      PatchForge.TPatchHelper;
{OI} SpliceBridge:           pbyte; // Memory is never freed        
     OrigFuncBridgeLabel:    string;
     OrigCodeBridgeStartPos: integer;
     OverwrittenCodeSize:    integer;

begin
  {!} Assert(OrigFunc <> nil);
  {!} Assert(HandlerFunc <> nil);
  p            := TPatchHelper.Wrap(TPatchMaker.Create);
  SpliceBridge := nil;
  result       := nil;
  // * * * * * //

  // === BEGIN generating SpliceBridge ===
  // Add pointer to original function bridge as the first argument
  p.WriteTribyte(PatchForge.INSTR_PUSH_PTR_ESP);
  p.WriteInt(PatchForge.INSTR_MOV_ESP_PLUS_4_CONST32);
  p.ExecActionOnApply(PatchForge.TAddLabelRealAddrAction.Create(p.NewAutoLabel(OrigFuncBridgeLabel)));
  p.WriteInt(0);

  // Jump to new handler
  p.Jump(PatchForge.JMP, HandlerFunc);
  
  // Ensure original code bridge is aligned
  p.Nop(p.Pos mod CODE_ADDR_ALIGNMENT);

  // Set result to offset from splice bridge start to original function bridge
  result := pointer(p.Pos);
  
  // Write original function bridge
  p.PutLabel(OrigFuncBridgeLabel);
  OrigCodeBridgeStartPos := p.Pos;
  p.WriteCode(OrigFunc, PatchForge.TMinCodeSizeDetector.Create(sizeof(PatchForge.TJumpCall32Rec)));
  OverwrittenCodeSize := p.Pos - OrigCodeBridgeStartPos;
  p.Jump(PatchForge.JMP, Utils.PtrOfs(OrigFunc, OverwrittenCodeSize));
  // === END generating SpliceBridge ===

  // Persist splice bridge
  AllocPersistentMem(SpliceBridge, p.Size);
  WritePatchAtCode(p.PatchMaker, SpliceBridge);

  // Turn result from offset to absolute address
  result := Ptr(integer(SpliceBridge) + integer(result));

  // Create and apply hook at target function start
  p.Clear();
  p.Jump(PatchForge.JMP, SpliceBridge);
  p.Nop(OverwrittenCodeSize - p.Pos);

  if AppliedPatch <> nil then begin
    AppliedPatch.Addr := OrigFunc;
    SetLength(AppliedPatch.Bytes, p.Size);
    Utils.CopyMem(p.Size, OrigFunc, @AppliedPatch.Bytes[0]);
  end;

  WritePatchAtCode(p.PatchMaker, OrigFunc);
  // * * * * * //
  p.Release;
end;

procedure TAppliedPatch.Rollback;
begin
  if Self.Bytes <> nil then begin
    WriteAtCode(Length(Self.Bytes), @Self.Bytes[0], Self.Addr);
  end;
end;

begin
  PersistentMemCritSection.Init;
end.