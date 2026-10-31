; ==============================================================================
; Module LookUp GUI
; PureBasic 6.40 - Windows 10
; © 2026 Peter Bergström - Licensed under the MIT License
; ==============================================================================

CompilerIf #PB_Compiler_IsMainFile
  
  IncludeFile "Module-NetworkTools.pbi"
  
CompilerEndIf

DeclareModule LookUpGUI
  
  Structure lookUpData
    netData.NetworkTools::scan
    index.l   ; chosen index from devices()
    chosenIP.s
    chosenMAC.s
    chosenName.s
  EndStructure
  
  Declare   Collect(*lookUp.lookUpData)
  Declare.b IsRunning() ; Checks if the thread has closed down and returns #True if still running, else #False.
  
EndDeclareModule

Module LookUpGUI
  
  EnableExplicit
  
  IncludeFile "Form-SyncthingLookUp.pbf"
  
  Global ip.s, mac.s, name.s
  Global scanThread.i
  
  Declare   _lookUpWinEvents(event, *lookUp.lookUpData)
  Declare   _stopScanNet(*lookUp.lookUpData)
  Procedure Collect(*lookUp.lookUpData)
    
    Protected.i lastListSize
    
    With *lookUp
      
      If \netData = 0
        Debug "Zero pointer for netData"
        End
      EndIf
      
      \netData\sharedMutex = CreateMutex()
      NetworkTools::debugValue = \netData\sharedMutex
      scanThread = CreateThread(NetworkTools::@ScanNet(), \netData)
      If Left(\netData\errorMsg, 1) = "1" Or Left(\netData\errorMsg, 1) = "7"
        Debug "Error, cancelling LookUp: " + \netData\errorMsg
      EndIf  
      
      OpenlookUpWin()
      StickyWindow(lookUpWin, #True)
      
      While _lookUpWinEvents(WaitWindowEvent(1), *lookUp)
        
        LockMutex(\netData\sharedMutex)
        Protected currentSize = ListSize(\netData\devices())
        Protected hasItems = #False
        
        If currentSize > lastListSize
          PushListPosition(\netData\devices())
          While currentSize > lastListSize
            SelectElement(\netData\devices(), lastListSize)
            If \netData\devices()\lookUpName = ""
              Continue
            EndIf
            AddGadgetItem(lst_lu, lastListSize, \netData\devices()\ip$ + #LF$ +
                                                \netData\devices()\mac$ + #LF$ +
                                                \netData\devices()\lookUpName , 0)
            lastListSize + 1
          Wend
          PopListPosition(\netData\devices())
        EndIf
        
        If currentSize > 0
          hasItems = #True
        EndIf
        UnlockMutex(\netData\sharedMutex)
        
        If Not IsThread(scanThread) And GetGadgetText(txt_luStatus) = "Scanning..."
          If Not hasItems
            SetGadgetText(txt_luStatus, "Nothing found.")
          Else
            SetGadgetText(txt_luStatus, "Finished.")
          EndIf
        EndIf
      Wend
      
      If \index >= 0
        LockMutex(\netData\sharedMutex)
        If \index < ListSize(\netData\devices())
          SelectElement(\netData\devices(), \index)
          \chosenIP   = \netData\devices()\ip$
          \chosenMAC  = \netData\devices()\mac$
          \chosenName = \netData\devices()\lookUpName
        EndIf
        UnlockMutex(\netData\sharedMutex)
      EndIf
      
      CloseWindow(lookUpWin)
      If \netData\errorMsg > ""
        Debug "LookUp warning: " + \netData\errorMsg
      EndIf
      
      _stopScanNet(*lookUp)
      
    EndWith
  EndProcedure
  
  Procedure   _lookUpWinEvents(event, *lookUp.lookUpData)
    
    If event = #PB_Event_CloseWindow
      ProcedureReturn #False
    EndIf
    
    If event <> #PB_Event_Gadget
      ProcedureReturn #True
    EndIf
    
    Select EventGadget()
      Case lst_lu, btn_luSelect
        If (EventType() = #PB_EventType_LeftDoubleClick Or event = btn_luSelect) And GetGadgetState(lst_lu) >= 0
          *lookUp\index = GetGadgetState(lst_lu)          
          ProcedureReturn #False
        EndIf
        
      Case btn_luCancel
        ProcedureReturn #False
    EndSelect
    
    ProcedureReturn #True
    
  EndProcedure
  
  Procedure   _stopScanNet(*lookUp.lookUpData)
    
    *lookUp\netData\quitScan = #True
    If IsThread(scanThread)
      WaitThread(scanThread)
    EndIf
    Debug "Killing Mutex"
    FreeMutex(*lookUp\netData\sharedMutex)
    
  EndProcedure
  
  Procedure.b IsRunning()
    
    If IsThread(scanThread)
      ProcedureReturn #True
    EndIf
    
    ProcedureReturn #False
    
  EndProcedure
  
EndModule

CompilerIf #PB_Compiler_IsMainFile
  
  Define lookUp.LookUpGUI::lookUpData
  lookUp\netData\subNet$ = "192.168.1"
  lookUp\netData\scanStart = 1
  lookUp\netData\scanLast  = 254
  LookUpGUI::Collect(lookUp)
  
  While LookUpGUI::IsRunning()
    Delay(100)
  Wend
  Debug lookUp\index
  
CompilerEndIf

; IDE Options = PureBasic 6.40 (Windows - x64)
; Folding = v-
; EnableThread
; EnableXP
; DPIAware
; Compiler = PureBasic 6.40 - C Backend (Windows - x64)
; EnablePurifier