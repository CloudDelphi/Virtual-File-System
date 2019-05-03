unit VfsBase;
(*
  Description: Implements in-memory virtual file system data storage.
  Author:      Alexander Shostak (aka Berserker aka EtherniDee aka BerSoft)
  TODO:        Use optimized hash-table storage for VfsItems instead of ansi-to-wide string keys in regular binary tree.
*)


(***)  interface  (***)

uses
  SysUtils, Math, Windows,
  Utils, WinNative, Alg, Concur, TypeWrappers, Lists, DataLib,
  StrLib,
  VfsUtils;

type
  (* Import *)
  TDict    = DataLib.TDict;
  TObjDict = DataLib.TObjDict;
  TString  = TypeWrappers.TString;
  TList    = Lists.TList;

const
  OVERWRITE_EXISTING      = true;
  DONT_OVERWRITE_EXISTING = false;

  AUTO_PRIORITY                = MAXLONGINT div 2;
  INITIAL_OVERWRITING_PRIORITY = AUTO_PRIORITY + 1;
  INITIAL_ADDING_PRIORITY      = AUTO_PRIORITY - 1;

type
  (*
    Specifies the order, in which files from different mapped directories will be listed in virtual directory.
    Virtual directory sorting is performed by priorities firstly and lexicographically secondly.
    SORT_FIFO - Items of the first mapped directory will be listed before the second mapped directory items.
    SORT_LIFO - Items of The last mapped directory will be listed before all other mapped directory items.
  *)
  TDirListingSortType = (SORT_FIFO = 0, SORT_LIFO = 1);

  (* Single redirected VFS entry: file or directory *)
  TVfsItem = class
   private
    function  GetName: WideString; inline;
    procedure SetName (const NewName: WideString); inline;

   public
    (* Name in lower case, used for wildcard mask matching *)
    SearchName: WideString;

    (* Absolute path to real file/folder location without trailing slash for non-drives *)
    RealPath: WideString;

    (* The priority used in virtual directories sorting for listing *)
    Priority: integer;

    (* List of directory child items or nil *)
    {On} Children: {U} TList {OF TVfsItem};

    (* Up to 32 special non-Windows attribute flags *)
    Attrs: integer;

    (* Full file info *)
    Info: TNativeFileInfo;

    function IsDir (): boolean;

    destructor Destroy; override;

    (* Name in original case. Automatically sets/converts SearchName, Info.FileName, Info.Base.FileNameLength *)
    property Name: WideString read GetName write SetName;
  end; // .class TVfsItem

  (* Allows to disable VFS temporarily for current thread only *)
  TThreadVfsDisabler = record
    PrevDisableVfsForThisThread: boolean;

    procedure DisableVfsForThread;
    procedure RestoreVfsForThread;
  end;

  TSingleArgExternalFunc = function (Arg: pointer = nil): integer; stdcall;

var
  (* Global VFS access synchronizer *)
  VfsCritSection: Concur.TCritSection;


function GetThreadVfsDisabler: TThreadVfsDisabler;

(* Runs VFS. Higher level API must install hooks in VfsCritSection protected area.
   Listing order is ignored if VFS is resumed from pause *)
function RunVfs (DirListingOrder: TDirListingSortType): boolean;

(* Temporarily pauses VFS, but does not reset existing mappings *)
function PauseVfs: boolean;

(* Stops VFS and clears all mappings *)
function ResetVfs: boolean;

(* Returns real path for VFS item by its absolute virtual path or empty string. Optionally returns file info structure *)
function GetVfsItemRealPath (const AbsVirtPath: WideString; {n} FileInfo: PNativeFileInfo = nil): WideString;

(* Returns virtual directory info. Adds virtual entries to specified directory listing container *)
function GetVfsDirInfo (const AbsVirtPath, Mask: WideString; {OUT} var DirInfo: TNativeFileInfo; DirListing: TDirListing): boolean;

(* Maps real directory contents to virtual path. Target must exist for success *)
function MapDir (const VirtPath, RealPath: WideString; OverwriteExisting: boolean; Flags: integer = 0): boolean;

(* Calls specified function with a single argument and returns its result. VFS is disabled for current thread during function exection *)
function CallWithoutVfs (Func: TSingleArgExternalFunc; Arg: pointer = nil): integer; stdcall;


(***)  implementation  (***)


var
(*
  Global map of case-insensitive normalized path to file/directory => corresponding TVfsItem.
  Access is controlled via critical section and global/thread switchers.
  Represents the whole cached virtual file system contents.
*)
{O} VfsItems: {O} TDict {OF TVfsItem};
  
  (* Global VFS state indicator. If false, all VFS search operations must fail *)
  VfsIsRunning: boolean = false;

  (* If true, VFS file/directory hierarchy is built and no mapping is allowed untill full reset *)
  VfsTreeIsBuilt: boolean = false;
    
  (* Automatical VFS items priority management *)
  OverwritingPriority: integer = INITIAL_OVERWRITING_PRIORITY;
  AddingPriority:      integer = INITIAL_ADDING_PRIORITY;

// All threadvar variables are automatically zeroed during finalization, thus zero must be the safest default value
threadvar
  DisableVfsForThisThread: boolean;

function TVfsItem.IsDir: boolean;
begin
  result := (Self.Info.Base.FileAttributes and Windows.FILE_ATTRIBUTE_DIRECTORY) <> 0;
end;

function TVfsItem.GetName: WideString;
begin
  result := Self.Info.FileName;
end;

procedure TVfsItem.SetName (const NewName: WideString);
begin
  Self.Info.SetFileName(NewName);
  Self.SearchName := StrLib.WideLowerCase(NewName);
end;

destructor TVfsItem.Destroy;
begin
  SysUtils.FreeAndNil(Self.Children);
end;

procedure TThreadVfsDisabler.DisableVfsForThread;
begin
  Self.PrevDisableVfsForThisThread := DisableVfsForThisThread;
  DisableVfsForThisThread          := true;
end;

procedure TThreadVfsDisabler.RestoreVfsForThread;
begin
  DisableVfsForThisThread := Self.PrevDisableVfsForThisThread;
end;

function GetThreadVfsDisabler: TThreadVfsDisabler;
begin
end;

function EnterVfs: boolean;
begin
  result := not DisableVfsForThisThread;

  if result then begin
    VfsCritSection.Enter;
    result := VfsIsRunning;

    if not result then begin
      VfsCritSection.Leave;
    end;
  end;
end;

procedure LeaveVfs;
begin
  VfsCritSection.Leave;
end;

function CompareVfsItemsByPriorityDescAndNameAsc (Item1, Item2: integer): integer;
begin
  result := TVfsItem(Item2).Priority - TVfsItem(Item1).Priority;

  if result = 0 then begin
    result := StrLib.CompareBinStringsW(TVfsItem(Item1).SearchName, TVfsItem(Item2).SearchName);
  end;
end;

function CompareVfsItemsByPriorityAscAndNameAsc (Item1, Item2: integer): integer;
begin
  result := TVfsItem(Item1).Priority - TVfsItem(Item2).Priority;

  if result = 0 then begin
    result := StrLib.CompareBinStringsW(TVfsItem(Item1).SearchName, TVfsItem(Item2).SearchName);
  end;
end;

procedure SortVfsListing ({U} List: DataLib.TList {OF TVfsItem}; SortType: TDirListingSortType);
begin
  if SortType = SORT_FIFO then begin
    List.CustomSort(CompareVfsItemsByPriorityDescAndNameAsc);
  end else begin
    List.CustomSort(CompareVfsItemsByPriorityAscAndNameAsc);
  end;
end;

procedure SortVfsDirListings (SortType: TDirListingSortType);
var
{Un} Children: DataLib.TList {OF TVfsItem};

begin
  Children := nil;
  // * * * * * //
  with DataLib.IterateDict(VfsItems) do begin
    while IterNext() do begin
      Children := TVfsItem(IterValue).Children;

      if (Children <> nil) and (Children.Count > 1) then begin
        SortVfsListing(Children, SortType);
      end;
    end;
  end;
end; // .procedure SortVfsDirListings

function FindVfsItemByNormalizedPath (const Path: WideString; {U} var {OUT} Res: TVfsItem): boolean;
var
{Un} VfsItem: TVfsItem;

begin
  VfsItem := VfsItems[WideStrToCaselessKey(Path)];
  result  := VfsItem <> nil;

  if result then begin
    Res := VfsItem;
  end;
end;

function FindVfsItemByPath (const Path: WideString; {U} var {OUT} Res: TVfsItem): boolean;
begin
  result := FindVfsItemByNormalizedPath(NormalizePath(Path), Res);
end;

(* All children list of VFS items MUST be empty *)
procedure BuildVfsItemsTree;
var
{Un} DirVfsItem: TVfsItem;
     AbsDirPath: WideString;

begin
  DirVfsItem := nil;
  // * * * * * //
  with DataLib.IterateDict(VfsItems) do begin
    while IterNext() do begin
      AbsDirPath := StrLib.ExtractDirPathW(CaselessKeyToWideStr(IterKey));

      if FindVfsItemByNormalizedPath(AbsDirPath, DirVfsItem) then begin
        DirVfsItem.Children.Add(IterValue);
      end;
    end;
  end;
end; // .procedure BuildVfsItemsTree

function RunVfs (DirListingOrder: TDirListingSortType): boolean;
begin
  result := not DisableVfsForThisThread;

  if result then begin
    with VfsCritSection do begin
      Enter;

      if not VfsIsRunning then begin
        if not VfsTreeIsBuilt then begin
          BuildVfsItemsTree();
          SortVfsDirListings(DirListingOrder);
          VfsTreeIsBuilt := true;
        end;
        
        VfsIsRunning := true;
      end;

      Leave;
    end; // .with
  end; // .if
end; // .function RunVfs

function PauseVfs: boolean;
begin
  result := not DisableVfsForThisThread;

  if result then begin
    with VfsCritSection do begin
      Enter;
      VfsIsRunning := false;
      Leave;
    end;
  end;
end;

function ResetVfs: boolean;
begin
  result := not DisableVfsForThisThread;

  if result then begin
    with VfsCritSection do begin
      Enter;
      VfsItems.Clear();
      VfsIsRunning   := false;
      VfsTreeIsBuilt := false;
      Leave;
    end;
  end;
end;

(* Returns real path for vfs item by its absolute virtual path or empty string. Optionally returns file info structure *)
function GetVfsItemRealPath (const AbsVirtPath: WideString; {n} FileInfo: PNativeFileInfo = nil): WideString;
var
{n} VfsItem: TVfsItem;

begin
  VfsItem := nil;
  result  := '';
  // * * * * * //
  if EnterVfs then begin
    if FindVfsItemByNormalizedPath(AbsVirtPath, VfsItem) then begin
      result := VfsItem.RealPath;

      if FileInfo <> nil then begin
        FileInfo^ := VfsItem.Info;
      end;
    end;

    LeaveVfs;
  end; // .if
end; // .function GetVfsItemRealPath

function GetVfsDirInfo (const AbsVirtPath, Mask: WideString; {OUT} var DirInfo: TNativeFileInfo; DirListing: TDirListing): boolean;
var
{n} VfsItem:        TVfsItem;
    NormalizedMask: WideString;
    i:              integer;

begin
  {!} Assert(DirListing <> nil);
  VfsItem := nil;
  // * * * * * //
  result := EnterVfs;

  if result then begin
    result := FindVfsItemByNormalizedPath(AbsVirtPath, VfsItem) and VfsItem.IsDir;

    if result then begin
      DirInfo := VfsItem.Info;

      if VfsItem.Children <> nil then begin
        NormalizedMask := StrLib.WideLowerCase(Mask);

        for i := 0 to VfsItem.Children.Count - 1 do begin
          if StrLib.MatchW(TVfsItem(VfsItem.Children[i]).SearchName, NormalizedMask) then begin
            DirListing.AddItem(@TVfsItem(VfsItem.Children[i]).Info);
          end;
        end;
      end; // .if
    end; // .if

    LeaveVfs;
  end; // .if
end; // .function GetVfsDirInfo

procedure CopyFileInfoWithoutNames (var Src, Dest: WinNative.FILE_ID_BOTH_DIR_INFORMATION);
begin
  Dest.FileIndex      := 0;
  Dest.CreationTime   := Src.CreationTime;
  Dest.LastAccessTime := Src.LastAccessTime;
  Dest.LastWriteTime  := Src.LastWriteTime;
  Dest.ChangeTime     := Src.ChangeTime;
  Dest.EndOfFile      := Src.EndOfFile;
  Dest.AllocationSize := Src.AllocationSize;
  Dest.FileAttributes := Src.FileAttributes;
  Dest.EaSize         := Src.EaSize;
end;

(* Redirects single file/directory path (not including directory contents). Target must exist for success *)
function RedirectFile (const AbsVirtPath, AbsRealPath: WideString; {n} FileInfoPtr: WinNative.PFILE_ID_BOTH_DIR_INFORMATION; OverwriteExisting: boolean; Priority: integer): {Un} TVfsItem;
const
  WIDE_NULL_CHAR_LEN = Length(#0);

var
{Un} VfsItem:        TVfsItem;
     PackedVirtPath: string;
     IsNewItem:      boolean;
     FileInfo:       TNativeFileInfo;
     Success:        boolean;

begin
  VfsItem := nil;
  result  := nil;
  // * * * * * //
  PackedVirtPath := WideStrToCaselessKey(AbsVirtPath);
  VfsItem        := VfsItems[PackedVirtPath];
  IsNewItem      := VfsItem = nil;
  Success        := true;

  if IsNewItem or OverwriteExisting then begin
    if FileInfoPtr = nil then begin
      Success := GetFileInfo(AbsRealPath, FileInfo);
    end;

    if Success then begin
      if IsNewItem then begin
        VfsItem                           := TVfsItem.Create();
        VfsItems[PackedVirtPath]          := VfsItem;
        VfsItem.Name                      := StrLib.ExtractFileNameW(AbsVirtPath);
        VfsItem.SearchName                := StrLib.WideLowerCase(VfsItem.Name);
        VfsItem.Info.Base.ShortNameLength := 0;
        VfsItem.Info.Base.ShortName[0]    := #0;
      end;

      if FileInfoPtr <> nil then begin
        CopyFileInfoWithoutNames(FileInfoPtr^, VfsItem.Info.Base);
      end else begin
        CopyFileInfoWithoutNames(FileInfo.Base, VfsItem.Info.Base);
      end;
 
      VfsItem.RealPath := AbsRealPath;
      VfsItem.Priority := Priority;
      VfsItem.Attrs    := 0;
    end; // .if
  end; // .if

  if Success then begin
    result := VfsItem;
  end;
end; // .function RedirectFile

function _MapDir (const AbsVirtPath, AbsRealPath: WideString; {n} FileInfoPtr: WinNative.PFILE_ID_BOTH_DIR_INFORMATION; OverwriteExisting: boolean; Priority: integer): {Un} TVfsItem;
var
{O}  Subdirs:        {O} TList {OF TFileInfo};
{U}  SubdirInfo:     TFileInfo;
{Un} DirVfsItem:     TVfsItem;
     Success:        boolean;
     FileInfo:       TNativeFileInfo;
     VirtPathPrefix: WideString;
     RealPathPrefix: WideString;
     i:              integer;

begin
  DirVfsItem := nil;
  Subdirs    := DataLib.NewList(Utils.OWNS_ITEMS);
  SubdirInfo := nil;
  result     := nil;
  // * * * * * //
  if Priority = AUTO_PRIORITY then begin
    if OverwriteExisting then begin
      Priority := OverwritingPriority;
      Inc(OverwritingPriority);
    end else begin
      Priority := AddingPriority;
      Dec(AddingPriority);
    end;
  end;
  
  DirVfsItem := RedirectFile(AbsVirtPath, AbsRealPath, FileInfoPtr, OverwriteExisting, Priority);
  Success    := DirVfsItem <> nil;

  if Success then begin
    VirtPathPrefix := AbsVirtPath + '\';
    RealPathPrefix := AbsRealPath + '\';

    if DirVfsItem.Children = nil then begin
      DirVfsItem.Children := DataLib.NewList(not Utils.OWNS_ITEMS);
    end;

    with SysScanDir(AbsRealPath, '*') do begin
      while IterNext(FileInfo.FileName, @FileInfo.Base) do begin
        if Utils.HasFlag(FileInfo.Base.FileAttributes, Windows.FILE_ATTRIBUTE_DIRECTORY) then begin         
          if (FileInfo.FileName <> '.') and (FileInfo.FileName <> '..') then begin
            Subdirs.Add(TFileInfo.Create(@FileInfo));
          end;
        end else begin
          RedirectFile(VirtPathPrefix + FileInfo.FileName, RealPathPrefix + FileInfo.FileName, @FileInfo, OverwriteExisting, Priority);
        end;
      end;
    end;

    for i := 0 to Subdirs.Count - 1 do begin
      SubdirInfo := TFileInfo(Subdirs[i]);
      _MapDir(VirtPathPrefix + SubdirInfo.Data.FileName, RealPathPrefix + SubdirInfo.Data.FileName, @SubdirInfo.Data, OverwriteExisting, Priority);
    end;
  end; // .if

  if Success then begin
    result := DirVfsItem;
  end;
  // * * * * * //
  SysUtils.FreeAndNil(Subdirs);
end; // .function _MapDir

function MapDir (const VirtPath, RealPath: WideString; OverwriteExisting: boolean; Flags: integer = 0): boolean;
begin
  with VfsCritSection do begin
    Enter;
    
    result := not VfsIsRunning and not VfsTreeIsBuilt;

    if result then begin
      result := _MapDir(NormalizePath(VirtPath), NormalizePath(RealPath), nil, OverwriteExisting, AUTO_PRIORITY) <> nil;
    end;
    
    Leave;
  end;
end;

function CallWithoutVfs (Func: TSingleArgExternalFunc; Arg: pointer = nil): integer; stdcall;
begin
  with GetThreadVfsDisabler do begin
    try
      DisableVfsForThread;
      result := Func(Arg);
    except
      on E: Exception do begin
        RestoreVfsForThread;
        raise E;
      end;
    end; // .try

    RestoreVfsForThread;
  end; // .with  
end; // .function CallWithoutVfs

begin
  VfsCritSection.Init;
  VfsItems := DataLib.NewDict(Utils.OWNS_ITEMS, DataLib.CASE_SENSITIVE);
end.