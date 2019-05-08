unit VfsMatchingTest;

(***)  interface  (***)

uses
  SysUtils, TestFramework,
  Utils, VfsMatching;

type
  TestMatching = class (TTestCase)
   published
    procedure TestMatchPattern;
  end;

(***)  implementation  (***)


procedure TestMatching.TestMatchPattern ();
begin
  Check(VfsMatching.MatchPattern('Nice picture.bak.bmp', '<.b?p>'), '{1}');
  CheckFalse(VfsMatching.MatchPattern('Nice picture.bak.bmp', '<.b?mp>'), '{2}');
  Check(VfsMatching.MatchPattern('this abb is a long abba story.txt', '*abba*.>xt>>>'), '{3}');
  Check(VfsMatching.MatchPattern('what a brave', '*??r*<"""'), '{4}');
  Check(VfsMatching.MatchPattern('.', '*<<*""">>>*<<""'), '{5}');
  Check(VfsMatching.MatchPattern('', ''), '{6}');
  CheckFalse(VfsMatching.MatchPattern('opportunity.png', '*p'), '{7}');
  Check(VfsMatching.MatchPattern('opportunity.png', '*p*'), '{8}');
  Check(VfsMatching.MatchPattern('', '*'), '{9}');
  Check(VfsMatching.MatchPattern('.?.', '*'), '{10}');
  Check(VfsMatching.MatchPattern('its the last hero of the night.docx', '*the*hero<.doc?'), '{11}');
end;

begin
  RegisterTest(TestMatching.Suite);
end.