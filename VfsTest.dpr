program VfsTest;

uses
  TestFramework, GuiTestRunner,
  VfsUtils, VfsBase, VfsDebug,
  VfsApiDigger, VfsExport, VfsOpenFiles,
  VfsDebugTest, VfsUtilsTest, VfsBaseTest,
  VfsApiDiggerTest, VfsOpenFilesTest;

begin
  TGUITestRunner.RunRegisteredTests;
end.

