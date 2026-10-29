; ============================================================================================
; Detect power states and execute (DPSE) - module
; PureBasic 6.40 - Windows 10+
; © 2026 Peter Bergström - all rights reserved
; © 2026 Peter Bergström - Licensed under the MIT License
; ============================================================================================

CompilerIf Not #PB_Compiler_Thread
  CompilerError "Module DPSE needs the thread safe option."
CompilerEndIf

DeclareModule DPSE
  
  ; Abstraction Declaration for WriteToLog
  
  Enumeration loggingLevel
    #Log_System
    #Log_Error
    #Log_Warning
    #Log_Info
    #Log_Detail
    #LogEndOfLevels
  EndEnumeration
  
  Declare.l   WriteToLog(message.s, level.l, caller.s = "")
  
  Define logLevel.l = #Log_Error ; log errors as default.

  
  ; Abstraction Declarations for Logic
  
  Declare   StateMachine()
  Declare   SM_TriggerInputEvent(inputEvent.l)
  
  Enumeration inputs
    #In_DisplayActivated
    #In_DisplayDeactivated
    #In_DisplayDimmed
    #In_DisplayTimeChanged
    #In_SleepTimeChanged    ;  4
    #In_PowerSchemeChanged
    #In_PowerPolicyChanged
    #In_PowerButton
    #In_InputHook
    #In_SystemResume        ;  9
    #In_System_powerDown
    #In_UserLogOff
    #In_SystemShutDown
    #In_extTaskDone
    #In_TimeOutDisplay      ; 14
    #In_TimeOutStandby
    #In_TimeOutTaskCoolOff
    #InputLastIndex
  EndEnumeration

  ; Abstraction Declarations for Windows signals
  
  Enumeration returnCodes 0 Step -1
    #success = 0                  ; Everything's okay.
    #noLib_kernel32               ; Can't open kernel32.dll.
    #noLib_PowrProf               ; Can't open powrprof.dll.
    #noLib_User32                 ; Can't open user32.dll.
    #noWindow                     ; Parameter is not an open window number (#window).
    #noExecutionState             ; can't find function SetThreadExecutionState.
    #noPowerScheme                ; No active power scheme.
    #noPowerGetActiveScheme       ; Can't find function PowerGetActiveScheme.
    #noPowerReadACValueIndex      ; Can't find function PowerReadACValueIndex.
    #noPowerReadDCValueIndex      ; Can't find function PowerReadDCValueIndex.
    #noSetSuspendState            ; Can't find function SetSuspendState.
    #noSendInput                  ; Can't find function SendInput.
    #noReadPowerOffModes          ; Can't get what power off modes that are available.
    #noPowerManagementFound       ; Can't find any power management on this machine.
    #noPowerSettingsNotification  ; Can't register power settings notifications.
    #noInputHooks                 ; Can't register input hooks for keys or mouse.
  EndEnumeration
  
  EnumerationBinary powerModes
    #pwrSrcAC
    #pwrSrcDC
    #pwrOffSleep
    #pwrOffHibernate
    #pwrOffShutdown
  EndEnumeration
  
  Structure pwrScheme
    pwrSrc.l
    supportedPwrOffModes.l
    displayOff_seconds.l
    standby_seconds.l
    overrideDisplayOff_seconds.l
    overrideStandby_seconds.l
  EndStructure
  
  Declare.l   PS_Init(window)
  Declare.l   GetModernPowerSettings(*pwrSettings.pwrScheme)
  Declare.l   GetPowerSettingChange(lParam, *displayState)
  Declare.b   SetComputerSuspendState(useHibernate.b = #False, force.b = #True, disableWake.b = #False)
  Declare     DisplayOff(caller.s)
  Declare     DisplayOn(caller.s)
  Declare     JogMouse(caller.s)
  Declare     SuppressStandby(displayAlwaysOn.b)
  Declare     _stopInputDetection(caller.s)
  Declare     AllowStandby(caller.s)
  Declare.q   GetInputIdleTime()
  Declare     HookEventHandler(thisEvent.i)
  Declare.l   PS_Free()
  
  Define logFileName.s = GetPathPart(ProgramFilename()) + "pTb-PowerState" ; extension is added automatically.
  
  ; Abstraction Declarations for Timer events
  
  Declare     Init()
  Declare     TimerEventHandler(thisEvent.i)
  Declare     SignalTaskToExecute(caller.s)
  Declare.b   PowerDown(caller.s)
  Declare     t_WinCallback(hWnd.i, uMsg.i, wParam.i, lParam.i)
  Declare     CleanUp()
  
  Enumeration customEvents #PB_Event_FirstCustomValue
    #Event_DisplayActivated
    #Event_DisplayDeactivated
    #Event_DisplayDimmed
    #Event_DisplayTimeChanged
    #Event_SleepTimeChanged
    #Event_PowerSchemeChanged
    #Event_PowerPolicyChanged
    #Event_PowerButton
    #Event_InputHook
    
    #Event_SystemResume
    #Event_System_powerDown
    #Event_UserLogOff
    #Event_SystemShutDown
  
    ; These are external events that can be posted from or to this module for different behaviours.
    #Event_extRunTask             ; signal to the main program to run its task.
    #Event_extTaskDone            ; signal from main program that the task is done.
    #Event_extTempDisplayOffTimer ; sets a temporary display off timer. 0 = never and -1 resets the time limit.
    #Event_extTempPowerOffTimer   ; sets a temporary power off timer. 0 = never and -1 resets the time limit.
  EndEnumeration
    
  Enumeration customEventTypes #PB_Event_FirstCustomValue
    #EventType_MouseFiltered
    #EventType_MouseMoved
    #EventType_KeyPressed
    #EventType_MButton
  EndEnumeration
  
EndDeclareModule

Module DPSE
  
  EnableExplicit
    
  ; Abstraction Definitions for Logic 
  
  Enumeration states
    #State_ScreenIsOn
    #State_ScreenRunningTask
    #State_ScreenIsOff
    #State_PowerRunningTask
    #State_PoweringDown
    #State_Resuming
  EndEnumeration
  
  Global currentState.l
  Global sm_Sum.l
  Global Dim sm_Inputs.b(#InputLastIndex - 1)
;   Global Dim sm_Snapshot.b(#InputLastIndex - 1)
  Global Dim sm_InputNames.s(#InputLastIndex - 1)
  sm_InputNames( 0) = "#In_DisplayActivated"
  sm_InputNames( 1) = "#In_DisplayDeactivated"
  sm_InputNames( 2) = "#In_DisplayDimmed"
  sm_InputNames( 3) = "#In_DisplayTimeChanged"
  sm_InputNames( 4) = "#In_SleepTimeChanged"
  sm_InputNames( 5) = "#In_PowerSchemeChanged"
  sm_InputNames( 6) = "#In_PowerPolicyChanged"
  sm_InputNames( 7) = "#In_PowerButton"
  sm_InputNames( 8) = "#In_InputHook"
  sm_InputNames( 9) = "#In_SystemResume"
  sm_InputNames(10) = "#In_System_powerDown"
  sm_InputNames(11) = "#In_UserLogOff"
  sm_InputNames(12) = "#In_SystemShutDown"
  sm_InputNames(13) = "#In_extTaskDone"
  sm_InputNames(14) = "#In_TimeOutDisplay"
  sm_InputNames(15) = "#In_TimeOutStandby"
  sm_InputNames(16) = "#In_TimeOutTaskCoolOff"

  ; Abstraction Definitions for Windows signals 
  
  IncludeFile "WriteToLog.pbi"
  
  #MONITOR_OFF = 2
  #MONITOR_ON = -1
  
  #filterDelta = 3
  
  Structure POWERBROADCAST_SETTING
    powerSetting.GUID
    dataLength.l
    dataBlock.a[1] ; Original name is Data, but that's a command in PB.
  EndStructure
  
  Structure MSLLHOOKSTRUCT
    pt.POINT
    mouseData.l
    flags.l
    time.l
    dwExtraInfo.i
  EndStructure
  
  Declare.q _getDwTime()
  
  ; powrprof.dll
  Prototype   Proto_PowerGetActiveScheme(userRootRegKey, *activePolicyGuid)
  Prototype   Proto_PowerReadACValueIndex(rootPowerKey, *schemeGuid, *subGroupOfPowerSettingsGuid, *powerSettingGuid, *acValueIndex)
  Prototype   Proto_PowerReadDCValueIndex(rootPowerKey, *schemeGuid, *subGroupOfPowerSettingsGuid, *powerSettingGuid, *dcValueIndex)
  Prototype   Proto_IsPwrSuspendAllowed()
  Prototype   Proto_IsPwrHibernateAllowed()
  Prototype   Proto_IsPwrShutdownAllowed()
  Prototype.b Proto_SetSuspendState(hibernate.b, forceCritical.b, disableWakeEvents.b)
  
  ; user32.dll
  Prototype.i Proto_RegisterPowerSettingNotification(hRecipient.i, *powerSettingGuid, flags.l)
  Prototype.i Proto_UnregisterPowerSettingNotification(handle.i)
  ;   Prototype.l Proto_ShutdownBlockReasonCreate(hWnd, pwszReason.p-unicode)
  ;   Prototype.l Proto_ShutdownBlockReasonDestroy(hWnd)
  Prototype.u Proto_SendInput(cInputs.u, *pInputs, cbSize.l)
  
  ; kernel32.dll
  Prototype.l Proto_SetThreadExecutionState(esFlags.l)
  
  Define   lastValidTickCount.i
  Define.b displayTurnedOff
  ElapsedMilliseconds() ; force start counting ticks. So we don't get false negatives later on.
  Global eventFloodFilter.i  ; filter out fast events
  #floodBorder = 10000

  ; Abstraction Definitions for Timer events 
  
  Declare.l GetRemainingTime(target.l)
  ; Constants for GetRemainingTime(). Note that GRT is a TLA for the function. Easy to remember.
  #GRT_Display = 1
  #GRT_Computer = 2
  Declare     StartDisplayOffTimer(caller.s)  
  Declare     StartPowerOffTimer(caller.s)
  Declare     NoDisplayOffTimer(caller.s)
  Declare     NoPowerOffTimer(caller.s)
  Declare.b   ValidateDisplayTimeout()
  Declare.b   ValidatePowerTimeout()
  Declare.s   TicksToString(ticks.q)
  
  Global currentPowerSettings.pwrScheme
  Global powerSource$
  Global displayState.l, forceDisplayOn.b = #True
  
  #maxDelayChunkTicks = 3600000 ; This is used when delay is zero (always on).
  #taskCoolDownTicks = 1 * 30 * 1000 ; The minimum paus between starts of the task.
  #_powerDownCoolDownTicks = 30 * 1000 ; Minimum delay between shut downs (prevents double events from happening).
  #overrideInactive = -1
  
  ; Abstraction Procedures for Logic
  
  Procedure   SM_TriggerInputEvent(inputEvent.l)
    
    sm_Inputs(inputEvent) = #True
    WriteToLog(sm_InputNames(inputEvent), #Log_Info)
    
  EndProcedure
  
  Procedure.b SM_CheckInput(inputEvent.l)
    
    If sm_Inputs(inputEvent)
      sm_Sum - 1
      ProcedureReturn #True
    EndIf
    
  EndProcedure
  
  Procedure   StateMachine()
    
    Protected i.l, lastSum.l
    
    sm_Sum = 0 : lastSum = 0
    For i = 0 To #InputLastIndex - 1
      sm_Sum + sm_Inputs(i)
    Next
    
    ; Repeat until no more inputs have been handled
    Repeat
      lastSum = sm_Sum
      
      Select currentState
          
        Case #State_ScreenIsOn
          If SM_CheckInput(#In_TimeOutDisplay)
            WriteToLog("#State_ScreenIsOn - #In_TimeOutDisplay -> #State_ScreenRunningTask", #Log_Info)
            SignalTaskToExecute("#State_ScreenIsOn")
            currentState = #State_ScreenRunningTask
            sm_Inputs(#In_TimeOutDisplay) = #False
          EndIf
          
          If SM_CheckInput(#In_PowerButton)
            WriteToLog("#State_ScreenIsOn - #In_PowerButton -> #State_PowerRunningTask", #Log_Info)
            DisplayOn("#In_PowerButton")
            SignalTaskToExecute("#In_PowerButton")
            currentState = #State_PowerRunningTask
            sm_Inputs(#In_PowerButton) = #False
          EndIf
          
        Case #State_ScreenRunningTask
          If SM_CheckInput(#In_extTaskDone)
        
            If SM_CheckInput(#In_TimeOutStandby)
              sm_Inputs(#In_extTaskDone) = #False
              sm_Inputs(#In_TimeOutStandby) = #False
              
              If PowerDown("")
                WriteToLog("#State_ScreenRunningTask - #In_extTaskDone -> #State_PoweringDown", #Log_Info)
                currentState = #State_PoweringDown
              Else
                WriteToLog("FAILED PowerDown -> #State_ScreenRunningTask - #In_extTaskDone -> #State_ScreenIsOn", #Log_Info)
                DisplayOn("#State_ScreenRunningTask")
                JogMouse("#State_ScreenRunningTask")
                currentState = #State_ScreenIsOn
              EndIf
            Else
              WriteToLog("#State_ScreenRunningTask - #In_extTaskDone -> #State_ScreenIsOff", #Log_Info)
              DisplayOff("#State_ScreenRunningTask")
              currentState = #State_ScreenIsOff
              sm_Inputs(#In_extTaskDone) = #False
            EndIf
          EndIf
          
        Case #State_ScreenIsOff
          If SM_CheckInput(#In_InputHook)
            WriteToLog("#State_ScreenIsOff - #In_InputHook -> #State_ScreenIsOn", #Log_Info)
            _stopInputDetection("#State_ScreenIsOff")
            DisplayOn("#State_ScreenIsOff")
            currentState = #State_ScreenIsOn
            sm_Inputs(#In_InputHook) = #False
            
          ElseIf SM_CheckInput(#In_DisplayActivated)
            WriteToLog("#State_ScreenIsOff - #In_DisplayActivated <-", #Log_Info)
            DisplayOff("#State_ScreenIsOff")
            sm_Inputs(#In_DisplayActivated) = #False
          EndIf
          
          If SM_CheckInput(#In_TimeOutStandby)
            sm_Inputs(#In_TimeOutStandby) = #False
            
            If PowerDown("#State_ScreenIsOff")
              WriteToLog("#State_ScreenIsOff - #In_TimeOutStandby -> #State_PoweringDown", #Log_Info)
              currentState = #State_PoweringDown
            Else
              WriteToLog("FAILED PowerDown -> #State_ScreenIsOff - #In_TimeOutStandby -> #State_ScreenIsOn", #Log_Info)
              DisplayOn("#State_ScreenIsOff")
              JogMouse("#State_ScreenIsOff")
              currentState = #State_ScreenIsOn
            EndIf
          EndIf
          
        Case #State_PowerRunningTask
          If SM_CheckInput(#In_extTaskDone)
            sm_Inputs(#In_extTaskDone) = #False
            If PowerDown("#State_PowerRunningTask")
              WriteToLog("#State_PowerRunningTask - #In_extTaskDone -> #State_PoweringDown", #Log_Info)
              currentState = #State_PoweringDown
            Else
              WriteToLog("FAILED PowerDown -> #State_PowerRunningTask - #In_extTaskDone -> #State_ScreenIsOn", #Log_Info)
              DisplayOn("#State_PowerRunningTask")
              JogMouse("#State_PowerRunningTask")
              currentState = #State_ScreenIsOn
            EndIf
          EndIf
          
        Case #State_PoweringDown
          If SM_CheckInput(#In_SystemResume)
            WriteToLog("#State_PoweringDown - #In_SystemResume -> #State_Resuming", #Log_Info)
            SignalTaskToExecute("#State_PoweringDown")
            currentState = #State_Resuming
            sm_Inputs(#In_SystemResume) = #False
          EndIf
          
        Case #State_Resuming
          If SM_CheckInput(#In_extTaskDone)
            WriteToLog("#State_Resuming - #In_extTaskDone -> #State_ScreenIsOn", #Log_Info)
            currentState = #State_ScreenIsOn
            sm_Inputs(#In_extTaskDone) = #False
          EndIf
          
      EndSelect
    Until lastSum = sm_Sum
    
  EndProcedure
                
  ; Abstraction Procedures for Windows signals
  
  ;< Init
  Declare.l   _initkernel32Functions()
  Declare.l   _initUser32Functions()
  Declare.l   _initPowrProfFunctions()
  Declare     _initGUID()
  Declare.l   _registerNotifications(window)
  Procedure.l PS_Init(window)
    
    Shared logFileName, logLevel
    Protected status.l
    
    If Not WriteToLog("", #Log_System)
      MessageRequester("PowerSchemes::Init", "Error, failed to write to log file " + logFileName + #CRLF$ + "No log entries will be written.")
    EndIf
    WriteToLog("New session: Log level " + logLevel, #Log_System)
    
    status = _initkernel32Functions()
    If status <> #success
      ProcedureReturn status
    EndIf
    
    status = _initUser32Functions()
    If status <> #success
      ProcedureReturn status
    EndIf
    
    status = _initPowrProfFunctions()
    If status <> #success
      ProcedureReturn status
    EndIf
    
    _initGUID()
    status = _registerNotifications(window)
    
    ProcedureReturn status
    
  EndProcedure
  
  Procedure.l _initkernel32Functions()
    
    Global hkernel32
    
    hkernel32 = OpenLibrary(#PB_Any, "kernel32.dll")
    If Not hkernel32
      WriteToLog("_initKernel32Functions() - Error, couldn't open kernel32.dll", #Log_Error)
      ProcedureReturn #noLib_kernel32
    EndIf
    
    Global SetThreadExecutionState.Proto_SetThreadExecutionState
    SetThreadExecutionState = GetFunction(hkernel32, "SetThreadExecutionState")
    
    If Not SetThreadExecutionState
      WriteToLog("_initKernel32Functions() - Error, can't find function SetThreadExecutionState", #Log_Error)
      ProcedureReturn #noExecutionState
    EndIf
    
    ProcedureReturn #success
    
  EndProcedure
  
  Procedure.l _initPowrProfFunctions()
    
    Global hPowrProf
    
    hPowrProf = OpenLibrary(#PB_Any, "powrprof.dll")
    If Not hPowrProf
      WriteToLog("_initPowrProfFunctions() - Error, couldn't open powrprof.dll", #Log_Error)
      ProcedureReturn #noLib_PowrProf
    EndIf
    
    Global PowerGetActiveScheme.Proto_PowerGetActiveScheme
    Global PowerReadACValueIndex.Proto_PowerReadACValueIndex
    Global PowerReadDCValueIndex.Proto_PowerReadDCValueIndex
    Global IsPwrSuspendAllowed.Proto_IsPwrSuspendAllowed
    Global IsPwrHibernateAllowed.Proto_IsPwrHibernateAllowed
    Global IsPwrShutdownAllowed.Proto_IsPwrShutdownAllowed
    Global SetSuspendState.Proto_SetSuspendState
    PowerGetActiveScheme  = GetFunction(hPowrProf, "PowerGetActiveScheme")
    PowerReadACValueIndex = GetFunction(hPowrProf, "PowerReadACValueIndex")
    PowerReadDCValueIndex = GetFunction(hPowrProf, "PowerReadDCValueIndex")
    IsPwrSuspendAllowed   = GetFunction(hPowrProf, "IsPwrSuspendAllowed")
    IsPwrHibernateAllowed = GetFunction(hPowrProf, "IsPwrHibernateAllowed")
    IsPwrShutdownAllowed  = GetFunction(hPowrProf, "IsPwrShutdownAllowed")
    SetSuspendState       = GetFunction(hPowrProf, "SetSuspendState")
    
    If Not PowerGetActiveScheme
      WriteToLog("_initPowrProfFunctions() - Error, can't find function PowerGetActiveScheme", #Log_Error)
      ProcedureReturn #noPowerGetActiveScheme
    EndIf
    If Not PowerReadACValueIndex
      WriteToLog("_initPowrProfFunctions() - Error, can't find function PowerReadACValueIndex", #Log_Error)
      ProcedureReturn #noPowerReadACValueIndex
    EndIf
    If Not PowerReadDCValueIndex
      WriteToLog("_initPowrProfFunctions() - Error, can't find function PowerReadDCValueIndex", #Log_Error)
      ProcedureReturn #noPowerReadDCValueIndex
    EndIf
    If Not IsPwrSuspendAllowed Or Not IsPwrHibernateAllowed Or Not IsPwrShutdownAllowed
      WriteToLog("_initPowrProfFunctions() - Error, can't find function IsPwrHibernateAllowed or IsPwrShutdownAllowed", #Log_Error)
      ProcedureReturn #noReadPowerOffModes
    EndIf
    If Not SetSuspendState
      WriteToLog("_initPowrProfFunctions() - Error, can't find function SetSuspendState", #Log_Error)
      ProcedureReturn #noSetSuspendState
    EndIf
    
    ProcedureReturn #success
    
  EndProcedure
  
  Procedure.l _initUser32Functions()
    
    Global hUser32
    
    hUser32 = OpenLibrary(#PB_Any, "user32.dll")
    If Not hUser32
      WriteToLog("_initUser32Functions() - Error, couldn't open user32.dll", #Log_Error)
      ProcedureReturn #noLib_User32
    EndIf
    
    Global RegisterPowerSettingNotification.Proto_RegisterPowerSettingNotification
    Global UnregisterPowerSettingNotification.Proto_UnregisterPowerSettingNotification
    ;     Global ShutdownBlockReasonCreate.Proto_ShutdownBlockReasonCreate
    ;     Global ShutdownBlockReasonDestroy.Proto_ShutdownBlockReasonDestroy
    Global SendInput.Proto_SendInput
    RegisterPowerSettingNotification    = GetFunction(hUser32, "RegisterPowerSettingNotification")
    UnregisterPowerSettingNotification  = GetFunction(hUser32, "UnregisterPowerSettingNotification")
    ;     ShutdownBlockReasonCreate           = GetFunction(user32Lib, "ShutdownBlockReasonCreate")
    ;     ShutdownBlockReasonDestroy          = GetFunction(user32Lib, "ShutdownBlockReasonDestroy")
    SendInput                           = GetFunction(hUser32, "SendInput")
    
    If Not RegisterPowerSettingNotification Or Not UnregisterPowerSettingNotification
      WriteToLog("_initUser32Functions() - Error, can't find function RegisterPowerSettingNotification or UnregisterPowerSettingNotification", #Log_Error)
      ProcedureReturn #noPowerManagementFound
    EndIf
    If Not SendInput
      WriteToLog("_initUser32Functions() - Error, can't find function SendInput", #Log_Error)
      ProcedureReturn #noSendInput
    EndIf
    
    ProcedureReturn #success
    
  EndProcedure
  
  Procedure _initGUID()
    
    Global.GUID videoSub, videoTime, sleepSub, sleepTime
    Global.GUID conDisplayState, awayMode
    Global.GUID schemePersonality, pwrSavePolicy
    
    ; Convert the GUID-strings to binary UUID/GUID structures as the Windows API requires.
    #GUID_VIDEO_SUBGROUP          = "{7516b95f-f776-4464-8c53-06167f40cc99}"
    #GUID_VIDEO_TIMEOUT           = "{3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e}"
    #GUID_SLEEP_SUBGROUP          = "{238c9fa8-0aad-41ed-83f4-97be242c8f20}"
    #GUID_SLEEP_TIMEOUT           = "{29f6c1db-86da-48c5-9fdb-f2b67b1f44da}"
    #GUID_CONSOLE_DISPLAY_STATE   = "{6FE69556-704A-47A0-8F24-C28D936FDA47}"
    #GUID_POWERSCHEME_PERSONALITY = "{245D8541-3943-4422-B025-13A784F679B7}"
    #GUID_POWER_SAVING_POLICY     = "{E73A048D-BF27-4F12-9731-8B207B9E1F62}"
    #GUID_SYSTEM_AWAYMODE         = "{98a7f580-01f7-48aa-9c0f-44352c29e5c0}"
    
    CLSIDFromString_(#GUID_VIDEO_SUBGROUP, videoSub)
    CLSIDFromString_(#GUID_VIDEO_TIMEOUT, videoTime)
    CLSIDFromString_(#GUID_SLEEP_SUBGROUP, sleepSub)
    CLSIDFromString_(#GUID_SLEEP_TIMEOUT, sleepTime)
    CLSIDFromString_(#GUID_CONSOLE_DISPLAY_STATE, conDisplayState)
    CLSIDFromString_(#GUID_POWERSCHEME_PERSONALITY, schemePersonality)
    CLSIDFromString_(#GUID_POWER_SAVING_POLICY, pwrSavePolicy)
    CLSIDFromString_(#GUID_SYSTEM_AWAYMODE, awayMode)
    
  EndProcedure
  
  Procedure.l _registerNotifications(window)
    
    Global hDisplayTimeoutNotify, hSleepTimeoutNotify
    Global hDisplayStateNotify, hPowerNotify
    Global hSchemeNotify, hPolicyNotify
    
    If Not IsWindow(window)
      ProcedureReturn #noWindow
    EndIf
    
    hDisplayTimeoutNotify = RegisterPowerSettingNotification(WindowID(window), @videoTime, 0)
    hSleepTimeoutNotify   = RegisterPowerSettingNotification(WindowID(window), @sleepTime, 0)
    hDisplayStateNotify   = RegisterPowerSettingNotification(WindowID(window), @conDisplayState, 0)
    hSchemeNotify         = RegisterPowerSettingNotification(WindowID(window), @schemePersonality, 0)
    hPolicyNotify         = RegisterPowerSettingNotification(WindowID(window), @pwrSavePolicy, 0)
    hPowerNotify          = RegisterPowerSettingNotification(WindowID(window), @awayMode, 0)
    
    If Not hDisplayTimeoutNotify Or Not hSleepTimeoutNotify Or Not hDisplayStateNotify Or Not hSchemeNotify Or Not hPolicyNotify Or Not hPowerNotify
      WriteToLog("_registerNotifications() - Error, can't initilize power pettings notifications", #Log_Error)
      ProcedureReturn #noPowerSettingsNotification
    EndIf
    
    ProcedureReturn #success
    
  EndProcedure
  ;> End Init
  
  Procedure.l GetModernPowerSettings(*pwrSettings.pwrScheme)
    
    Global *activeGUID = 0
    
    Protected powerSource.SYSTEM_POWER_STATUS
    
    ; Get current active power save scheme (like Balanced or High performance). To be able to read out timings later.
    If PowerGetActiveScheme(0, @*activeGUID) Or Not *activeGUID
      WriteToLog("GetModernPowerSettings() - Error, couldn't read active power save scheme", #Log_Error)
      ProcedureReturn #noPowerScheme
    EndIf
    
    ; Find out power source. If you check out the structure under powerSource, you can find some info on the battery (if included).
    If GetSystemPowerStatus_(@powerSource)
      
      If powerSource\ACLineStatus
        *pwrSettings\pwrSrc = #pwrSrcAC
      Else
        *pwrSettings\pwrSrc = #pwrSrcDC
      EndIf
      
    Else
      WriteToLog("GetModernPowerSettings() - Warning, can't evaluate power source - setting AC", #Log_Warning)
      *pwrSettings\pwrSrc = #pwrSrcAC
    EndIf
    
    ; Find out power down modes
    *pwrSettings\supportedPwrOffModes = #pwrOffSleep * IsPwrSuspendAllowed()
    *pwrSettings\supportedPwrOffModes + #pwrOffHibernate * IsPwrHibernateAllowed()
    *pwrSettings\supportedPwrOffModes + #pwrOffShutdown * IsPwrShutdownAllowed()
    
    ; Find out power down timings 
    If *pwrSettings\pwrSrc = #pwrSrcDC
      ; Get DC preferences
      PowerReadDCValueIndex(0, *activeGUID, videoSub, videoTime, *pwrSettings + OffsetOf(pwrScheme\displayOff_seconds))
      PowerReadDCValueIndex(0, *activeGUID, sleepSub, sleepTime, *pwrSettings + OffsetOf(pwrScheme\standby_seconds))
    Else
      ; Get AC preferences
      PowerReadACValueIndex(0, *activeGUID, videoSub, videoTime, *pwrSettings + OffsetOf(pwrScheme\displayOff_seconds))
      PowerReadACValueIndex(0, *activeGUID, sleepSub, sleepTime, *pwrSettings + OffsetOf(pwrScheme\standby_seconds))
    EndIf
    
    ProcedureReturn #success
    
  EndProcedure
  
  Declare     _startInputDetection(caller.s)
  Procedure.l GetPowerSettingChange(lParam, displayState.i)
    
    Protected *setting.POWERBROADCAST_SETTING
    
    *setting = lParam
    
    ; Check if the event has anything to do with the status of the display power.
    If CompareMemory(@*setting\powerSetting, @conDisplayState, SizeOf(GUID))
      CopyMemory(@*setting\dataBlock, @displayState, 4)
      
      Select displayState
        Case 0
          SM_TriggerInputEvent(#In_DisplayDeactivated)
          
        Case 1
          PostEvent(#Event_DisplayActivated)
          SM_TriggerInputEvent(#In_DisplayActivated)
          
        Case 2
          PostEvent(#Event_DisplayDimmed)
          SM_TriggerInputEvent(#In_DisplayDimmed)          
      EndSelect
      
      ProcedureReturn
    EndIf
    
    ; Check if the power button have been pressed.
    If CompareMemory(@*setting\powerSetting, @awayMode, SizeOf(GUID)) And PeekL(@*setting\dataBlock) = #True
      PostEvent(#Event_PowerButton)
      SM_TriggerInputEvent(#In_PowerButton)
      ProcedureReturn
    EndIf
    
    ; Check if the display timing has changed
    If CompareMemory(@*setting\powerSetting, @videoTime, SizeOf(GUID))
      PostEvent(#Event_DisplayTimeChanged)
      SM_TriggerInputEvent(#In_DisplayTimeChanged)
      ProcedureReturn
    EndIf
    
    ; Check if the power timing has changed
    If CompareMemory(@*setting\powerSetting, @sleepTime, SizeOf(GUID))
      PostEvent(#Event_SleepTimeChanged)
      SM_TriggerInputEvent(#In_SleepTimeChanged)
      ProcedureReturn
    EndIf
    
    ; Check if the power scheme type has changed
    If CompareMemory(@*setting\powerSetting, @schemePersonality, SizeOf(GUID))
      PostEvent(#Event_PowerSchemeChanged)
      SM_TriggerInputEvent(#In_PowerSchemeChanged)
      ProcedureReturn
    EndIf
    
    ; Check if the power policy has changed
    If CompareMemory(@*setting\powerSetting, @pwrSavePolicy, SizeOf(GUID))
      PostEvent(#Event_PowerPolicyChanged)
      SM_TriggerInputEvent(#In_PowerPolicyChanged)
      ProcedureReturn
    EndIf
    
    ProcedureReturn #Null
    
  EndProcedure
  
  Declare     _keyboardHookProc(nCode.l, wParam.i, lParam.i)
  Declare     _mouseHookProc(nCode.l, wParam.i, lParam.i)
  Procedure   _startInputDetection(caller.s)
    
    Global.i hInstance, hKeyHook, hMouseHook
    Global.l lastMouseX, lastMouseY
    
    Protected initialPos.POINT
    
    If hInstance
      WriteToLog("_startInputDetection() ignored. Already active!", #Log_Detail, caller)
      ProcedureReturn
    EndIf
    
    GetCursorPos_(@initialPos)
    lastMouseX = initialPos\x
    lastMouseY = initialPos\y 
    
    hInstance = GetModuleHandle_(#Null)
    hKeyHook   = SetWindowsHookEx_(#WH_KEYBOARD_LL, @_keyboardHookProc(), hInstance, 0)
    hMouseHook = SetWindowsHookEx_(#WH_MOUSE_LL, @_mouseHookProc(), hInstance, 0)
    
    If Not hKeyHook Or Not hMouseHook
      WriteToLog("_startInputDetection() - Error, couldn't hook to the inputs.", #Log_Error, caller)
      ProcedureReturn #noInputHooks
    EndIf
    WriteToLog("_startInputDetection()", #Log_Detail, caller)
    
  EndProcedure
  
  Procedure   _keyboardHookProc(nCode.l, wParam.i, lParam.i)
    
    Protected *kb.KBDLLHOOKSTRUCT = lParam
    
    If nCode >= 0
      If wParam = #WM_KEYDOWN Or wParam = #WM_SYSKEYDOWN
        PostEvent(#Event_InputHook, 0, 0, #EventType_KeyPressed, *kb\vkCode)
      EndIf
    EndIf
    
    ; to follow Windows principles, return the result from CallNextHookEx_
    ProcedureReturn CallNextHookEx_(hKeyHook, nCode, wParam, lParam)
    
  EndProcedure
  
  Procedure   _mouseHookProc(nCode.l, wParam.i, lParam.i)
    
    Protected   *mouse.MSLLHOOKSTRUCT
    Protected.i diffX, diffY, diffSum
    
    If nCode >= 0
      *mouse = lParam
      Select wParam
          
        Case #WM_MOUSEMOVE
          ; Calculate delta
          diffX = Abs(*mouse\pt\x - lastMouseX)
          diffY = Abs(*mouse\pt\y - lastMouseY)
          lastMouseX = *mouse\pt\x
          lastMouseY = *mouse\pt\y
          
          diffSum = diffX + diffY
          If diffSum > #filterDelta          
            PostEvent(#Event_InputHook, diffX, diffY, #EventType_MouseMoved, diffSum)
          Else
            PostEvent(#Event_InputHook, diffX, diffY, #EventType_MouseFiltered, diffSum)
          EndIf
        Default
          ; A mouse button.
          PostEvent(#Event_InputHook, 0, 0, #EventType_MButton, wParam)
          
      EndSelect
    EndIf
    
    ; to follow Windows principles, return the result from CallNextHookEx_
    ProcedureReturn CallNextHookEx_(hMouseHook, nCode, wParam, lParam)
    
  EndProcedure
  
  Procedure   _stopInputDetection(caller.s)
    
    If hKeyHook
      UnhookWindowsHookEx_(hKeyHook)
      hKeyHook = 0
    EndIf
    
    If hMouseHook
      UnhookWindowsHookEx_(hMouseHook)
      hMouseHook = 0
      WriteToLog("_stopInputDetection()", #Log_Detail, caller)
    Else
      WriteToLog("_stopInputDetection() Already stopped.", #Log_Detail, caller)
    EndIf
    
  EndProcedure
  
  Procedure.b SetComputerSuspendState(useHibernate.b = #False, force.b = #True, disableWake.b = #False)
    ; returns #null when failed
    WriteToLog("SetComputerSuspendState() - Going to power save.", #Log_Detail)
    ProcedureReturn SetSuspendState(useHibernate, force, disableWake)
  EndProcedure
  
  Procedure   JogMouse(caller.s)
    
    ; Moves mouse pointer to the left and the right (to break fake sleep state)
    
    Protected input.INPUT
    
    input\type = #INPUT_MOUSE
    input\mi\dwFlags = #MOUSEEVENTF_MOVE
    
    input\mi\dx = -10
    SendInput(1, @input, SizeOf(INPUT))
    Delay(50)
    
    WriteToLog("JogMouse()", #Log_Detail, caller)
    
    input\mi\dx = 10
    SendInput(1, @input, SizeOf(INPUT))
    
  EndProcedure
  
  Procedure   DisplayOff(caller.s)
    
    Shared displayTurnedOff, lastValidTickCount
    
    WriteToLog("DisplayOff()", #Log_Detail, caller)
    SendMessage_(#HWND_BROADCAST, #WM_SYSCOMMAND, #SC_MONITORPOWER, #MONITOR_OFF)
    lastValidTickCount = _getDwTime()
    _startInputDetection("DisplayOff")
    displayTurnedOff = #True
    
  EndProcedure
  
  Procedure   DisplayOn(caller.s)
    
    WriteToLog("DisplayOn()", #Log_Detail, caller)
    SendMessage_(#HWND_BROADCAST, #WM_SYSCOMMAND, #SC_MONITORPOWER, #MONITOR_ON)
    Delay(50)
    JogMouse("DisplayOn")
    
  EndProcedure
  
  Procedure   SuppressStandby(displayAlwaysOn.b)
    
    If displayAlwaysOn
      SetThreadExecutionState(#ES_SYSTEM_REQUIRED | #ES_AWAYMODE_REQUIRED | #ES_CONTINUOUS | #ES_DISPLAY_REQUIRED)
    Else
      SetThreadExecutionState(#ES_SYSTEM_REQUIRED | #ES_AWAYMODE_REQUIRED | #ES_CONTINUOUS)
    EndIf
    
  EndProcedure
  
  Procedure   AllowStandby(caller.s)
    SetThreadExecutionState(#ES_CONTINUOUS) 
    WriteToLog("AllowStandby(): Standby allowed (normal function).", #Log_Detail, caller)
  EndProcedure
  
  Procedure.q _getDwTime()
    
    Protected lii.LASTINPUTINFO
    
    lii\cbSize = SizeOf(LASTINPUTINFO)
    
    If GetLastInputInfo_(@lii)
      ProcedureReturn lii\dwTime
    EndIf
    
    ProcedureReturn 0 ; Landing here means that no idle time is measured and GetLastInputInfo_() failed.
    
  EndProcedure
  
  Procedure.q GetInputIdleTime()
    
    Shared lastValidTickCount, displayTurnedOff
    
    If displayTurnedOff
      ProcedureReturn GetTickCount_() - lastValidTickCount
    Else
      ProcedureReturn GetTickCount_() - _getDwTime()
    EndIf
    
  EndProcedure
  
  Procedure   HookEventHandler(thisEvent.i)
    
    Shared lastValidTickCount, displayTurnedOff
    
    If thisEvent <> #Event_InputHook
      ProcedureReturn
    EndIf
    
    ; Don't do anything to manipulate the idle time while the display is still on. This should not happen, or at least, not very often.
    If Not displayTurnedOff
      _stopInputDetection("HookEventHandler() - Since Display is on, turning the hooks off.")
      WriteToLog("HookEventHandler() - hook event while display is on. Skipping.", #Log_Detail)
      ProcedureReturn
    EndIf
    
    If EventType() = #EventType_MouseFiltered 
      If ElapsedMilliseconds() - eventFloodFilter > #floodBorder
        WriteToLog("HookEventHandler() - Mouse move " + Str(EventData()) + " pixels filtered.", #Log_Detail)
      EndIf
    Else
      SM_TriggerInputEvent(#In_InputHook)
      WriteToLog("HookEventHandler() - Real input. Lighting up display.", #Log_Detail)
      displayTurnedOff = #False ; latest added
      lastValidTickCount = GetTickCount_()
    EndIf
    
  EndProcedure
  
  Procedure.l PS_Free()
    
    Shared hUser32, hPowrProf
    
    UnregisterPowerSettingNotification(hDisplayTimeoutNotify)
    UnregisterPowerSettingNotification(hSleepTimeoutNotify)
    UnregisterPowerSettingNotification(hDisplayStateNotify)
    UnregisterPowerSettingNotification(hSchemeNotify)
    UnregisterPowerSettingNotification(hPolicyNotify)
    UnregisterPowerSettingNotification(hPowerNotify)
    LocalFree_(*activeGUID)
    CloseLibrary(hkernel32)
    CloseLibrary(hUser32)
    CloseLibrary(hPowrProf)
    
    ProcedureReturn #success
    
  EndProcedure
  
  ; Abstraction Procedures for Timer events 
  Procedure   Init()
    
    Protected checkPowerScheme
    
    checkPowerScheme = PS_Init(0)
    If checkPowerScheme
      WriteToLog("Error setting up power settings reading. See PowerSchemes for translation of code " + Str(checkPowerScheme), #Log_Error)
      End
    EndIf
    checkPowerScheme = GetModernPowerSettings(@currentPowerSettings)
    If checkPowerScheme
      WriteToLog("Error getting power settings. See PowerSchemes for translation of code " + Str(checkPowerScheme), #Log_Error)
      End
    EndIf
    
    SuppressStandby(forceDisplayOn)
    WriteToLog("SuppressStandby(): Standby mode disabled.", #Log_Detail)
    
    WriteToLog("Registration successful! Waiting for system timer...", #Log_Detail)
    
    If currentPowerSettings\pwrSrc
      powerSource$ = "(AC)"
    Else
      powerSource$ = "(DC)"
    EndIf
    currentPowerSettings\overrideDisplayOff_seconds = #overrideInactive
    currentPowerSettings\overrideStandby_seconds    = #overrideInactive
    WriteToLog("Timeouts [seconds]: Display " + TicksToString(currentPowerSettings\displayOff_seconds) +
               " Computer " + TicksToString(currentPowerSettings\standby_seconds) + " Power source " + powerSource$, #Log_Detail)
    
    SetWindowCallback(DPSE::@t_WinCallback(), 0)

  EndProcedure
  
  Procedure   TimerEventHandler(thisEvent.i)
    
    Protected lastEvent.l, lastTime.q, remainingTime.q
    
    If thisEvent = lastEvent And ElapsedMilliseconds() - lastTime < 50
      ProcedureReturn
    Else
      lastEvent = thisEvent
      lastTime = ElapsedMilliseconds()
    EndIf
    
    If currentPowerSettings\pwrSrc = #pwrSrcAC
      powerSource$ = "(AC)"
    Else
      powerSource$ = "(DC)"
    EndIf
    
    Select thisEvent
      Case #PB_Event_Timer
        
        Select EventTimer()
          Case 1 ; Display time out
            If ValidateDisplayTimeout()
              NoDisplayOffTimer("MainLoop timer")
              SM_TriggerInputEvent(#In_TimeOutDisplay)
            Else
              StartDisplayOffTimer("MainLoop timer")
            EndIf
            
          Case 2 ; Standby time out
            If ValidatePowerTimeout()
              NoPowerOffTimer("MainLoop timer")
              SM_TriggerInputEvent(#In_TimeOutStandby)
            Else
              StartPowerOffTimer("MainLoop timer")
            EndIf
            
          Case 3 ; Permit task to run again
            RemoveWindowTimer(0, 3)
            SM_TriggerInputEvent(#In_TimeOutTaskCoolOff)
        EndSelect
        
      Case #Event_PowerButton
;         NoDisplayOffTimer("MainLoop PB")
;         NoPowerOffTimer("MainLoop PB")
        
      Case #Event_DisplayTimeChanged
        GetModernPowerSettings(@currentPowerSettings)
        WriteToLog("SCHEDULE Event: Display time was modified. Timeouts [seconds]:" +
                   " Display " + TicksToString(currentPowerSettings\displayOff_seconds) +
                   " Power source " + powerSource$, #Log_Detail)
        currentPowerSettings\overrideDisplayOff_seconds = #overrideInactive ; reset override
        StartDisplayOffTimer("MainLoop P8")
        
      Case #Event_SleepTimeChanged
        GetModernPowerSettings(@currentPowerSettings)
        WriteToLog("SCHEDULE Event: Power down time was modified. Timeouts [seconds]:" +
                   " Computer " + TicksToString(currentPowerSettings\standby_seconds) +
                   " Power source " + powerSource$, #Log_Detail)
        currentPowerSettings\overrideStandby_seconds = #overrideInactive ; reset override
        StartPowerOffTimer("MainLoop P8")
          
      Case #Event_PowerSchemeChanged
        GetModernPowerSettings(@currentPowerSettings)
        WriteToLog("SCHEDULE Event: Power scheme was modified.", #Log_Detail)
        
      Case #Event_PowerPolicyChanged
        WriteToLog("SCHEDULE Event: Power policy changed - HOW?", #Log_Detail)
          
      Case #Event_DisplayActivated
        StartDisplayOffTimer("MainLoop E1")
        StartPowerOffTimer("MainLoop E1")
        
      Case #Event_SystemResume
        StartDisplayOffTimer("MainLoop Resume")
        StartPowerOffTimer("MainLoop Resume")
        
      Case #Event_System_powerDown
        WriteToLog("POWER: System is going to sleep.", #Log_Detail) ; not sure I ever get this event.
        
      Case #Event_UserLogOff
        WriteToLog("POWER: User is logging off.", #Log_Detail)
        
      Case #Event_SystemShutDown
        WriteToLog("POWER: System shutdown or reboot detected.", #Log_Detail)
        
      Case #Event_extTaskDone
        SM_TriggerInputEvent(#In_extTaskDone)
        AddWindowTimer(0, 3, #taskCoolDownTicks)
        
      Case #Event_extTempDisplayOffTimer
        currentPowerSettings\overrideDisplayOff_seconds = EventData()
        
        If currentPowerSettings\overrideDisplayOff_seconds = #overrideInactive
          WriteToLog("POWER: Display original scheme.", #Log_Detail)
        Else
          WriteToLog("POWER: Override display off - value: " + TicksToString(currentPowerSettings\overrideDisplayOff_seconds), #Log_Detail)
        EndIf
        
      Case #Event_extTempPowerOffTimer
        currentPowerSettings\overrideStandby_seconds = EventData()
        WriteToLog("POWER: Override standby - value: " + Str(currentPowerSettings\overrideStandby_seconds), #Log_Detail)
        
    EndSelect
      
  EndProcedure
  
  Procedure   SignalTaskToExecute(caller.s)
    
    WriteToLog("SignalTaskToExecute(): Starting...", #Log_Detail, caller)
    PostEvent(#Event_extRunTask)
    
  EndProcedure
  
  Procedure.b   PowerDown(caller.s)
    
    ; Returns True if the power down was successful
    
    Static turnOffCoolDown.q
    Protected result.l = #True ; set to not fail even if a power down setting wasn't found.
    Protected _powerDownTicks.q
    
    If caller <> "MainLoop PB"
      If ElapsedMilliseconds() - turnOffCoolDown < #_powerDownCoolDownTicks And ElapsedMilliseconds() > #_powerDownCoolDownTicks
        WriteToLog("(PowerDown(): Ignored - Cool down not finished.)", #Log_Info, caller)
        turnOffCoolDown = ElapsedMilliseconds()
        ProcedureReturn #False
      Else
        WriteToLog("PowerDown(): Trying to power down computer", #Log_Detail, caller)
      EndIf
    Else
      WriteToLog("PowerDown(): Entering a user induced power down", #Log_Detail, caller)
    EndIf
    
    AllowStandby("PowerDown")
    
    JogMouse("PowerDown")
    Delay(50)
    
    ; Tries to power down in order Standby, Hibernation. If none exists, nothing happens except for a message in the log.
    _powerDownTicks = ElapsedMilliseconds()
    If currentPowerSettings\supportedPwrOffModes & #pwrOffSleep
      Debug "Trying to sleep"
      result = SetComputerSuspendState()
    ElseIf currentPowerSettings\supportedPwrOffModes & #pwrOffHibernate
      Debug "Trying to hibernate"
      result = SetComputerSuspendState(#True)
    ElseIf currentPowerSettings\supportedPwrOffModes & #pwrOffShutdown
      WriteToLog("(PowerDown(): Ignored - No support for shut down right now. Will not power down.", #Log_Warning, caller)
    Else
      WriteToLog("(PowerDown(): Ignored - Can't find power down method. Will not power down.", #Log_Warning, caller)
    EndIf
    ; Did the function for power down fail?
    If Not result
      WriteToLog("(PowerDown(): Power down Failed by reason unknown!)", #Log_Warning, caller)
    Else
      ; Was it a real power down?
      If ElapsedMilliseconds() - _powerDownTicks < 2000
        WriteToLog("(PowerDown(): An attempt was made to power down, but it failed.)", #Log_Warning, caller)
        ProcedureReturn #False
      EndIf
    EndIf
    
    turnOffCoolDown = ElapsedMilliseconds()
    SuppressStandby(forceDisplayOn)
    WriteToLog("SuppressStandby(): Standby mode disabled.", #Log_Detail, "PowerDown()")  
    
    ProcedureReturn #True
    
  EndProcedure
  
  Procedure.l GetRemainingTime(target.l)
    
    Protected reference.q
    
    Select target
      Case #GRT_Display
        If currentPowerSettings\overrideDisplayOff_seconds = #overrideInactive
          reference = currentPowerSettings\displayOff_seconds
        Else
          reference = currentPowerSettings\overrideDisplayOff_seconds
        EndIf
      Case #GRT_Computer
        If currentPowerSettings\overrideStandby_seconds = #overrideInactive
          reference = currentPowerSettings\standby_seconds
        Else
          reference = currentPowerSettings\overrideStandby_seconds
        EndIf
    EndSelect
    
    If Not reference ; meaning always on
      ProcedureReturn #maxDelayChunkTicks ; Don't give back zero. That will trigger power down events.
    EndIf
    
    reference * 1000 ; convert to ms.
    ProcedureReturn reference - GetInputIdleTime() ; return what time is left to count down.
    
  EndProcedure
  
  Procedure   StartDisplayOffTimer(caller.s)
    
    Protected ticksDelayDisplay = GetRemainingTime(#GRT_Display)
    
    If ticksDelayDisplay > 1
      AddWindowTimer(0, 1, ticksDelayDisplay)
      WriteToLog("StartDisplayOffTimer(): Setting display off to " + Str(ticksDelayDisplay / 1000) + " seconds.", #Log_Detail, caller)
    Else
      WriteToLog("(StartDisplayOffTimer(): Display timer set fail: Glitching display on or a power button press?)", #Log_Detail, caller)
      NoDisplayOffTimer("StartDisplayOffTimer()")
    EndIf
    
  EndProcedure
  
  Procedure   StartPowerOffTimer(caller.s)  
    
    Protected ticksDelayPower = GetRemainingTime(#GRT_Computer)
    
    If ticksDelayPower > 1
      AddWindowTimer(0, 2, ticksDelayPower)
      WriteToLog("StartPowerOffTimer(): Setting standby to " + Str(ticksDelayPower / 1000) + " seconds", #Log_Detail, caller)
    Else
      WriteToLog("(StartPowerOffTimer(): Standby timer set failed: The remote possibilty happened! Note what you did and please report.)", #Log_Detail, caller)
      NoPowerOffTimer("StartPowerOffTimer()")
    EndIf
    
  EndProcedure
  
  Procedure   NoDisplayOffTimer(caller.s)
    
    RemoveWindowTimer(0, 1)
    WriteToLog("NoDisplayOffTimer(): Timer turned off for display.", #Log_Detail, caller)
    
  EndProcedure
  
  Procedure   NoPowerOffTimer(caller.s)
    
    RemoveWindowTimer(0, 2)
    WriteToLog("NoPowerOffTimer(): Timer turned off for standby.", #Log_Detail, caller)
    
  EndProcedure
  
  Procedure.b ValidateDisplayTimeout()
    
    If GetRemainingTime(#GRT_Display) <= 0 
      ProcedureReturn #True
    Else
      ProcedureReturn #False
    EndIf
    
  EndProcedure
  
  Procedure.b ValidatePowerTimeout()
    
    If GetRemainingTime(#GRT_Computer) <= 0
      ProcedureReturn #True
    Else
      ProcedureReturn #False
    EndIf
    
  EndProcedure
  
  Procedure   t_WinCallback(hWnd.i, uMsg.i, wParam.i, lParam.i)
    
    If uMsg = #WM_POWERBROADCAST
      
      Select wParam
        Case #PBT_POWERSETTINGCHANGE
          ; Examine the exact power event
          GetPowerSettingChange(lParam, displayState)
          
        Case #PBT_APMRESUMESUSPEND
          PostEvent(#Event_SystemResume) ; System Resume/Wake
          SM_TriggerInputEvent(#In_SystemResume)
          
        Case #PBT_APMSUSPEND
          PostEvent(#Event_System_powerDown) ; System Entering Sleep/Hibernation
          SM_TriggerInputEvent(#In_System_powerDown)
          
      EndSelect
      
    ; Handle Shutdown, Reboot and Logoff
    ElseIf uMsg = #WM_QUERYENDSESSION
      ; lParam contains flags. If $80000000 (ENDSESSION_CLOSEAPP) is NOT set, it's a real shutdown/logoff.
      ; Windows does not easily separate Reboot from Shutdown here, but we can detect Logoff.
      If lParam = $80000000 ; #ENDSESSION_LOGOFF
        PostEvent(#Event_UserLogOff) ; User Logging Off
        SM_TriggerInputEvent(#In_UserLogOff)
      Else
        PostEvent(#Event_SystemShutDown) ; Full Shutdown or Reboot
        SM_TriggerInputEvent(#In_SystemShutDown)
      EndIf
      
      ProcedureReturn #True
      
    EndIf
    
    ProcedureReturn #PB_ProcessPureBasicEvents
    
  EndProcedure

  Procedure.s TicksToString(ticks.q)
    If ticks
      ProcedureReturn Str(ticks)
    Else
      ProcedureReturn "∞"
    EndIf
  EndProcedure
  
  Procedure   CleanUp()
    
    WriteToLog("Cleaning up and exiting", #Log_Detail)
    
    SetWindowCallback(0, 0)
    AllowStandby("CleanUp")
    PS_Free()
    WriteToLog("End session", #Log_System)
    WriteToLog("", #Log_System)
    
  EndProcedure
  
EndModule

; IDE Options = PureBasic 6.40 (Windows - x64)
; CursorPosition = 405
; FirstLine = 331
; CursorPosition = 3
; Folding = H8----8--
; Markers = 365
; EnableXP
; DPIAware
; Compiler = PureBasic 6.40 - C Backend (Windows - x64)