program VfsTest;

uses
  TestFramework, GuiTestRunner,
  VfsUtils, VfsBase, VfsDebug,
  VfsApiDigger, VfsExport, VfsOpenFiles,
  VfsHooks, VfsControl,
  VfsTestHelper,
  VfsDebugTest, VfsUtilsTest, VfsBaseTest,
  VfsApiDiggerTest, VfsOpenFilesTest, VfsIntegratedTest;

begin
  VfsTestHelper.InitConsole;
  TGUITestRunner.RunRegisteredTests;
end.

