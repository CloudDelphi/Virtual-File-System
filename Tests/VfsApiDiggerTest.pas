unit VfsApiDiggerTest;

(***)  interface  (***)

uses
  Windows, SysUtils, TestFramework,
  Utils, WinUtils, DataLib,
  VfsApiDigger;

type
  TestApiDigger = class (TTestCase)
   published
    procedure DetermineRealApiAddress;
  end;


(***)  implementation  (***)


procedure TestApiDigger.DetermineRealApiAddress;
type
  TGetCurrentProcessId = function (): integer; stdcall;

var
  Kernel32Handle:   THandle;
  KernelBaseHandle: THandle;
  NormalProc:       TGetCurrentProcessId;
  RealProc:         TGetCurrentProcessId;
  TestProc:         TGetCurrentProcessId;

begin
  Kernel32Handle   := Windows.GetModuleHandle('kernel32.dll');
  KernelBaseHandle := Windows.GetModuleHandle('kernelbase.dll');

  if (Kernel32Handle <> 0) and (KernelBaseHandle <> 0) then begin
    NormalProc := Windows.GetProcAddress(Kernel32Handle, 'GetCurrentProcessId');
    RealProc   := Windows.GetProcAddress(KernelBaseHandle, 'GetCurrentProcessId');

    if (@NormalProc <> nil) and (@RealProc <> nil) then begin
      VfsApiDigger.FindOutRealSystemApiAddrs([Kernel32Handle]);
      TestProc := VfsApiDigger.GetRealProcAddress(Kernel32Handle, 'GetCurrentProcessId');
      Check(@TestProc = @RealProc, Format('Failed to get real api address. Normal address: %x, Real address: %x, Got address: %x', [Int(@NormalProc), Int(@RealProc), Int(@TestProc)]));
    end;
  end;
end;

begin
  RegisterTest(TestApiDigger.Suite);
end.