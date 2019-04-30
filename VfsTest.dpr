program VfsTest;

uses
  TestFramework, GuiTestRunner,
  VfsUtils, VfsBase, VfsDebug, VfsExport,
  VfsDebugTest;

begin
  TGUITestRunner.RunRegisteredTests;
end.

