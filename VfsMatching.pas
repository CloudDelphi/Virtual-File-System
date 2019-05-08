unit VfsMatching;
(*
  Description: Implements NT files matching strategy, same as RtlIsNameInExpression.
  @link https://blogs.msdn.microsoft.com/jeremykuhne/2017/06/04/wildcards-in-windows/
  @link https://devblogs.microsoft.com/oldnewthing/?p=24143
*)


(***)  interface  (***)

uses
  SysUtils,
  Utils, PatchForge;


function CompilePattern (const Pattern: WideString): Utils.TArrayOfByte;
function MatchPattern (const Str: WideString; {n} Pattern: pointer): boolean; overload;
function MatchPattern (const Str, Pattern: WideString): boolean; overload;


(***)  implementation  (***)


const
  (* File name without last separator and extension: ~([^.]*+\z|.*(?=\.))~ *)
  DOS_STAR = '<';
  
  (* Dos single char or before dot/end: ~((?=\.)|.?)~ *)
  DOS_QM = '>';

  (* Dos dot or string end: ~(\.|\z)~ *)
  DOS_DOT = '"';

  MAX_STR_LEN = High(word);


type
  TPatternKind = (KIND_CHAR, KIND_ANY_CHAR, KIND_ANY_CHARS, KIND_DOS_ANY_CHAR, KIND_DOS_ANY_CHARS, KIND_DOS_DOT, KIND_END);

  PPattern = ^TPattern;
  TPattern = record
    Kind: TPatternKind;
    Len:  word;
    Ch:   WideChar;
  end;


function CompilePattern (const Pattern: WideString): Utils.TArrayOfByte;
var
{O} Compiled:        PatchForge.TPatchHelper;
    PrevPatternKind: TPatternKind;
    NextPatternKind: TPatternKind;
    SkipPattern:     boolean;
    c:               WideChar;
    i:               integer;

begin
  Compiled := PatchForge.TPatchHelper.Wrap(PatchForge.TPatchMaker.Create);
  // * * * * * //
  PrevPatternKind := KIND_END;

  for i := 1 to Length(Pattern) do begin
    c           := Pattern[i];
    SkipPattern := false;

    case c of
      '?': NextPatternKind := KIND_ANY_CHAR;
      
      '*': begin
        NextPatternKind := KIND_ANY_CHARS;
        SkipPattern     := PrevPatternKind = KIND_ANY_CHARS;
      end;

      DOS_STAR: begin
        NextPatternKind := KIND_DOS_ANY_CHARS;
        SkipPattern     := PrevPatternKind = KIND_DOS_ANY_CHARS;
      end;
      
      DOS_QM: NextPatternKind := KIND_DOS_ANY_CHAR;
      
      DOS_DOT: NextPatternKind := KIND_DOS_DOT;
    else
      NextPatternKind := KIND_CHAR;
    end; // .switch

    if not SkipPattern then begin
      with PPattern(Compiled.AllocAndSkip(sizeof(TPattern)))^ do begin
        Kind := NextPatternKind;
        Ch   := c;
      end;
    end;

    PrevPatternKind := NextPatternKind;
  end; // .for

  PPattern(Compiled.AllocAndSkip(sizeof(TPattern))).Kind := KIND_END;
  result := Compiled.GetPatch;
  // * * * * * //
  Compiled.Release;
end; // .function CompilePattern

function MatchPattern (const Str: WideString; {n} Pattern: pointer): boolean; overload;
var
{Un} Subpattern: PPattern;
     StrLen:     integer;
     StrStart:   PWideChar;
     StrEnd:     PWideChar;
     s:          PWideChar;

  function MatchSubpattern: boolean;
  var
    DotFinder: PWideChar;

  begin
    result         := false;
    Subpattern.Len := 1;

    case Subpattern.Kind of
      KIND_CHAR: begin
        result := s^ = Subpattern.Ch;
      end;

      KIND_ANY_CHAR: begin
        result := s <> StrEnd;
      end;

      KIND_DOS_ANY_CHAR: begin
        result := true;

        if (s^ = '.') or (s = StrEnd) then begin
          Subpattern.Len := 0;
        end;
      end;

      KIND_DOS_DOT: begin
        result := (s^ = '.') or (s = StrEnd);
        
        if s = StrEnd then begin
          Subpattern.Len := 0;
        end;
      end;

      KIND_DOS_ANY_CHARS: begin
        result := true;

        if s^ <> '.' then begin
          DotFinder := StrEnd;

          while (DotFinder > s) and (DotFinder^ <> '.') do begin
            Dec(DotFinder);
          end;

          if DotFinder^ <> '.' then begin
            DotFinder := StrEnd;
          end;
        end else begin
          DotFinder := s;
        end;

        Subpattern.Len := DotFinder - s;
      end; // .case KIND_DOS_ANY_CHARS

      KIND_ANY_CHARS: begin
        result         := true;
        Subpattern.Len := 0;
      end;

      KIND_END: begin
        result         := s = StrEnd;
        Subpattern.Len := 0;
      end;
    end; // .switch

    if result then begin
      Inc(s, Subpattern.Len);
    end;
  end; // .function MatchSubpattern

  function Recover: boolean;
  var
    NextSubpattern: PPattern;
    NextChar:       WideChar;
    Caret:          PWideChar;

  begin
    result := false;

    while not result and (cardinal(Subpattern) >= cardinal(Pattern)) do begin
      case Subpattern.Kind of
        KIND_ANY_CHARS: begin
          if s < StrEnd then begin
            result         := true;
            NextSubpattern := Utils.PtrOfs(Subpattern, sizeof(TPattern));
            Inc(Subpattern.Len);
            Inc(s);
  
            (* Fast consume to the end: xxx* *)
            if NextSubpattern.Kind = KIND_END then begin
              Inc(Subpattern.Len, StrEnd - s);
              s := StrEnd;
            end
            (* Fast search for special character: *carry *)
            else if NextSubpattern.Kind = KIND_CHAR then begin
              NextChar := NextSubpattern.Ch;
              Caret    := s;
              
              while (Caret < StrEnd) and (Caret^ <> NextChar) do begin
                Inc(Caret);
              end;

              if Caret < StrEnd then begin
                Inc(Subpattern.Len, Caret - s);
                s := Caret;
              end else begin
                result := false;
              end;              
            end; // .elseif
          end else begin
            Dec(s, Subpattern.Len);
          end; // .else
        end; // .case KIND_ANY_CHARS
      else
        Dec(s, Subpattern.Len);
      end; // .switch

      if result then begin
        Inc(Subpattern);
      end else begin
        Dec(Subpattern);
      end;
    end; // .while
  end; // .function Recover

begin
  Subpattern := Pattern;
  StrLen     := Length(Str);
  StrStart   := PWideChar(Str);
  StrEnd     := StrStart + StrLen;
  s          := StrStart;
  // * * * * * //
  if Pattern = nil then begin
    result := Str = '';
    exit;
  end;

  if StrLen > MAX_STR_LEN then begin
    result := false;
    exit;
  end;

  while cardinal(Subpattern) >= cardinal(Pattern) do begin
    if MatchSubpattern then begin
      if Subpattern.Kind = KIND_END then begin
        break;
      end;

      Inc(Subpattern);
    end else begin
      Dec(Subpattern);
      Recover;
    end;
  end;

  result := (cardinal(Subpattern) >= cardinal(Pattern)) and (s^ = #0);
end; // .function MatchPattern

function MatchPattern (const Str, Pattern: WideString): boolean; overload;
var
  CompiledPattern: Utils.TArrayOfByte;

begin
  CompiledPattern := CompilePattern(Pattern);
  result          := MatchPattern(Str, pointer(CompiledPattern));
end;

end.