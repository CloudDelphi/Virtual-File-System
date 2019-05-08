program VfsTest;

uses
  TestFramework, GuiTestRunner,
  VfsUtils, VfsBase, VfsDebug,
  VfsApiDigger, VfsExport, VfsOpenFiles,
  VfsHooks, VfsControl, VfsMatching,
  VfsTestHelper, VfsMatchingTest,
  VfsDebugTest, VfsUtilsTest, VfsBaseTest,
  VfsApiDiggerTest, VfsOpenFilesTest, VfsIntegratedTest;

begin
  System.IsMultiThread := true;
  VfsTestHelper.InitConsole;
  TGUITestRunner.RunRegisteredTests;
end.
