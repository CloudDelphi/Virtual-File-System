unit VfsWatching;
(*
  Description: Provides means to watch for mapped directories changes and refresh VFS.
               Works unreliably when trying to watch the whole logical drive.
*)


(***)  interface  (***)

uses
  Windows, SysUtils, Math,
  Utils, Concur, WinUtils, StrLib, WinNative,
  VfsBase, VfsUtils;


(* Spawns separate thread, which starts recursive monitoring for changes in specified directory.
   VFS will be fully refreshed or smartly updated on any change. Debounce interval specifies
   time in msec to wait after last change before running full VFS rescanning routine *)
function RunWatcher (const WatchDir: WideString; DebounceInterval: integer): boolean;


(***)  implementation  (***)


type
  (* Import *)
  THandle = Windows.THandle;

const
  (* Import *)
  INVALID_HANDLE_VALUE = Windows.INVALID_HANDLE_VALUE;
  
  STOP_EVENT_HANDLE_IND     = 0;
  NOTIFICATION_HANDLE_INDEX = 1;
  NUM_WATCHED_HANDLES       = 2;

type 
  TDirChangeAction = (NOTIFY_FILE_ADDED, NOTIFY_FILE_REMOVED, NOTIFY_FILE_MODIFIED, NOTIFY_FILE_RENAMED_FROM_NAME, NOTIFY_FILE_RENAMED_TO_NAME,
                      NOTIFY_STOP_EVENT, NOTIFY_TIMEOUT, NOTIFY_TOO_MANY_CHANGES, NOTIFY_UNKNOWN_ACTION);

const
  NOTIFY_ESSENTIAL = FILE_NOTIFY_CHANGE_FILE_NAME or FILE_NOTIFY_CHANGE_DIR_NAME or FILE_NOTIFY_CHANGE_ATTRIBUTES or FILE_NOTIFY_CHANGE_SIZE or FILE_NOTIFY_CHANGE_CREATION;
  NO_STOP_EVENT    = 0;
  INFINITE         = Windows.INFINITE;

type
  (* Directory change record *)
  TDirChange = record
    Action: TDirChangeAction;

    (* Absolute expanded and normalized path to file, that triggered notification *)
    FilePath: WideString;
  end;

  IDirChangesIterator = interface
    function IterNext ({out} var DirChange: TDirChange; StopEvent: THandle = 0; Timeout: integer = integer(Windows.INFINITE); NotifyFilter: cardinal = NOTIFY_ESSENTIAL): boolean;
  end;

  TDirChangesIterator = class (Utils.TManagedObject, IDirChangesIterator)
   protected const
     BUF_SIZE = 65500;

   protected
   {O} fDirHandle:   THandle;
   {O} fNotifyEvent: THandle;
       fDirPath:     WideString;
       fBuf:         array [0..BUF_SIZE - 1] of byte;
       fBufSize:     integer;
       fBufPos:      integer;
       fIsEnd:       boolean;

   public
    constructor Create (const DirPath: WideString); overload;
    destructor Destroy; override;
    
    function IterNext ({out} var DirChange: TDirChange; StopEvent: THandle = 0; Timeout: integer = integer(Windows.INFINITE); NotifyFilter: cardinal = NOTIFY_ESSENTIAL): boolean;
  end; // .class TDirChangesIterator

var
  WatcherCritSection:        Concur.TCritSection;
  AbsWatcherDir:             WideString;
  WatcherDebounceInterval:   integer;
  WatcherStopEvent:          THandle = 0;
  WatcherIsRunning:          boolean = false;
  WatcherThreadHandle:       THandle;
  WatcherThreadId:           cardinal;


function IsValidHandle (Handle: THandle): boolean; inline;
begin
  result := (Handle <> 0) and (Handle <> INVALID_HANDLE_VALUE);
end;

constructor TDirChangesIterator.Create (const DirPath: WideString);
const
  MANUAL_RESET_EVENT = true;

begin
  Self.fDirPath   := VfsUtils.NormalizePath(DirPath);
  Self.fDirHandle := Windows.CreateFileW(PWideChar(Self.fDirPath), Windows.GENERIC_READ, Windows.FILE_SHARE_READ or Windows.FILE_SHARE_WRITE, nil,
                                         Windows.OPEN_EXISTING, Windows.FILE_FLAG_BACKUP_SEMANTICS or Windows.FILE_FLAG_OVERLAPPED, 0);

  if IsValidHandle(Self.fDirHandle) then begin
    Self.fNotifyEvent := Windows.CreateEventW(nil, MANUAL_RESET_EVENT, false, nil);

    if not IsValidHandle(Self.fNotifyEvent) then begin
      Windows.CloseHandle(Self.fDirHandle);
      Self.fDirHandle := 0;
    end;
  end;

  Self.fIsEnd := not IsValidHandle(Self.fDirHandle);
end; // .constructor TDirChangesIterator.Create

destructor TDirChangesIterator.Destroy;
begin
  if IsValidHandle(Self.fDirHandle) then begin
    Windows.CloseHandle(Self.fDirHandle);
  end;

  if IsValidHandle(Self.fNotifyEvent) then begin
    Windows.CloseHandle(Self.fNotifyEvent);
  end;
end;

function DecodeNativeDirChangeAction (Action: integer): TDirChangeAction;
begin
  case Action of
    Windows.FILE_ACTION_ADDED:            result := NOTIFY_FILE_ADDED;
    Windows.FILE_ACTION_REMOVED:          result := NOTIFY_FILE_REMOVED;
    Windows.FILE_ACTION_MODIFIED:         result := NOTIFY_FILE_MODIFIED;
    Windows.FILE_ACTION_RENAMED_OLD_NAME: result := NOTIFY_FILE_RENAMED_FROM_NAME;
    Windows.FILE_ACTION_RENAMED_NEW_NAME: result := NOTIFY_FILE_RENAMED_TO_NAME;
  else
    result := NOTIFY_UNKNOWN_ACTION;
  end;
end;

function TDirChangesIterator.IterNext ({out} var DirChange: TDirChange; StopEvent: THandle = 0; Timeout: integer = integer(Windows.INFINITE); NotifyFilter: cardinal = NOTIFY_ESSENTIAL): boolean;
const
  WATCH_SUBTREE   = true;
  WAIT_OVERLAPPED = true;


var
{n} NotifInfoInBuf: WinNative.PFILE_NOTIFY_INFORMATION;
    AsyncRes:       Windows.TOverlapped;
    TriggeredEvent: THandle;
    Dummy:          integer;

begin
  NotifInfoInBuf := nil;
  // * * * * * //
  result := not Self.fIsEnd;

  if not result then begin
    exit;
  end;

  if Timeout = 0 then begin
    DirChange.Action := NOTIFY_TIMEOUT;
    exit;
  end;

  if Self.fBufPos < fBufSize then begin
    NotifInfoInBuf   := @Self.fBuf[Self.fBufPos];
    DirChange.Action := DecodeNativeDirChangeAction(NotifInfoInBuf.Action);

    if DirChange.Action = NOTIFY_FILE_REMOVED then begin
      DirChange.FilePath := VfsUtils.AddBackslash(Self.fDirPath) + NotifInfoInBuf.GetFileName;
      DirChange.FilePath := VfsUtils.AddBackslash(WinUtils.GetLongPathW(StrLib.ExtractDirPathW(DirChange.FilePath))) + StrLib.ExtractFileNameW(DirChange.FilePath);
    end else begin
      DirChange.FilePath := WinUtils.GetLongPathW(VfsUtils.AddBackslash(Self.fDirPath) + NotifInfoInBuf.GetFileName);
    end;

    Self.fBufPos := Utils.IfThen(NotifInfoInBuf.NextEntryOffset <> 0, Self.fBufPos + integer(NotifInfoInBuf.NextEntryOffset), Self.BUF_SIZE);
  end else begin
    FillChar(AsyncRes, sizeof(AsyncRes), 0);
    AsyncRes.hEvent := Self.fNotifyEvent;
    Windows.ResetEvent(Self.fNotifyEvent);
    
    Self.fBufSize := 0;
    Self.fBufPos  := 0;
    result        := Windows.ReadDirectoryChangesW(Self.fDirHandle, @Self.fBuf, sizeof(Self.fBuf), WATCH_SUBTREE, NotifyFilter, @Dummy, @AsyncRes, nil);

    if result then begin
      DirChange.FilePath := '';

      case WinUtils.WaitForObjects([StopEvent, Self.fNotifyEvent], TriggeredEvent, Timeout) of
        WinUtils.WR_WAITED: begin
          if TriggeredEvent = StopEvent then begin
            DirChange.Action := NOTIFY_STOP_EVENT;
          end else begin
            result := Windows.GetOverlappedResult(Self.fNotifyEvent, AsyncRes, cardinal(Self.fBufSize), not WAIT_OVERLAPPED);

            if result then begin
              if Self.fBufSize = 0 then begin
                DirChange.Action := NOTIFY_TOO_MANY_CHANGES;
              end else if Self.fBufSize < sizeof(NotifInfoInBuf^) + sizeof(WideChar) then begin
                result := false;
              end else begin
                result := Self.IterNext(DirChange, StopEvent, Timeout, NotifyFilter);
              end;
            end;            
          end;
        end; // .case WR_WAITED

        WinUtils.WR_TIMEOUT: begin
          DirChange.Action := NOTIFY_TIMEOUT;
        end;
      else
        result := false;
      end; // .switch wait result
    end; // .if

    Self.fIsEnd := not result;
  end; // .else
end; // .function TDirChangesIterator.IterNext

function ReadDirChanges (const DirPath: WideString): IDirChangesIterator;
begin
  result := TDirChangesIterator.Create(DirPath);
end;

function WatcherThreadProc (Arg: integer): integer; stdcall;
var
  IsEnd:             LONGBOOL;
  NeedFullRescan:    LONGBOOL;
  CurrentTime:       Int64;
  LastChangeTime:    Int64;
  PlannedRescanTime: Int64;
  Timeout:           integer;
  DummyEvent:        THandle;
  DirChangesScanner: IDirChangesIterator;
  DirChange:         TDirChange;

begin
  DirChangesScanner := nil;
  // * * * * * //
  IsEnd          := false;
  NeedFullRescan := false;
  LastChangeTime := 0;
  result         := 0;

  with VfsBase.GetThreadVfsDisabler do begin
    DisableVfsForThread;

    try
      while not IsEnd do begin
        CurrentTime       := GetMicroTime;
        PlannedRescanTime := LastChangeTime + Int64(WatcherDebounceInterval);

        if NeedFullRescan and (PlannedRescanTime <= CurrentTime) then begin
          VfsBase.RefreshVfs;
          NeedFullRescan := false;
        end;

        if DirChangesScanner = nil then begin
          DirChangesScanner := TDirChangesIterator.Create(AbsWatcherDir);
        end;

        // Failed to start watching directory
        if not DirChangesScanner.IterNext(DirChange, WatcherStopEvent, Utils.IfThen(boolean(NeedFullRescan), integer(PlannedRescanTime - CurrentTime), integer(Windows.INFINITE))) then begin
          // Force scanner recreation later
          DirChangesScanner := nil;

          // Wait and retry, unless stop signal is received
          Timeout := Utils.IfThen(NeedFullRescan, Min(WatcherDebounceInterval, integer(PlannedRescanTime - CurrentTime)), WatcherDebounceInterval);

          if WinUtils.WaitForObjects([WatcherStopEvent], DummyEvent, Timeout) = WinUtils.WR_WAITED then begin
            IsEnd := true;
          end;
        // Ok, got some signal
        end else begin
          if DirChange.Action = NOTIFY_STOP_EVENT then begin
            IsEnd := true;
          end else if DirChange.Action = NOTIFY_TIMEOUT then begin
            // Will perform full rescan on next loop iteration
          end else if DirChange.Action in [NOTIFY_FILE_ADDED, NOTIFY_FILE_REMOVED, NOTIFY_FILE_RENAMED_FROM_NAME, NOTIFY_FILE_RENAMED_TO_NAME, NOTIFY_UNKNOWN_ACTION, NOTIFY_TOO_MANY_CHANGES] then begin
            LastChangeTime := WinUtils.GetMicroTime;
            NeedFullRescan := true;
          end else if DirChange.Action = NOTIFY_FILE_MODIFIED then begin
            if not NeedFullRescan then begin
              VfsBase.RefreshMappedFile(DirChange.FilePath);
            end;
            
            LastChangeTime := WinUtils.GetMicroTime;
          end;
        end; // .else
      end; // .while
    finally
      RestoreVfsForThread;
    end; // .try
  end; // .with
end; // .function WatcherThreadProc

function RunWatcher (const WatchDir: WideString; DebounceInterval: integer): boolean;
const
  MANUAL_RESET = true;

begin
  with WatcherCritSection do begin
    Enter;

    result := not WatcherIsRunning;

    if result then begin
      AbsWatcherDir           := VfsUtils.NormalizePath(WatchDir);
      WatcherDebounceInterval := Max(0, DebounceInterval);

      if not WinUtils.IsValidHandle(WatcherStopEvent) then begin
        WatcherStopEvent := Windows.CreateEventW(nil, MANUAL_RESET, false, nil);
        result           := WinUtils.IsValidHandle(WatcherStopEvent);
      end;

      if result then begin
        WatcherThreadHandle := Windows.CreateThread(nil, 0, @WatcherThreadProc, nil, 0, WatcherThreadId);
      end;
    end;

    Leave;
  end; // .with
end; // .function RunWatcher

function StopWatcher: LONGBOOL;
const
  MANUAL_RESET = true;

begin
  with WatcherCritSection do begin
    Enter;

    result := WatcherIsRunning;

    if result then begin
      Windows.SetEvent(WatcherStopEvent);
      result := Windows.WaitForSingleObject(WatcherThreadHandle, Windows.INFINITE) = Windows.WAIT_OBJECT_0;

      if result then begin
        Windows.CloseHandle(WatcherThreadHandle);
        Windows.CloseHandle(WatcherStopEvent);
        WatcherThreadHandle := 0;
        WatcherStopEvent    := 0;
        WatcherIsRunning    := false;
      end;
    end;

    Leave;
  end; // .with
end; // .function StopWatcher

begin
  WatcherCritSection.Init;
end.