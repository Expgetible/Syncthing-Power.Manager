; ==============================================================================
; Procedure Write to log
; PureBasic 6.40 - Windows 10+
; © 2026 Peter Bergström - all rights reserved
; ==============================================================================
;< Features:
; • Time stamp with date.
;
; • Back tracing. By putting in the current procedure in the message the routine
;   can also put in a caller (which is the routine that called said procedure).
;
CompilerIf #PB_Compiler_IsMainFile
;   Example:
  Procedure Proc2(caller.s)
    ; doing something
    WriteToLog("Proc2() - Something is done.", caller)
  EndProcedure

  Procedure Proc1(caller.s)
    Proc2("Proc1")
    ; doing stuff but found something wrong
    Protected someError = #True
    If someError
      WriteToLog("Proc1() - didn't do it right.", caller)
    EndIf
  EndProcedure
  
  Define logFileName.s = GetPathPart(ProgramFilename()) + "Your name of choice"
  Proc1("Main")
  End
CompilerEndIf
;
;   The "()" will be replaced with "( From CallingRoutine ). That means you can
;   see that Proc1 delivered the message on demand from Proc2. Of course
;   you can omit caller by sending "", or also omit executing routine.
;
;   But if your string doesn't have "()" no caller will be inserted.
;
; • Writes files up to a certain size of the log and then renames it to the
;   first in a sequence. The sequence is 1 to #log_MaxSeq
;   plus the current log file without any sequence number. Oldest file is the 
;   one with the highest sequence number.
;
; • Keeps the sequence to a certain number of files (so the hard drive doesn't
;   fill up with lots and lots of log files.
; ==============================================================================
; Insert these two lines in your code to start using WriteToLog():
;   Define logFileName.s = ; GetPathPart(ProgramFilename()) + "Your name of choice" or any other choice.
;   IncludeFile("yourPath\WriteToLog.pbi")
; Don't add an extension to the filename. '.log' will be added automatically.
;>

#log_DateFormat = "[%yyyy-%mm-%dd %hh:%ii:%ss"
#TargetPrecision = 1000000
  
Dim logLevelName.s(#LogEndOfLevels - 1)
logLevelName(#Log_System)   = ""
logLevelName(#Log_Error)    = " Error: "
logLevelName(#Log_Warning)  = " Warning: "
logLevelName(#Log_Info)     = " Info: "
logLevelName(#Log_Detail)   = " Detail: "

Structure timeData
  currentDate.q
  currentTicks.q
  ticksDiff.q
  dateFormated.s 
  diffFormated.s
  lastDate.q
  lastTicks.q
  counter.q
  frequency.q
  dateGap.q
EndStructure

Declare GetTime()

Global myTimer.timeData

QueryPerformanceFrequency_(@myTimer\frequency)
QueryPerformanceCounter_(@myTimer\counter)
myTimer\dateGap = Date() - Int(myTimer\counter / myTimer\frequency)

Procedure.l WriteToLog(message.s, level.l, caller.s = "")
  
  #log_ext = ".log"
  #log_MaxSize = 250000
  #log_MaxSeq = 50
  
  Shared logFileName, logLevel, logLevelName()
  Protected log$, myFile.i, sequence.l
  Static lastDate
  
  ; Only log entries low enough, but never fail.
  If logLevel >= #LogEndOfLevels
    logLevel = #LogEndOfLevels - 1
  EndIf
  If level > logLevel
    ProcedureReturn #True
  EndIf
  
  ; Time to switch log file?
  If FileSize(logFileName + #log_ext) > #log_MaxSize
    
    ; if the sequence is full, erase the oldest one (highest number)
    If FileSize(logFileName + "-" + Str(#log_MaxSeq) + #log_ext) >= 0
      DeleteFile(logFileName + "-" + Str(#log_MaxSeq) + #log_ext)
    EndIf
    
    ; rename sequence upwards from top and down.
    For sequence = #log_MaxSeq To 2 Step -1
      If FileSize(logFileName + "-" + Str(sequence - 1) + #log_ext) >= 0
        RenameFile(logFileName + "-" + Str(sequence - 1) + #log_ext, logFileName + "-" + Str(sequence) + #log_ext)
      EndIf
    Next
    
    ; now rename the log to first in sequence, so we can create a new one.
    RenameFile(logFileName + #log_ext, logFileName + "-" + Str(1) + #log_ext)
    
  EndIf
  
  ; Add a caller, if given. Tracks who called/caused an event.
  If message > ""
    If caller > #Null$
      caller = "( From " + caller + " )"
      message = ReplaceString(message, "()", caller)
    EndIf
    
    ; Put together the final log message.
    GetTime()
    If myTimer\ticksDiff > #TargetPrecision / 2
      log$ = #CRLF$ + myTimer\dateFormated
    Else
      log$ = myTimer\dateFormated + myTimer\diffFormated
    EndIf
    log$ + logLevelName(level) + message
  EndIf
  
  ; Open the/a file.
  myFile = OpenFile(#PB_Any, logFileName + #log_ext)
  If Not myFile
    ProcedureReturn #False
  EndIf
  
  ; Write log data.
  FileSeek(myFile, Lof(myFile))
  WriteStringN(myFile, log$)
  Debug log$
  CloseFile(myFile)
  
  ProcedureReturn #True
  
EndProcedure

Procedure GetTime()
  
  Protected seconds.q, fractionScaled.q
  Protected datePart$, fractionPart$
  
  ; Get current time and date down to 1/myTimer\frequency second
  QueryPerformanceCounter_(@myTimer\counter)
  seconds = myTimer\counter / myTimer\frequency
  myTimer\currentDate = myTimer\dateGap + seconds
  myTimer\currentTicks = myTimer\counter - (seconds * myTimer\frequency)
  fractionScaled = (myTimer\currentTicks * #TargetPrecision) / myTimer\frequency
  
  ; Get the time difference since last called GetTime (in 1/myTimer\frequency s)
  myTimer\ticksDiff = myTimer\currentDate - myTimer\lastDate
  myTimer\ticksDiff * #TargetPrecision
  myTimer\ticksDiff + myTimer\currentTicks - myTimer\lastTicks
  
  ; Format the date strings
  myTimer\dateFormated = FormatDate(#log_DateFormat, myTimer\currentDate) +
                         "." +
                         RSet(Str(fractionScaled), Len(Str(#TargetPrecision)) - 1, "0") +
                         "] "
  myTimer\diffFormated = "[+" + RSet(Str(myTimer\ticksDiff), Len(Str(#TargetPrecision)) - 1, "0") + " µs] "
  
  ; Remember time and date from this call
  myTimer\lastDate = myTimer\currentDate
  myTimer\lastTicks = myTimer\currentTicks
  
EndProcedure


; IDE Options = PureBasic 6.40 (Windows - x64)
; CursorPosition = 175
; FirstLine = 34
; Folding = d-
; EnableXP
; DPIAware
; Compiler = PureBasic 6.40 - C Backend (Windows - x64)