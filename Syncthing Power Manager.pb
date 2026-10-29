; ==============================================================================
; Syncthing Monitor for the sys tray
; PureBasic 6.40 - Windows 10
; © 2026 Peter Bergström - Licensed under the MIT License
; ==============================================================================
; 
; 2026-10-28: 
; Updated:      • The state machine is now updated with a more secure method running in the same loop as the events.
; Implemented:  • Log level is adjustable via preferences.
; 2026-10-26: V1.3
; Implemented:  • A state machine instead of flags trying to keep track of what actions to do.
; Implemented:  • The module DPSE is now in three parts: Logic, Windows signals and Timer events.
; 2026-10-17: v1.1
; Fixed:        • Path fix. The log file was saved to the development folder. Now it goes to the same folder as the
; Fixed:          prefs file - local on each computer.
; 2026-10-16: v1.0
; Updated: Bumping version to 1.0, the first release.
; Fixed:    • When display and power down is set to the same time out, the computer never powers down. (race
; Fixed:      condition) We get message: (PowerDown( From MainLoop power down timer ): Ignored - Task haven't
; Fixed:      run yet.) Which is correct, but there must be a trigger to power down when task has finished.
; Fixed:      (the logic is modified, remains to try it) - It seems to work now! Not sure exactly what did it
; Fixed:      because a lot of fixes have been made.
; 2026-10-06:
; Fixed:		• Since many things can happen at the same time, it's not sure that they happen in the correct
; Fixed:		  order, so some extra logic have been inserted to handle flags and their conditions.
; 2026-10-05:
; Updated:	• Task cool off time is now counted from when the message TaskDone arrives. (was in signaltask
; Updated:    procedure as a reminiscence before messages where used). This means task can't double run.
; 2026-10-16
; Todo: • Add a check of the server IP by verifying the prefs MAC and IP with the LookUp IP for the prefered MAC.
; Todo:   This is to detect a new IP if the server is using DHCP.
; Todo:   Also add a better fail safe if the lookup doesn't find the MAC.
; Todo: • Add colour preferences for the status. Should edit purple-okay, blue-online, yellow=not synced, green=synced
; Todo:   and red=no connection.
; Todo: • I've added blue colour. Make use of this when the IP answers the ping, meaning the server is online.
; Todo: • Add 'Override power settings', to temorarily change the timings or even turn power save off. The low level
; Todo:   parts in DPSE already support it.

EnableExplicit

CompilerIf #PB_Compiler_Debugger
  #debug_NoRunTask = #True
CompilerElse
  #debug_NoRunTask = #False
CompilerEndIf

#programName = "SyncthingPowerManager"

;< Definitions
IncludeFile "Module-Prefs.pbi"
IncludeFile "Form-SyncthingPrefs.pbf"
IncludeFile "Module-DetectPowerState.pbi" ; named DPSE (Detect Power States and Execute)
IncludeFile "Module-NetworkTools.pbi"
IncludeFile "Module-LookUpGUI.pbi"

DataSection
  LogoType:
  IncludeBinary "Syncthing_logo_16x16.PNG"
EndDataSection

Declare   EventHandler()
Declare   UpdateTrayIcon(color.l)
Declare.s SyncthingAPI(endpoint.s)
Declare   t_watchDog(*param)
Declare   InitPrefsWindow()
Declare.b PrefsWinEvents(thisEvent)

Enumeration Windows
  #Win_Main
EndEnumeration

Enumeration MenuItems
  #Menu_Status
  #Menu_Percent
  #Menu_Conflicts
  #Menu_Prefs
  #Menu_Exit
EndEnumeration

Enumeration TrayIcons
  #Tray_Main
EndEnumeration

Enumeration Images
  #Img_Logo
  #Img_Tray
EndEnumeration

#Col_Red    = $FF483FBF ; Offline when trying to sync.
#Col_Blue   = $FFD5A720 ; Online
#Col_Purple = $FFC06D9A ; Not connected or not updated.
#Col_Yellow = $FF07C1FF ; Update in progress.
#Col_Green  = $FF45A728 ; Updated.

Global gStatus$ = "Connecting..."
Global gPercent$ = "Waiting for connection..."
Global gConflict$ = "No conflicts"
Global gQuit.i = #False
Global gThreadMutex.i = CreateMutex()
Global threadWatchDog.i ;, threadPrefs

Define   prefsResult$
Define   keepActive.b

#stStatus               = "Status: "
#stStatus_notConnected  = "Server offline"
#stStatus_Sync          = "Synchronising..."
#stStatus_UpToDate      = "Up to date"
;>
;< Init preferences and read them in
#prefs_vaDbg        = "vaDbg" ; log / debug level
#prefs_nwMAC        = "nwMAC"
#prefs_nwServerIP   = "nwIP"
#prefs_nwSubNet     = "nwSubNet"
#prefs_stURL        = "stURL"
#prefs_stAPIKey     = "stAPIKey"
#prefs_stDeviceID   = "stDeviceID"
#prefs_stShowCodes  = "stShowCodes"
#prefs_prWinX       = "prWinX"
#prefs_prWinY       = "prWinY"

prefsResult$ = Prefs::Get(#programName)
If prefsResult$ <> #Null$
  MessageRequester("Syncthing Power Manager", prefsResult$)
  End
EndIf

If MapSize(Prefs::key()) = 0
  OpenprefsWin(400, 400)
  InitPrefsWindow()
  Repeat
    keepActive = PrefsWinEvents(WaitWindowEvent())
  Until Not keepActive
EndIf

DPSE::logLevel = Val(Prefs::key(#prefs_vaDbg))
If DPSE::logLevel < DPSE::#Log_Error
  DPSE::logLevel = DPSE::#Log_Error
EndIf
If DPSE::logLevel >= DPSE::#LogEndOfLevels
  DPSE::logLevel = DPSE::#LogEndOfLevels
EndIf

DPSE::logFileName = Prefs::MakeFileName(#programName, "") ; extension is added by WriteToLog due to it's functionality.
;>
;< Init window and icon
UsePNGImageDecoder()
If Not CatchImage(#Img_Logo, ?LogoType)
  DPSE::WriteToLog("Error - Monitor couldn't read logo.", DPSE::#Log_Error)
EndIf

If Not OpenWindow(#Win_Main, 0, 0, 0, 0, "Syncthing Monitor", #PB_Window_Invisible)
  DPSE::WriteToLog("Fatal Error - Monitor couldn't open window, quiting.", DPSE::#Log_Error)
  End
EndIf
  
If Not CreateImage(#Img_Tray, 16, 16, 32, #Col_Purple)
  DPSE::WriteToLog("Fatal Error - Monitor couldn't create tray icon, quiting.", DPSE::#Log_Error)
  End
EndIf
;>
; Main

DPSE::Init()
EventHandler()
DPSE::CleanUp()
;< Finish
If IsThread(threadWatchDog)
  WaitThread(threadWatchDog, 5000)
EndIf

RemoveSysTrayIcon(#Tray_Main)
End
;>

Declare     t_TryCompleteSync(*param)
Procedure   EventHandler()
  
  Protected popUpMenu, thisEvent
  
  AddSysTrayIcon(#Tray_Main, WindowID(#Win_Main), ImageID(#Img_Tray))
  SysTrayIconToolTip(#Tray_Main, "Syncthing Monitor")
  
  popUpMenu = CreatePopupMenu(#PB_Any)
  If popUpMenu
    MenuItem(#Menu_Status, #stStatus + #stStatus_notConnected)
    MenuItem(#Menu_Percent, "0%")
    MenuItem(#Menu_Conflicts, "No conflicts")
    DisableMenuItem(popUpMenu, #Menu_Status, #True)
    DisableMenuItem(popUpMenu, #Menu_Percent, #True)
    DisableMenuItem(popUpMenu, #Menu_Conflicts, #True)
    MenuBar()
    MenuItem(#Menu_Prefs, "Preferences")
    MenuBar()
    MenuItem(#Menu_Exit, "Quit")
  EndIf
  
  threadWatchDog = CreateThread(@t_watchDog(), 0)
  
  Repeat
    thisEvent = WaitWindowEvent(50)
    If thisEvent = #PB_Event_SysTray
      If EventType() = #PB_EventType_RightClick
        LockMutex(gThreadMutex)
        SetMenuItemText(popUpMenu, #Menu_Status, #stStatus + gStatus$)
        SetMenuItemText(popUpMenu, #Menu_Percent, gPercent$)
        SetMenuItemText(popUpMenu, #Menu_Conflicts, gConflict$)
        UnlockMutex(gThreadMutex)
        
        DisplayPopupMenu(popUpMenu, WindowID(#Win_Main))
      EndIf
    EndIf
    
    If thisEvent = #PB_Event_Menu
      If EventMenu() = #Menu_Exit
        gQuit = #True
      EndIf
      If EventMenu() = #Menu_Prefs
        OpenprefsWin(Val(Prefs::key(#prefs_prWinX)), Val(Prefs::key(#prefs_prWinY)))
        InitPrefsWindow()
      EndIf
        
    EndIf
    
    If thisEvent = DPSE::#Event_extRunTask
      CreateThread(@t_TryCompleteSync(), 0)
    EndIf
    
    DPSE::HookEventHandler(thisEvent)
    DPSE::TimerEventHandler(thisEvent)
    PrefsWinEvents(thisEvent)
    
    DPSE::StateMachine()
    
  Until gQuit = #True

EndProcedure

Procedure   t_TryCompleteSync(*param)
  
  Global  tryCompleteSyncRunning = #True
  Protected timer.q, serverIP.s
  
  CompilerIf #debug_NoRunTask
    Delay(4000)
    Goto FinishTask
  CompilerEndIf
  
  Debug "Trying to wake up server."
  NetworkTools::WakeOnLAN(Prefs::key(#prefs_nwMAC), Prefs::key(#prefs_nwSubNet))
  
  ; Wait for server to get online but give up if perhaps not on the network right now.
  timer = ElapsedMilliseconds()
  While ElapsedMilliseconds() - timer < 120000 And gStatus$ = #stStatus_notConnected And gQuit = #False
    Delay(200)
  Wend
  If gStatus$ = #stStatus_notConnected
    Debug "No contact with server, giving up"
    Goto FinishTask
  EndIf
  Debug "Server is awake."
  
  ; Wait for Syncthing to do its magic.
  Repeat
    If ElapsedMilliseconds() - timer > 30000
      Debug "Synchronizing..."
      timer = ElapsedMilliseconds()
    EndIf
    Delay(200)
  Until gStatus$ = #stStatus_UpToDate Or gStatus$ = #stStatus_notConnected Or gQuit = #True
  Debug "Stopped waiting for sync"
  
  FinishTask:
  PostEvent(DPSE::#Event_extTaskDone, 0, 0)
  tryCompleteSyncRunning = #False
  
EndProcedure

Procedure   UpdateTrayIcon(color.l)
  
  If Not CreateImage(#Img_Tray, 16, 16, 32, color) 
    Debug "Couldn't create #Img_Tray"
    ProcedureReturn
  EndIf
  
  If Not IsImage(#Img_Logo)
    Debug "The logo picture is missing"
    ProcedureReturn
  EndIf
  
  If Not StartDrawing(ImageOutput(#Img_Tray))
    Debug "Couldn't draw on #Img_Tray"
    ProcedureReturn
  EndIf
 
  DrawingMode(#PB_2DDrawing_AlphaBlend)
  DrawImage(ImageID(#Img_Logo), 0, 0, 16, 16)
  StopDrawing()
  
  ChangeSysTrayIcon(#Tray_Main, ImageID(#Img_Tray))
  
EndProcedure

Procedure.s SyncthingAPI(endpoint.s)
  
  Protected httpRequest.i, response.s = ""
  NewMap myHeaders$()
  
  myHeaders$("X-API-Key") = Prefs::key(#prefs_stAPIKey)
  
  httpRequest = HTTPRequest(#PB_HTTP_Get, Prefs::key(#prefs_stURL) + endpoint, "", #PB_HTTP_NoSSLCheck, myHeaders$())
  If httpRequest
    response = HTTPInfo(httpRequest, #PB_HTTP_Response)
    FinishHTTP(httpRequest)
  EndIf
  
  ProcedureReturn response
  
EndProcedure

Declare.b   _checkConnection()
Declare.f   _uploadNeeds(*files.Integer, *dirs.Integer)
Declare.i   _checkForProblems()
Procedure   t_watchDog(*param)
  
  Protected   jsonRaw.s, connected.b, completion.f
  Protected.i jsonObj, needFiles, needDirs
  Protected.i syncStarted, conflictCount, rootVal
  Protected.i currentColor, lastColor, localIsSyncing
  
  Repeat
    localIsSyncing = #False
    
    connected = _checkConnection()
    If connected
      
      completion = _uploadNeeds(@needFiles, @needDirs)
      If completion < 100.0 Or needFiles > 0 Or needDirs > 0
        localIsSyncing = #True
      EndIf
      conflictCount = _checkForProblems()
      
    EndIf
    
    LockMutex(gThreadMutex)
    
    If Not connected
      gStatus$ = #stStatus_notConnected
      gPercent$ = "Waiting for connection..."
      gConflict$ = "Conflict: none"
      syncStarted = #False
      If tryCompleteSyncRunning
        currentColor = #Col_Red
      Else
        currentColor = #Col_Purple ; Purple (Disconnected)
      EndIf
    Else
      ; Server is online.
      If conflictCount <> 0
        gConflict$ = "⚠️ Errors/Conflicts: " + Str(conflictCount) + " occurrences!"
      Else
        gConflict$ = "No conflicts discovered"
      EndIf
      
      ; Check if something is transferred (up or down).
      If localIsSyncing
        gStatus$ = #stStatus_Sync
        gPercent$ = "Left: " + Str(needFiles) + " files, " + Str(needDirs) + " directories (" + StrF(completion, 1) + "%)"
        syncStarted = #True
        currentColor = #Col_Yellow ; Yellow (Syncing)
      Else
        gStatus$ = #stStatus_UpToDate
        gPercent$ = "All done (" + StrF(completion, 1) + "%)"
        currentColor = #Col_Green ; Green (Done)
        
      EndIf
    EndIf
    
    ; Only update the tray icon if the colour has changed (which depends on the status).
    If currentColor <> lastColor
      UpdateTrayIcon(currentColor)
      lastColor = currentColor
    EndIf
    
    UnlockMutex(gThreadMutex)
    
    Delay(1000)
  Until gQuit = #True
  
EndProcedure

Procedure.b _checkConnection()

  Protected   jsonRaw.s, jsonObj.i, connected.b, error.i
  Protected.i objectValue, connectionsObj, connectionNode
  
  jsonRaw = SyncthingAPI("/rest/system/connections")
  If jsonRaw = ""
    Debug "REST are not giving us any answer (_checkConnection)"
    ProcedureReturn #False
  EndIf
  
  jsonObj = ParseJSON(#PB_Any, jsonRaw)
  If Not jsonObj
    Debug "Not compatible with JSON (_checkConnection)"
    ProcedureReturn #False
  EndIf
  
  objectValue = JSONValue(jsonObj)
  If JSONType(objectValue) <> #PB_JSON_Object
    Debug "The type of data is not an object (_checkConnection)"
    error = #True
  EndIf
    
  connectionsObj = GetJSONMember(objectValue, "connections")
  If Not error And (Not connectionsObj Or JSONType(connectionsObj) <> #PB_JSON_Object)
    Debug "Can't find details about our connections"
    error = #True
  EndIf
  
  If Not error And Not ExamineJSONMembers(connectionsObj)
    Debug "Can't examine the object"
    error = #True
  EndIf
  
  If error
    FreeJSON(jsonObj)
    ProcedureReturn #False
  EndIf
  
  While NextJSONMember(connectionsObj)
    If JSONMemberKey(connectionsObj) <> Prefs::key(#prefs_stDeviceID)
      Continue ; Not the searced device. Try next member.
    EndIf
    
    connectionNode = JSONMemberValue(connectionsObj)
    If Not GetJSONMember(connectionNode, "connected")
      Continue ; No status for connected. Try next member. We have to be sure to have this or the next test will fail hard.
    EndIf
    
    If GetJSONBoolean(GetJSONMember(connectionNode, "connected")) = #True
      connected = #True ; Found the searched device and it's online.
      Break   ; break out from the while-wend loop
    EndIf
  Wend
  
  FreeJSON(jsonObj)
  ProcedureReturn connected
  
EndProcedure

Procedure.f _uploadNeeds(*files.Integer, *dirs.Integer)
  
  Protected jsonRaw.s, jsonObj.i, completion.f, rootVal.i
  
  jsonRaw = SyncthingAPI("/rest/db/completion?device=" + Prefs::key(#prefs_stDeviceID))
  If jsonRaw = ""
    Debug "REST are not giving us any answer (_uploadNeeds)"
    ProcedureReturn -1
  EndIf
  
  jsonObj = ParseJSON(#PB_Any, jsonRaw)
  If Not jsonObj
    Debug "Not compatible with JSON (_uploadNeeds)"
    ProcedureReturn -1
  EndIf
  
  rootVal = JSONValue(jsonObj)
  If JSONType(rootVal) = #PB_JSON_Object
    If GetJSONMember(rootVal, "completion")
      completion = GetJSONDouble(GetJSONMember(rootVal, "completion"))
    EndIf
    If GetJSONMember(rootVal, "needFiles")
      *files\i = GetJSONInteger(GetJSONMember(rootVal, "needFiles"))
    EndIf
    If GetJSONMember(rootVal, "needDirectories")
      *dirs\i = GetJSONInteger(GetJSONMember(rootVal, "needDirectories"))
    EndIf
  Else
    completion = 100.0
    *files = 0
    *dirs = 0
  EndIf
  
  FreeJSON(jsonObj)
  ProcedureReturn completion
  
EndProcedure

Procedure.i _checkForProblems()
  
  Protected jsonRaw.s, jsonObj.i, errorsNode.i
  Protected conflictCount.i, rootVal.i
  
  jsonRaw = SyncthingAPI("/rest/system/error")
  If jsonRaw = ""
    Debug "REST are not giving us any answer (_checkForProblems)"
    ProcedureReturn -1
  EndIf
  
  jsonObj = ParseJSON(#PB_Any, jsonRaw)
  If Not jsonObj
    Debug "Not compatible with JSON (_checkForProblems)"
    ProcedureReturn -1
  EndIf
  
  rootVal = JSONValue(jsonObj)
  If JSONType(rootVal) = #PB_JSON_Object
    errorsNode = GetJSONMember(rootVal, "errors")
    If errorsNode And JSONType(errorsNode) = #PB_JSON_Array
      conflictCount = JSONArraySize(errorsNode)
    EndIf
  EndIf
  
  FreeJSON(jsonObj)
  ProcedureReturn conflictCount
  
EndProcedure

Procedure   InitPrefsWindow()
  
  Protected flag.b
  
  StickyWindow(prefsWin, #True)
  If MapSize(Prefs::key()) > 0
    SetGadgetText(str_nwSubNet,     Prefs::key(#prefs_nwSubNet))
    SetGadgetText(str_nwServerIP,   Prefs::key(#prefs_nwServerIP))
    SetGadgetText(str_nwServerMAC,  Prefs::key(#prefs_nwMAC))
    SetGadgetText(str_stURL,        Prefs::key(#prefs_stURL))
    SetGadgetText(str_stAPIKey,     Prefs::key(#prefs_stAPIKey))
    SetGadgetText(str_stDeviceID,   Prefs::key(#prefs_stDeviceID))
    SetGadgetText(str_vaDbg,        Prefs::key(#prefs_vaDbg))
    
    flag = Val(Prefs::key(#prefs_stShowCodes))
    SetGadgetState(chk_stShowCodes, flag)
    SetGadgetState(chk_stAPIKey,    flag)
    SetGadgetState(chk_stDeviceID,  flag)
    SendMessage_(GadgetID(str_stAPIKey),    #EM_SETPASSWORDCHAR, Bool(Not flag), 0)
    SendMessage_(GadgetID(str_stDeviceID),  #EM_SETPASSWORDCHAR, Bool(Not flag), 0)
    DisableGadget(chk_stAPIKey,   flag)
    DisableGadget(chk_stDeviceID, flag)
  EndIf
  
EndProcedure

Procedure.b PrefsWinEvents(thisEvent.i)
  
  ; This is an extension of the main event loop.
  ; Returns a boolean to help the initial prefs request (when there is no prefs file). Otherwise it does nothing.
  ; Returning #True is for keeping on calling and #False is for closed window (and stop calling).
  
  Protected prefsResult$, flag.b, subNet$, string.s, dotCount
  Static lookUpDisabled.b
  
  ; If my window isn't open, there's nothing here to check.
  If Not IsWindow(prefsWin)
    ProcedureReturn #False
  EndIf
  
  ; If tray icon commands quit (gQuit), I follow.
  If gQuit Or thisEvent = #PB_Event_CloseWindow
    CloseWindow(prefsWin)
    ProcedureReturn #False
  EndIf
  
  If lookUpDisabled
    If Not LookUpGUI::IsRunning()
      DisableGadget(btn_nwLookUp, #False)
      lookUpDisabled = #False
    EndIf
  EndIf
  
  If thisEvent <> #PB_Event_Gadget
    ProcedureReturn #True
  EndIf
  
  Select EventGadget()
      
    Case chk_stAPIKey
      
      SendMessage_(GadgetID(str_stAPIKey),    #EM_SETPASSWORDCHAR, Bool(Not GetGadgetState(chk_stAPIKey)), 0)
      InvalidateRect_(GadgetID(str_stAPIKey),   0, #True)
      
    Case chk_stDeviceID
      
      SendMessage_(GadgetID(str_stDeviceID),  #EM_SETPASSWORDCHAR, Bool(Not GetGadgetState(chk_stDeviceID)), 0)
      InvalidateRect_(GadgetID(str_stDeviceID), 0, #True)
      
    Case chk_stShowCodes
      
      flag = GetGadgetState(chk_stShowCodes)
      
      SetGadgetState(chk_stAPIKey,    flag)
      DisableGadget( chk_stAPIKey,    flag)
      SetGadgetState(chk_stDeviceID,  flag)
      DisableGadget( chk_stDeviceID,  flag)
      
      SendMessage_(   GadgetID(str_stAPIKey),    #EM_SETPASSWORDCHAR, Bool(Not flag), 0)
      SendMessage_(   GadgetID(str_stDeviceID),  #EM_SETPASSWORDCHAR, Bool(Not flag), 0)
      InvalidateRect_(GadgetID(str_stAPIKey),   0, #True)
      InvalidateRect_(GadgetID(str_stDeviceID), 0, #True)
      
    Case btn_nwLookUp
      
      Static lookUp.LookUpGUI::lookUpData
      ClearList(lookUp\netData\devices())
      lookUp\netData\errorMsg = ""
      lookUp\netData\quitScan = #False
      lookUp\netData\scanDone = #False
      lookUp\netData\subNet$ = GetGadgetText(str_nwSubNet)
      lookUp\netData\scanStart = 1
      lookUp\netData\scanLast  = 254
      lookUp\index = -1
      DisableGadget(btn_nwLookUp, #True)
      lookUpDisabled = #True
      LookUpGUI::Collect(lookUp)
      If lookUp\chosenMAC <> #Null$
        SetGadgetText(str_nwServerIP , lookUp\chosenIP)
        SetGadgetText(str_nwServerMAC, lookUp\chosenMAC)
      EndIf
      
    Case btn_Cancel
      
      CloseWindow(prefsWin)
      ProcedureReturn #False
      
    Case btn_Save
      
      ; check up the format of the sub net.
      string = GetGadgetText(str_nwSubNet)
      If Right(string, 1) <> "."
        string + "."
      EndIf
      dotCount = CountString(string, ".")
      subNet$ = Str(Val(StringField(string, 1, "."))) + "."
      subNet$ + Str(Val(StringField(string, 2, "."))) + "."
      subNet$ + Str(Val(StringField(string, 3, ".")))
      If string <> subNet$
        SetGadgetText(str_nwSubNet, string)
      EndIf
      
      If Len(GetGadgetText(str_nwServerMAC)) <> 17 Or CountString(GetGadgetText(str_nwServerMAC), ":") <> 5
        MessageRequester("Error", "A MAC address must have the format $$:$$:$$:$$:$$:$$:$$:$$")
        SetActiveGadget(str_nwServerMAC)
      ElseIf subNet$ <> Left(string, Len(subNet$)) Or dotCount <> 3
        MessageRequester("Error", "The subnet should be in the form n.n.n. or n.n.n, where n >= 0 and <= 255." +
                                  "Common subnets are 10.0.0. and 192.168.1.")
        SetActiveGadget(str_nwSubNet)
      Else
        Prefs::key(#prefs_nwMAC)        = GetGadgetText(str_nwServerMAC)
        Prefs::key(#prefs_nwServerIP)   = GetGadgetText(str_nwServerIP)
        Prefs::key(#prefs_nwSubNet)     = GetGadgetText(str_nwSubNet)
        Prefs::key(#prefs_stURL)        = GetGadgetText(str_stURL)
        Prefs::key(#prefs_stAPIKey)     = GetGadgetText(str_stAPIKey)
        Prefs::key(#prefs_stDeviceID)   = GetGadgetText(str_stDeviceID)
        Prefs::key(#prefs_prWinX)       = Str(WindowX(prefsWin))
        Prefs::key(#prefs_prWinY)       = Str(WindowY(prefsWin))
        Prefs::key(#prefs_stShowCodes)  = Str(GetGadgetState(chk_stShowCodes))
        Prefs::key(#prefs_vaDbg)        = GetGadgetText(str_vaDbg)
        DPSE::logLevel                  = Val(Prefs::key(#prefs_vaDbg))
        
        prefsResult$ = Prefs::Set()
        If prefsResult$ <> #Null$
          Debug prefsResult$
        EndIf
        CloseWindow(prefsWin)
        ProcedureReturn #False
      EndIf
      
  EndSelect
  
  ProcedureReturn #True
  
EndProcedure

; IDE Options = PureBasic 6.40 (Windows - x64)
; CursorPosition = 37
; Folding = -4H-
; Optimizer
; EnableThread
; EnableXP
; DPIAware
; Compiler = PureBasic 6.40 - C Backend (Windows - x64)