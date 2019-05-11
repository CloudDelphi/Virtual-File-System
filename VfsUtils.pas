unit VfsUtils;
(*
  
*)


(***)  interface  (***)

uses
  SysUtils, Math, Windows,
  Utils, WinNative, Alg, TypeWrappers,
  Lists, DataLib, StrLib,
  VfsMatching;

type
  (* Import *)
  TDict    = DataLib.TDict;
  TObjDict = DataLib.TObjDict;
  TString  = TypeWrappers.TString;
  TList    = Lists.TList;

const
  MAX_FILENAME_SIZE               = WinNative.MAX_FILENAME_LEN * sizeof(WideChar);
  DRIVE_CHAR_INDEX_IN_NT_ABS_PATH = 5; // \??\D:

type
  TSysOpenFileMode = (OPEN_AS_ANY = 0, OPEN_AS_FILE = WinNative.FILE_NON_DIRECTORY_FILE, OPEN_AS_DIR = WinNative.FILE_DIRECTORY_FILE);

  (* WINNT widest file structre wrapper *)
  PNativeFileInfo = ^TNativeFileInfo;
  TNativeFileInfo = record
    Base:     WinNative.FILE_ID_BOTH_DIR_INFORMATION;
    FileName: WideString;

    procedure SetFileName (const NewFileName: WideString);
    function  CopyFileNameToBuf ({ni} Buf: pbyte; BufSize: integer): boolean;
    function  GetFileSize: Int64;
  end;

  (* TNativeFileInfo wrapper for dynamical data structures with memory manamement *)
  TFileInfo = class
   public
    Data: TNativeFileInfo;

    constructor Create ({n} Data: PNativeFileInfo = nil);
  end;

  (* Universal directory listing holder *)
  TDirListing = class
   private
    {O} fFileList: {O} DataLib.TList {OF TFileInfo};
        fFileInd:  integer;

    function GetCount: integer;

   public
    constructor Create;
    destructor  Destroy; override;

    function  IsEnd: boolean;
    procedure AddItem ({U} FileInfo: PNativeFileInfo; const FileName: WideString = ''; const InsertBefore: integer = High(integer));
    function  GetNextItem ({OUT} var {U} Res: TFileInfo): boolean;
    procedure Rewind;
    procedure Clear;

    (* Always seeks as close as possible *)
    function Seek (SeekInd: integer): boolean;
    function SeekRel (RelInd: integer): boolean;

    function GetDebugDump: string;

    property FileInd: integer read fFileInd;
    property Count:   integer read GetCount;
  end; // .class TDirListing

  ISysDirScanner = interface
    function IterNext ({OUT} var FileName: WideString; {n} FileInfo: WinNative.PFILE_ID_BOTH_DIR_INFORMATION = nil): boolean;
  end;

  TSysDirScanner = class (Utils.TManagedObject, ISysDirScanner)
   protected const
     BUF_SIZE = (sizeof(WinNative.FILE_ID_BOTH_DIR_INFORMATION) + MAX_FILENAME_SIZE) * 10;

   protected
    fOwnsDirHandle: boolean;
    fDirHandle:     Windows.THandle;
    fMask:          WideString;
    fMaskU:         WinNative.UNICODE_STRING;
    fIsStart:       boolean;
    fIsEnd:         boolean;
    fBufPos:        integer;
    fBuf:           array [0..BUF_SIZE - 1] of byte;

   public
    constructor Create (const hDir: Windows.THandle; const Mask: WideString); overload;
    constructor Create (const DirPath, Mask: WideString); overload;
    destructor Destroy; override;
    
    function IterNext ({OUT} var FileName: WideString; {n} FileInfo: WinNative.PFILE_ID_BOTH_DIR_INFORMATION = nil): boolean;
  end; // .class TSysDirScanner


(* Packs lower cased WideString bytes into AnsiString buffer *)
function WideStrToCaselessKey (const Str: WideString): string;

(* The opposite of WideStrToKey *)
function CaselessKeyToWideStr (const CaselessKey: string): WideString;

(* Returns expanded unicode path, preserving trailing delimiter, or original path on error *)
function ExpandPath (const Path: WideString): WideString;

(* Returns path without trailing delimiter (for non-drives). Optionally returns flag, whether path had trailing delim or not.
   The flag is false for drives *)
function NormalizeAbsPath (const Path: WideString; {n} HadTrailingDelim: pboolean = nil): WideString;

(* Returns expanded path without trailing delimiter (for non-drives). Optionally returns flag, whether path had trailing delim or not.
   The flag is false for drives *)
function NormalizePath (const Path: WideString; {n} HadTrailingDelim: pboolean = nil): WideString;

(* Returns absolute normalized path with nt path prefix '\??\' (unless path already begins with '\' character).
   Optionally returns flag, whether path had trailing delim or not. *)
function ToNtAbsPath (const Path: WideString; {n} HadTrailingDelim: pboolean = nil): WideString;

(* Return true if path is valid absolute path to root drive like '\??\X:' with any/zero number of trailing slashes *)
function IsNtRootDriveAbsPath (const Path: WideString): boolean;

(* Adds backslash to path end, unless there is already existing one *)
function AddBackslash (const Path: WideString): WideString;

(* Joins multiple path parts into single path. Backslashes are trimmed from each part and finally empty parts are ignored.
   Each part must be valid path part like '\DirName\\\' or 'C:' *)
function MakePath (const Parts: array of WideString): WideString;

(* Removes optional leading \??\ prefix from path *)
function StripNtAbsPathPrefix (const Path: WideString): WideString;

(* Saves API result in external variable and returns result as is *)
function SaveAndRet (Res: integer; out ResCopy): integer;

(* Opens file/directory using absolute NT path and returns success flag *)
function SysOpenFile (const NtAbsPath: WideString; {OUT} var Res: Windows.THandle; const OpenMode: TSysOpenFileMode = OPEN_AS_ANY; const AccessMode: ACCESS_MASK = GENERIC_READ or SYNCHRONIZE): boolean;

(* Returns TNativeFileInfo record for single file/directory. Short names and files indexes/ids in the result are always empty. *)
function GetFileInfo (const FilePath: WideString; {OUT} var Res: TNativeFileInfo): boolean;

function SysScanDir (const hDir: Windows.THandle; const Mask: WideString): ISysDirScanner; overload;
function SysScanDir (const DirPath, Mask: WideString): ISysDirScanner; overload;

(* Scans specified directory and adds sorted entries to directory listing. Optionally exclude names from Exclude dictionary.
   Excluded items must be preprocessed via WideStringToCaselessKey routine.
   Applies filtering by mask to fix possible invalid native functions behavior, found at least on Win XP when
   tests were run on network drive *)
procedure GetDirectoryListing (const SearchPath, FileMask: WideString; {Un} Exclude: TDict {OF CaselessKey => not NIL}; DirListing: TDirListing);

(***)  implementation  (***)


type
  TDirListingItem = class
    SearchName: WideString;
    Info:       TNativeFileInfo;
  end;


function WideStrToCaselessKey (const Str: WideString): string;
var
  ProcessedPath: WideString;

begin
  result := '';

  if Str <> '' then begin
    ProcessedPath := StrLib.WideLowerCase(Str);
    SetLength(result, Length(ProcessedPath) * sizeof(ProcessedPath[1]) div sizeof(result[1]));
    Utils.CopyMem(Length(result) * sizeof(result[1]), PWideChar(ProcessedPath), PChar(result));
  end;
end;

function CaselessKeyToWideStr (const CaselessKey: string): WideString;
begin
  result := '';

  if CaselessKey <> '' then begin
    SetLength(result, Length(CaselessKey) * sizeof(CaselessKey[1]) div sizeof(result[1]));
    Utils.CopyMem(Length(result) * sizeof(result[1]), pchar(CaselessKey), PWideChar(result));
  end;
end;

function ExpandPath (const Path: WideString): WideString;
var
  BufLen:         integer;
  NumCharsCopied: integer;
  FileNameAddr:   PWideChar;

begin
  result := '';

  if Path <> '' then begin
    BufLen         := 0;
    NumCharsCopied := Windows.GetFullPathNameW(PWideChar(Path), 0, nil, FileNameAddr);

    while NumCharsCopied > BufLen do begin
      BufLen         := NumCharsCopied;
      SetLength(result, BufLen - 1);
      NumCharsCopied := Windows.GetFullPathNameW(PWideChar(Path), BufLen, PWideChar(result), FileNameAddr);
    end;

    if NumCharsCopied <= 0 then begin
      result := Path;
    end else begin
      SetLength(result, NumCharsCopied);
    end;
  end; // .if
end; // .function ExpandPath

function NormalizeAbsPath (const Path: WideString; {n} HadTrailingDelim: pboolean = nil): WideString;
begin
  result := StrLib.ExcludeTrailingBackslashW(Path, HadTrailingDelim);

  if (Length(result) = 2) and (result[1] = ':') then begin
    result := result + '\';

    if HadTrailingDelim <> nil then begin
      HadTrailingDelim^ := false;
    end;
  end;
end;

function NormalizePath (const Path: WideString; {n} HadTrailingDelim: pboolean = nil): WideString;
begin
  result := NormalizeAbsPath(ExpandPath(Path), HadTrailingDelim);
end;

function ToNtAbsPath (const Path: WideString; {n} HadTrailingDelim: pboolean = nil): WideString;
begin
  result := NormalizePath(Path, HadTrailingDelim);

  if (result <> '') and (result[1] <> '\') then begin
    result := '\??\' + result;
  end;
end;

function IsNtRootDriveAbsPath (const Path: WideString): boolean;
const
  MIN_VALID_LEN = Length('\??\X:');

var
  i: integer;

begin
  result := (Length(Path) >= MIN_VALID_LEN) and (Path[1] = '\') and (Path[2] = '?') and (Path[3] = '?') and (Path[4] = '\') and (ord(Path[5]) < 256) and (char(Path[5]) in ['A'..'Z']) and (Path[6] = ':');

  if result then begin
    for i := MIN_VALID_LEN + 1 to Length(Path) do begin
      if Path[i] <> '\' then begin
        result := false;
        exit;
      end;
    end;
  end;
end; // .function IsNtRootDriveAbsPath

function StripNtAbsPathPrefix (const Path: WideString): WideString;
begin
  result := Path;

  if (Length(Path) >= 4) and (Path[1] = '\') and (Path[2] = '?') and (Path[3] = '?') and (Path[4] = '\') then begin
    result := Copy(Path, 4 + 1);
  end;
end;

function AddBackslash (const Path: WideString): WideString;
begin
  if (Path = '') or (Path[Length(Path)] <> '\') then begin
    result := Path + '\';
  end else begin
    result := Path;
  end;
end;

function MakePath (const Parts: array of WideString): WideString;
var
{n} CurrChar: PWideChar;
    Part:     WideString;
    PartLen:  integer;
    ResLen:   integer;
    i:        integer;

begin
  CurrChar := nil;
  // * * * * * //
  ResLen := 0;
  
  // Calculate estimated final string length, assume extra '\' for each non-empty part
  for i := 0 to High(Parts) do begin
    if Parts[i] <> '' then begin
      Inc(ResLen, Length(Parts[i]) + 1);
    end;
  end;

  SetLength(result, ResLen);
  CurrChar := PWideChar(result);

  for i := 0 to High(Parts) do begin
    PartLen := Length(Parts[i]);

    if PartLen > 0 then begin
      Part := StrLib.TrimBackslashesW(Parts[i]);
      
      if Part <> '' then begin
        // Add '\' glue for non-first part
        if i = 0 then begin
          Dec(ResLen);
        end else begin
          CurrChar^ := '\';
          Inc(CurrChar);
        end;
        
        Dec(ResLen, PartLen - Length(Part));
        PartLen := Length(Part);
        
        Utils.CopyMem(PartLen * sizeof(WideChar), PWideChar(Part), CurrChar);
        Inc(CurrChar, PartLen);
      end else begin
        Dec(ResLen, PartLen + 1);
      end;
    end;
  end; // .for

  // Trim garbage at final string end
  SetLength(result, ResLen);
end; // .function MakePath

function SaveAndRet (Res: integer; out ResCopy): integer;
begin
  integer(ResCopy) := Res;
  result           := Res;
end;

procedure TNativeFileInfo.SetFileName (const NewFileName: WideString);
begin
  Self.FileName            := NewFileName;
  Self.Base.FileNameLength := Length(NewFileName) * sizeof(WideChar);
end;

function TNativeFileInfo.CopyFileNameToBuf ({ni} Buf: pbyte; BufSize: integer): boolean;
begin
  {!} Assert(Utils.IsValidBuf(Buf, BufSize));
  result := integer(Self.Base.FileNameLength) <= BufSize;

  if BufSize > 0 then begin
    Utils.CopyMem(Self.Base.FileNameLength, PWideChar(Self.FileName), Buf);
  end;
end;

function TNativeFileInfo.GetFileSize: Int64;
begin
  result := Self.Base.EndOfFile.QuadPart;
end;

constructor TFileInfo.Create ({n} Data: PNativeFileInfo = nil);
begin
  if Data <> nil then begin
    Self.Data := Data^;
  end;
end;

constructor TDirListing.Create;
begin
  Self.fFileList := DataLib.NewList(Utils.OWNS_ITEMS);
  Self.fFileInd  := 0;
end;

destructor TDirListing.Destroy;
begin
  SysUtils.FreeAndNil(Self.fFileList);
end;

procedure TDirListing.AddItem (FileInfo: PNativeFileInfo; const FileName: WideString = ''; const InsertBefore: integer = High(integer));
var
{O} Item: TFileInfo;

begin
  {!} Assert(FileInfo <> nil);
  // * * * * * //
  Item := TFileInfo.Create(FileInfo);

  if FileName <> '' then begin
    Item.Data.SetFileName(FileName);
  end;

  if InsertBefore >= Self.fFileList.Count then begin
    Self.fFileList.Add(Item); Item := nil;
  end else begin
    Self.fFileList.Insert(Item, InsertBefore); Item := nil;
  end;  
  // * * * * * //
  SysUtils.FreeAndNil(Item);
end; // .procedure TDirListing.AddItem

function TDirListing.GetCount: integer;
begin
  result := Self.fFileList.Count;
end;

function TDirListing.IsEnd: boolean;
begin
  result := Self.fFileInd >= Self.fFileList.Count;
end;

function TDirListing.GetNextItem ({OUT} var Res: TFileInfo): boolean;
begin
  result := Self.fFileInd < Self.fFileList.Count;

  if result then begin
    Res := TFileInfo(Self.fFileList[Self.fFileInd]);
    Inc(Self.fFileInd);
  end;
end;

procedure TDirListing.Rewind;
begin
  Self.fFileInd := 0;
end;

procedure TDirListing.Clear;
begin
  Self.fFileList.Clear;
  Self.fFileInd := 0;
end;

function TDirListing.Seek (SeekInd: integer): boolean;
begin
  Self.fFileInd := Alg.ToRange(SeekInd, 0, Self.fFileList.Count - 1);
  result        := Self.fFileInd = SeekInd;
end;

function TDirListing.SeekRel (RelInd: integer): boolean;
begin
  result := Self.Seek(Self.fFileInd + RelInd);    
end;

function TDirListing.GetDebugDump: string;
var
  FileNames: Utils.TArrayOfStr;
  i:         integer;

begin
  SetLength(FileNames, Self.fFileList.Count);

  for i := 0 to Self.fFileList.Count - 1 do begin
    FileNames[i] := TFileInfo(Self.fFileList[i]).Data.FileName;
  end;

  result := StrLib.Join(FileNames, #13#10);
end;

function SysOpenFile (const NtAbsPath: WideString; {OUT} var Res: Windows.THandle; const OpenMode: TSysOpenFileMode = OPEN_AS_ANY; const AccessMode: ACCESS_MASK = GENERIC_READ or SYNCHRONIZE): boolean;
var
  FilePathU:     WinNative.UNICODE_STRING;
  hFile:         Windows.THandle;
  ObjAttrs:      WinNative.OBJECT_ATTRIBUTES;
  IoStatusBlock: WinNative.IO_STATUS_BLOCK;

begin
  FilePathU.AssignExistingStr(NtAbsPath);
  ObjAttrs.Init(@FilePathU);

  result := WinNative.NtOpenFile(@hFile, AccessMode, @ObjAttrs, @IoStatusBlock, FILE_SHARE_READ or FILE_SHARE_WRITE, ord(OpenMode) or FILE_SYNCHRONOUS_IO_NONALERT) = WinNative.STATUS_SUCCESS;

  if result then begin
    Res := hFile;
  end;
end; // .function SysOpenFile

function GetFileInfo (const FilePath: WideString; {OUT} var Res: TNativeFileInfo): boolean;
const
  BUF_SIZE = sizeof(WinNative.FILE_ALL_INFORMATION) + MAX_FILENAME_SIZE;

var
{U} FileAllInfo:   WinNative.PFILE_ALL_INFORMATION;
    NtAbsPath:     WideString;
    hFile:         Windows.THandle;
    Buf:           array [0..BUF_SIZE - 1] of byte;
    IoStatusBlock: WinNative.IO_STATUS_BLOCK;

begin
  FileAllInfo := @Buf;
  // * * * * * //
  NtAbsPath := ToNtAbsPath(FilePath); 
  result    := SysOpenFile(NtAbsPath, hFile, OPEN_AS_ANY);

  if not result then begin
    exit;
  end;

  if IsNtRootDriveAbsPath(NtAbsPath) then begin
    // Return fake info for root drive
    result := SaveAndRet(Windows.GetFileAttributesW(PWideChar(StripNtAbsPathPrefix(NtAbsPath))), FileAllInfo.BasicInformation.FileAttributes) <> integer(Windows.INVALID_HANDLE_VALUE);

    if result then begin
      FillChar(Res.Base, sizeof(Res.Base), 0);
      Res.Base.FileAttributes := FileAllInfo.BasicInformation.FileAttributes;
      Res.SetFileName(NtAbsPath[DRIVE_CHAR_INDEX_IN_NT_ABS_PATH] + WideString(':\'#0));
    end;
  end else begin
    result := WinNative.NtQueryInformationFile(hFile, @IoStatusBlock, FileAllInfo, BUF_SIZE, ord(WinNative.FileAllInformation)) = WinNative.STATUS_SUCCESS;

    if result then begin
      Res.Base.FileIndex       := 0;
      Res.Base.CreationTime    := FileAllInfo.BasicInformation.CreationTime;
      Res.Base.LastAccessTime  := FileAllInfo.BasicInformation.LastAccessTime;
      Res.Base.LastWriteTime   := FileAllInfo.BasicInformation.LastWriteTime;
      Res.Base.ChangeTime      := FileAllInfo.BasicInformation.ChangeTime;
      Res.Base.FileAttributes  := FileAllInfo.BasicInformation.FileAttributes;
      Res.Base.EndOfFile       := FileAllInfo.StandardInformation.EndOfFile;
      Res.Base.AllocationSize  := FileAllInfo.StandardInformation.AllocationSize;
      Res.Base.EaSize          := FileAllInfo.EaInformation.EaSize;
      Res.Base.ShortNameLength := 0;
      Res.Base.ShortName[0]    := #0;
      Res.Base.FileNameLength  := FileAllInfo.NameInformation.FileNameLength;
      Res.Base.FileId.LowPart  := 0;
      Res.Base.FileId.HighPart := 0;

      Res.SetFileName(StrLib.ExtractFileNameW(StrLib.WideStringFromBuf(
        @FileAllInfo.NameInformation.FileName,
        Max(0, Min(integer(IoStatusBlock.Information) - sizeof(FileAllInfo^), FileAllInfo.NameInformation.FileNameLength)) div sizeof(WideChar)
      )));
    end; // .if
  end; // .else

  WinNative.NtClose(hFile);
end; // .function GetFileInfo

constructor TSysDirScanner.Create (const hDir: Windows.THandle; const Mask: WideString);
begin
  Self.fOwnsDirHandle := false;
  Self.fDirHandle     := hDir;
  Self.fMask          := StrLib.WideLowerCase(Mask);
  Self.fMaskU.AssignExistingStr(Self.fMask);
  Self.fIsStart       := true;
  Self.fIsEnd         := false;
  Self.fBufPos        := 0;
end;

constructor TSysDirScanner.Create (const DirPath, Mask: WideString);
var
  hDir: Windows.THandle;

begin
  hDir := Windows.INVALID_HANDLE_VALUE;
  SysOpenFile(ToNtAbsPath(DirPath), hDir, OPEN_AS_DIR);

  Self.Create(hDir, Mask);

  if hDir <> Windows.INVALID_HANDLE_VALUE then begin
    Self.fOwnsDirHandle := true;
  end else begin
    Self.fIsEnd := true;
  end;
end; // .constructor TSysDirScanner.Create

destructor TSysDirScanner.Destroy;
begin
  if Self.fOwnsDirHandle then begin
    WinNative.NtClose(Self.fDirHandle);
  end;
end;

function TSysDirScanner.IterNext ({OUT} var FileName: WideString; {n} FileInfo: WinNative.PFILE_ID_BOTH_DIR_INFORMATION = nil): boolean;
const
  MULTIPLE_ENTRIES = false;

var
{n} FileInfoInBuf: WinNative.PFILE_ID_BOTH_DIR_INFORMATION;
    IoStatusBlock: WinNative.IO_STATUS_BLOCK;
    FileNameLen:   integer;
    Status:        integer;

begin
  FileInfoInBuf := nil;
  // * * * * * //
  result := not Self.fIsEnd and (Self.fDirHandle <> Windows.INVALID_HANDLE_VALUE);

  if not result then begin
    exit;
  end;

  if not Self.fIsStart and (Self.fBufPos < Self.BUF_SIZE) then begin
    FileInfoInBuf := @Self.fBuf[Self.fBufPos];
    FileNameLen   := Min(FileInfoInBuf.FileNameLength, Self.BUF_SIZE - Self.fBufPos) div sizeof(WideChar);
    FileName      := StrLib.WideStringFromBuf(@FileInfoInBuf.FileName, FileNameLen);

    if FileInfo <> nil then begin
      FileInfo^               := FileInfoInBuf^;
      FileInfo.FileNameLength := FileNameLen * sizeof(WideChar);
    end;

    Self.fBufPos := Utils.IfThen(FileInfoInBuf.NextEntryOffset <> 0, Self.fBufPos + integer(FileInfoInBuf.NextEntryOffset), Self.BUF_SIZE);
  end else begin
    Self.fBufPos  := 0;
    Status        := WinNative.NtQueryDirectoryFile(Self.fDirHandle, 0, nil, nil, @IoStatusBlock, @Self.fBuf, Self.BUF_SIZE, ord(WinNative.FileIdBothDirectoryInformation), MULTIPLE_ENTRIES, @Self.fMaskU, Self.fIsStart);
    result        := (Status = WinNative.STATUS_SUCCESS) and (integer(IoStatusBlock.Information) <> 0);
    Self.fIsStart := false;

    if result then begin
      result := Self.IterNext(FileName, FileInfo);
    end else begin
      Self.fIsEnd := true;
    end;
  end; // .else
end; // .function TSysDirScanner.IterNext

function SysScanDir (const hDir: Windows.THandle; const Mask: WideString): ISysDirScanner; overload;
begin
  result := TSysDirScanner.Create(hDir, Mask);
end;

function SysScanDir (const DirPath, Mask: WideString): ISysDirScanner; overload;
begin
  result := TSysDirScanner.Create(DirPath, Mask);
end;

function CompareFileItemsByNameAsc (Item1, Item2: integer): integer;
begin
  result := StrLib.CompareBinStringsW(TDirListingItem(Item1).SearchName, TDirListingItem(Item2).SearchName);

  if result = 0 then begin
    result := StrLib.CompareBinStringsW(TDirListingItem(Item1).Info.FileName, TDirListingItem(Item2).Info.FileName);
  end;
end;

procedure SortDirListing ({U} List: TList {OF TDirListingItem});
begin
  List.CustomSort(CompareFileItemsByNameAsc);
end;

procedure GetDirectoryListing (const SearchPath, FileMask: WideString; {Un} Exclude: TDict {OF CaselessKey => not NIL}; DirListing: TDirListing);
var
{O} Items:        {O} TList {OF TDirListingItem};
{O} Item:         {O} TDirListingItem;
    CompiledMask: Utils.TArrayOfByte;
    i:            integer;

begin
  {!} Assert(DirListing <> nil);
  Items        := DataLib.NewList(Utils.OWNS_ITEMS);
  Item         := TDirListingItem.Create;
  CompiledMask := VfsMatching.CompilePattern(FileMask);
  // * * * * * //
  with VfsUtils.SysScanDir(SearchPath, FileMask) do begin
    while IterNext(Item.Info.FileName, @Item.Info.Base) do begin     
      if VfsMatching.MatchPattern(Item.Info.FileName, pointer(CompiledMask)) and ((Exclude = nil) or (Exclude[WideStrToCaselessKey(Item.Info.FileName)] = nil)) then begin
        Item.SearchName := StrLib.WideLowerCase(Item.Info.FileName);
        Items.Add(Item); Item := nil;
        Item := TDirListingItem.Create;
      end;
    end;
  end;

  SortDirListing(Items);

  for i := 0 to Items.Count - 1 do begin
    DirListing.AddItem(@TDirListingItem(Items[i]).Info);
  end;
  // * * * * * //
  SysUtils.FreeAndNil(Items);
  SysUtils.FreeAndNil(Item);
end; // .procedure GetDirectoryListing

end.