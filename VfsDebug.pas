unit VfsDebug;
(*
  Author:      Alexander Shostak aka Berserker aka Ethernidee.
  Description: Provides logging and debugging capabilities for VFS project.
*)


(***)  interface  (***)

uses
  Windows, SysUtils,
  Utils, StrLib, Concur, DlgMes;

type
  TLoggingProc = procedure (Operation, Message: pchar); stdcall;

  EAssertFailure = class (Exception)
  end;


function  SetLoggingProc ({n} Handler: TLoggingProc): {n} TLoggingProc; stdcall;
procedure WriteLog (const Operation, Message: string);
procedure WriteLog_ (const Operation, Message: pchar);


var
  (* For external non-100% reliable fast checks of logging subsystem state *)
  LoggingEnabled: boolean = false;


(***)  implementation  (***)


var
    LogCritSection: Concur.TCritSection;
{n} LoggingProc:    TLoggingProc;


function SetLoggingProc ({n} Handler: TLoggingProc): {n} TLoggingProc; stdcall;
begin
  with LogCritSection do begin
    Enter;
    result         := @LoggingProc;
    LoggingProc    := Handler;
    LoggingEnabled := @LoggingProc <> nil;
    Leave;
  end;
end;

procedure WriteLog (const Operation, Message: string);
begin
  WriteLog_(pchar(Operation), pchar(Message));
end;

procedure WriteLog_ (const Operation, Message: pchar);
begin
  if LoggingEnabled then begin
    with LogCritSection do begin
      Enter;

      if @LoggingProc <> nil then begin
        LoggingProc(Operation, Message);
      end;
      
      Leave;
    end;
  end;
end;

procedure AssertHandler (const Mes, FileName: string; LineNumber: integer; Address: pointer);
var
  CrashMes: string;

begin
  CrashMes := StrLib.BuildStr
  (
    'Assert violation in file "~FileName~" on line ~Line~.'#13#10'Error at address: $~Address~.'#13#10'Message: "~Message~"',
    [
      'FileName', FileName,
      'Line',     SysUtils.IntToStr(LineNumber),
      'Address',  SysUtils.Format('%x', [integer(Address)]),
      'Message',  Mes
    ],
    '~'
  );
  
  WriteLog('AssertHandler', CrashMes);

  DlgMes.MsgError(CrashMes);

  raise EAssertFailure.Create(CrashMes) at Address;
end; // .procedure AssertHandler


begin
  LogCritSection.Init;
  AssertErrorProc := AssertHandler;
end.