unit VfsApiDigger;
(*
  Description: Provides means for detecting real WinAPI functions addresses, bypassing proxy dlls and
               other low level code routines.
*)


(***)  interface  (***)

uses
  SysUtils, Windows,
  Utils, DataLib, PatchForge;


(* Determines real exported API addresses for all specified DLL handles. If DLL imports function
   with the same name, as the exported one, then imported one is treated as real function.
   Example: kernel32.ReadProcessMemory can be a bridge to imported kernelbase.ReadProcessMemory.
   If DLL handle was processed earlier, it's skipped *)
procedure FindOutRealSystemApiAddrs (const DllHandles: array of integer);

(* Returns real code address, bypassing possibly nested simple redirection stubs like JMP [...] or JMP XXX. *)
function GetRealAddress (CodeOrRedirStub: pointer): {n} pointer;

(* Enhanced version of kernel32.GetProcAddress, traversing bridge chains and using info, gained by FindOutRealSystemApiAddrs earlier *)
function GetRealProcAddress (DllHandle: integer; const ProcName: string): {n} pointer;


(***)  implementation  (***)


var
(* Map of DLL handle => API name => Real api address *)
{O} DllRealApiAddrs: {O} TObjDict {OF TDict};


procedure FindOutRealSystemApiAddrs (const DllHandles: array of integer);
const
  PE_SIGNATURE_LEN = 4;

type
  PImageImportDirectory = ^TImageImportDirectory;
  TImageImportDirectory = packed record
    RvaImportLookupTable:  integer;
    TimeDateStamp:         integer;
    ForwarderChain:        integer;
    RvaModuleName:         integer;
    RvaImportAddressTable: integer;
  end;

  PHintName = ^THintName;
  THintName = packed record
    Hint: word;
    Name: array [0..MAXLONGINT - 5] of char;
  end;

var
  ImportDirInfo:     PImageDataDirectory;
  ImportDir:         PImageImportDirectory;
  ImportLookupTable: Utils.PEndlessIntArr;
  ImportAddrTable:   Utils.PEndlessIntArr;
  DllApiRedirs:      {U} TDict {of pointer};
  DllHandle:         integer;
  i, j:              integer;

begin
  ImportDirInfo     := nil;
  ImportDir         := nil;
  ImportLookupTable := nil;
  ImportAddrTable   := nil;
  DllApiRedirs      := nil;
  // * * * * * //
  for i := 0 to high(DllHandles) do begin
    DllHandle     := DllHandles[i];
    ImportDirInfo := @PImageOptionalHeader(DllHandle + PImageDosHeader(DllHandle)._lfanew + PE_SIGNATURE_LEN + sizeof(TImageFileHeader)).DataDirectory[1];
    DllApiRedirs  := DllRealApiAddrs[Ptr(DllHandle)];

    if DllApiRedirs = nil then begin
      DllApiRedirs                    := DataLib.NewDict(NOT Utils.OWNS_ITEMS, DataLib.CASE_SENSITIVE);
      DllRealApiAddrs[Ptr(DllHandle)] := DllApiRedirs;

      // Found valid import directory in Win32 PE
      if ((ImportDirInfo.Size > 0) and (ImportDirInfo.VirtualAddress <> 0)) then begin
        ImportDir := pointer(DllHandle + integer(ImportDirInfo.VirtualAddress));

        while ImportDir.RvaImportLookupTable <> 0 do begin
          ImportLookupTable := pointer(DllHandle + ImportDir.RvaImportLookupTable);
          ImportAddrTable   := pointer(DllHandle + ImportDir.RvaImportAddressTable);

          j := 0;

          while (j >= 0) and (ImportLookupTable[j] <> 0) do begin
            if ImportLookupTable[j] > 0 then begin
              DllApiRedirs[pchar(@PHintName(DllHandle + ImportLookupTable[j]).Name)] := Ptr(ImportAddrTable[j]);
            end;

            Inc(j);
          end;

          Inc(ImportDir);
        end; // .while
      end; // .if
    end; // .if
  end; // .for
end; // .procedure FindOutRealSystemApiAddrs

function GetRealAddress (CodeOrRedirStub: pointer): {n} pointer;
const
 MAX_DEPTH = 100;

var
  Depth: integer;

begin
  {!} Assert(CodeOrRedirStub <> nil);
  result := CodeOrRedirStub;
  Depth  := 0;

  while Depth < MAX_DEPTH do begin
    // JMP DWORD [PTR]
    if pword(result)^ = PatchForge.OPCODE_JMP_PTR_CONST32 then begin
      result := ppointer(integer(result) + sizeof(word))^;
    // JXX SHORT CONST8
    end else if PatchForge.IsShortJumpConst8Opcode(pbyte(result)^) then begin
      result := pointer(integer(result) + sizeof(byte) + pshortint(integer(result) + sizeof(byte))^);
    // JMP NEAR CONST32
    end else if pbyte(result)^ = PatchForge.OPCODE_JMP_CONST32 then begin
      result := pointer(integer(result) + sizeof(PatchForge.TJumpCall32Rec) + pinteger(integer(result) + sizeof(byte))^);
    // JXX (conditional) NEAR CONST32
    end else if PatchForge.IsNearJumpConst32Opcode(pword(result)^) then begin
      result := pointer(integer(result) + sizeof(word) + sizeof(integer) + pinteger(integer(result) + sizeof(word))^);
    // Regular code
    end else begin
      break;
    end; // .else

    Inc(Depth);
  end; // .while
end; // .function GetRealAddress

function GetRealProcAddress (DllHandle: integer; const ProcName: string): {n} pointer;
var
{Un} DllApiRedirs: {U} TDict {OF pointer};

begin
  DllApiRedirs := DllRealApiAddrs[Ptr(DllHandle)];
  result       := nil;
  // * * * * * //

  if DllApiRedirs <> nil then begin
    result := DllApiRedirs[ProcName];
  end;

  if result = nil then begin
    result := Windows.GetProcAddress(DllHandle, pchar(ProcName));
  end;

  if result <> nil then begin
    result := GetRealAddress(result);
  end;
end; // .function GetRealProcAddress

begin
  DllRealApiAddrs := DataLib.NewObjDict(Utils.OWNS_ITEMS);
end.