unit VfsTestHelper;
(*
  
*)


(***)  interface  (***)

uses
  SysUtils, Windows,
  Utils, WinUtils, StrLib;

(* Initializes debug console *)
procedure InitConsole;

(* Returns absolute path to directory with test contents *)
function GetTestsRootDir: WideString;


(***)  implementation  (***)


procedure InitConsole;
var
  Rect:    TSmallRect;
  BufSize: TCoord;
  hIn:     THandle;
  hOut:    THandle;

begin
  AllocConsole;
  SetConsoleCP(GetACP);
  SetConsoleOutputCP(GetACP);
  hIn                       := GetStdHandle(STD_INPUT_HANDLE);
  hOut                      := GetStdHandle(STD_OUTPUT_HANDLE);
  pinteger(@System.Input)^  := hIn;
  pinteger(@System.Output)^ := hOut;
  BufSize.x                 := 120;
  BufSize.y                 := 1000;
  SetConsoleScreenBufferSize(hOut, BufSize);
  Rect.Left                 := 0;
  Rect.Top                  := 0;
  Rect.Right                := 120 - 1;
  Rect.Bottom               := 50 - 1;
  SetConsoleWindowInfo(hOut, true, Rect);
  SetConsoleTextAttribute(hOut, (0 shl 4) or $0F);
end; // .procedure InitConsole;

function GetTestsRootDir: WideString;
var
  Caret: PWideChar;

begin
  result := WinUtils.GetExePath;
  {!} Assert(result <> '', 'Failed to get full path to current executable file');
  
  result := StrLib.ExtractDirPathW(WinUtils.GetExePath);
  {!} Assert(result <> '', 'Failed to extract executable file directory path');

  if result[Length(result)] <> '\' then begin
    result := result + '\Tests\Fs';
  end else begin
    result := result + 'Tests\Fs';
  end;
end; // .function GetTestsRootDir

end.