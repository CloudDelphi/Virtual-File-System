# VFS (Virtual File System)
Add Virtual File System support to your project. Implement Mods directory support in 2 lines of code.
Virtually copies contents of any directory into any directory. Copied contents is available in read-only mode.

## Example:
```delphi
VfsImport.MapModsFromListA('D:\Game', 'D:\Game\Mods', 'D:\Game\Mods\list.txt');
VfsImport.RunVfs(VfsImport.SORT_FIFO);
```
