unit VfsOpenFiles;
(*
  Author:      Alexander Shostak aka Berserker aka EtherniDee.
  Description: Provides concurrent storage for additional information for each file handle,
               fully integrated to file handles life cycle.
               The unit works independently of other VFS subsystems, guaranteeing relative paths
               resolution capability (conversion of directory handle into directory path).
               Most NT file APIs can work with pairs of [hDir, RelativePath] (@see WinNative.TObjectAttributes).
*)


(***)  interface  (***)

uses
  Windows, SysUtils,
  Utils, Concur, DataLib, StrLib,
  VfsUtils, VfsBase, VfsMatching;
type
  (* Import *)
  TVfsItem = VfsBase.TVfsItem;

type
  (* Extra information for file handle. Working with structure must be protected by corresponding critical section *)
  TOpenedFile = class
   public
    (* Handle for either virtual or real path *)
    hFile: Windows.THandle;

    (* Virtual path to file (path given to NtCreate API) *)
    AbsPath: WideString;

    (* Directory listing (both real and virtual children). Created on the fly on FillDirListing call *)
    {On} DirListing: VfsUtils.TDirListing;

    constructor Create (hFile: Windows.THandle; const AbsPath: WideString);
    destructor Destroy; override;

    (* Makes complete directory listing, including real and virtual items. Does nothing if listing already exists *)
    procedure FillDirListing (const Mask: WideString);
  end; // .class TOpenedFile

var
  OpenFilesCritSection: Concur.TCritSection;


(* Returns TOpenedFile by handle or nil. MUST BE called in OpenFilesCritSection protected area *)
function GetOpenedFile (hFile: Windows.THandle): {n} TOpenedFile;

(* Returns absolute virtual/real path to opened file by its handle in a thread-safe way. Empty string on failure. The result path is the one, passed to open file API *)
function GetOpenedFilePath (hFile: Windows.THandle): WideString;

(* Atomically replaces TOpenedFile record for given file handle *)
procedure SetOpenedFileInfo (hFile: Windows.THandle; {On} OpenedFile: TOpenedFile);

(* Atomically deletes TOpenedFile information by file handle *)
procedure DeleteOpenedFileInfo (hFile: Windows.THandle);


(***)  implementation  (***)


var
(* Map of all tracked file handles => TOpenedFile. Protected by corresponding critical section *)
{O} OpenedFiles: {O} TObjDict {of TOpenedFile};


constructor TOpenedFile.Create (hFile: Windows.THandle; const AbsPath: WideString);
begin
  Self.hFile   := hFile;
  Self.AbsPath := AbsPath;
end;

destructor TOpenedFile.Destroy;
begin
  FreeAndNil(Self.DirListing);
end;

procedure TOpenedFile.FillDirListing (const Mask: WideString);
var
{On} ExcludedItems:  {U} TDict {OF not nil};
     VfsItemFound:   boolean;
     NumVfsChildren: integer;
     DirInfo:        TNativeFileInfo;
     ParentDirInfo:  TNativeFileInfo;
     DirItem:        TFileInfo;

begin
  ExcludedItems := nil;
  // * * * * * //
  if Self.DirListing <> nil then begin
    exit;
  end;

  Self.DirListing := TDirListing.Create;
  VfsItemFound    := VfsBase.GetVfsDirInfo(Self.AbsPath, Mask, DirInfo, Self.DirListing);
  ExcludedItems   := DataLib.NewDict(not Utils.OWNS_ITEMS, DataLib.CASE_SENSITIVE);

  if VfsItemFound then begin
    while Self.DirListing.GetNextItem(DirItem) do begin
      ExcludedItems[WideStrToCaselessKey(DirItem.Data.FileName)] := Ptr(1);
    end;

    Self.DirListing.Rewind;
  end;

  // Add real items
  NumVfsChildren := Self.DirListing.Count;

  with VfsBase.GetThreadVfsDisabler do begin
    DisableVfsForThread;

    try
      VfsUtils.GetDirectoryListing(Self.AbsPath, Mask, ExcludedItems, Self.DirListing);
    finally
      RestoreVfsForThread;
    end;
  end;

  // No real items added, maybe there is a need to add '.' and/or '..' manually
  if VfsItemFound and (Self.DirListing.Count = NumVfsChildren) then begin
    if VfsMatching.MatchPattern('.', Mask) then begin
      Self.DirListing.AddItem(@DirInfo, '.');
    end;

    if VfsMatching.MatchPattern('..', Mask) and VfsUtils.GetFileInfo(VfsUtils.AddBackslash(Self.AbsPath) + '..', ParentDirInfo) then begin
      Self.DirListing.AddItem(@ParentDirInfo, '..');
    end;
  end;
  // * * * * * //
  SysUtils.FreeAndNil(ExcludedItems);
end; // .procedure TOpenedFile.FillDirListing

function GetOpenedFile (hFile: Windows.THandle): {n} TOpenedFile;
begin
  result := OpenedFiles[pointer(hFile)];
end;

function GetOpenedFilePath (hFile: Windows.THandle): WideString;
var
{n} OpenedFile: TOpenedFile;

begin
  OpenedFile := nil;
  result     := '';
  // * * * * * //
  with OpenFilesCritSection do begin
    Enter;

    OpenedFile := OpenedFiles[pointer(hFile)];

    if OpenedFile <> nil then begin
      result := OpenedFile.AbsPath;
    end;

    Leave;
  end;
end; // .function GetOpenedFilePath

procedure SetOpenedFileInfo (hFile: Windows.THandle; {On} OpenedFile: TOpenedFile);
begin
  with OpenFilesCritSection do begin
    Enter;
    OpenedFiles[pointer(hFile)] := OpenedFile; OpenedFile := nil;
    Leave;
  end;
  // * * * * * //
  SysUtils.FreeAndNil(OpenedFile);
end;

procedure DeleteOpenedFileInfo (hFile: Windows.THandle);
begin
  with OpenFilesCritSection do begin
    Enter;
    OpenedFiles.DeleteItem(pointer(hFile));
    Leave;
  end;
end;

begin
  OpenFilesCritSection.Init;
  OpenedFiles := DataLib.NewObjDict(Utils.OWNS_ITEMS);
end.