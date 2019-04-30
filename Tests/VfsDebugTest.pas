unit VfsDebugTest;
{$ASSERTIONS ON}

(***)  interface  (***)

uses
  SysUtils, TestFramework,
  Utils, VfsDebug;

type
  TestDebug = class (TTestCase)
   published
    procedure TestAssertHandler;
    procedure TestLogging;
  end;

(***)  implementation  (***)


var
  LogContents: string;

procedure ClearLog;
begin
  LogContents := '';
end;

function GetLog: string;
begin
  result := LogContents;
end;

procedure WriteLog (const Operation, Message: pchar); stdcall;
begin
  LogContents := LogContents + Operation + ';' + Message;
end;

procedure TestDebug.TestAssertHandler ();
var
  Raised: boolean;

begin
  Raised := false;

  try
    System.Assert(false, 'Some assertion message');
  except
    on E: VfsDebug.EAssertFailure do Raised := true;
  end;

  Check(Raised, 'Assertion should raise EAssertFailure exception');
end;

procedure TestDebug.TestLogging;
begin
  ClearLog;
  VfsDebug.SetLoggingProc(@WriteLog);
  VfsDebug.WriteLog('TestOperation', 'TestMessage');
  Check(GetLog() = 'TestOperation;TestMessage', 'Custom logging proc should have written certain message to log');

  ClearLog;
  VfsDebug.SetLoggingProc(nil);
  VfsDebug.WriteLog('TestOperation', 'TestMessage');
  Check(GetLog() = '', 'Nil logging proc must not write anything to log');
end;

begin
  RegisterTest(TestDebug.Suite);
end.