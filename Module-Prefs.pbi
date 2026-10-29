; ============================================================================================
; Prefs module
; PureBasic 6.40 - Windows 10+
; © 2026 Peter Bergström - all rights reserved
; ============================================================================================
; Features:
; • Maintains a very simple preferences file that only contains keys (no groups).
; • A map, key(), is used to hold all keys with their values (strings).
; • The main program can find which ever preference needed in the map by calling the key name.
; • Any *new* preference is just added to the map and will be saved when calling Set(). And of
;   course, loaded next time Get() is called.
; • Returns error messages as strings on the format "error code" + "-" + "clear text".
;   In this way you can extract the error code with 
;   Val(returnMessage.s)
;   but also get the full explanation of the error.
;   Please don't use a programName that begins with a numeric, that might be confusing for
;   your error checking routine, if you don't take special measures for it.
;
; Bonus feature:
; • Since this module where to find out its own place for the prefs file, the algorithm to
;   make up the full name was moved to an own procedure, MakeFileName(), that can be used to
;   create other file names as well.
; ============================================================================================

DeclareModule Prefs
  
  ; roaming means settings can be shared between computers with the same account. (depending on you network capabilities)
  ; local (standard) is individual for each user and computer.
  Declare.s Get(programName.s, roaming.b = #False) ; Reads/creates
  Declare.s Set()                                  ; Writes/updates
  Declare.s MakeFileName(programName.s, extension.s, roaming.b = #False)
  
  Global NewMap key.s()
  
EndDeclareModule

Module Prefs
  
  EnableExplicit
  
  Prototype.l proto_CLSIDFromString(*lpsz, *pclsid)
  Prototype.l proto_SHGetKnownFolderPath(*rfid, dwFlags.l, hToken.i, *ppszPath)
  Prototype   proto_CoTaskMemFree(*pv)
  
  ; change the company name to your own needs. By using a "company" name, all your software folders will be available in one folder.
  #prefsCompany = "pTb" ; the prefs will be in a \subfolder\subfolder\file called \#prefsCompany\programName\programName.prefs
  
  #GUID_Roaming = "{3EB685DB-65F9-4CF6-A03A-E3EF65729F3D}"
  #GUID_Local   = "{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}"
  
  Declare.s _getWindowsFolder(guidString.s)
  Procedure.s Get(programName.s, roaming.b = #False)
    
    Global fullName.s ; folder.s
    
    fullName = MakeFileName(programName, ".prefs")
    
    If FileSize(fullName) > -1
      OpenPreferences(fullName)
    Else
      If Not CreatePreferences(fullName)
        ProcedureReturn "6-Can't create prefs file - " + fullName
        End
      EndIf
    EndIf
    
    ExaminePreferenceKeys()
    While NextPreferenceKey()
      key(PreferenceKeyName()) = PreferenceKeyValue()
    Wend
    ClosePreferences()
    
  EndProcedure
  
  Procedure.s Set()
    
    If fullName = #Null$
      ProcedureReturn "7-No place to save the preferences. Have you called Get() before?"
    EndIf
    
    If Not OpenPreferences(fullName)
      ProcedureReturn "8-Can't open prefs file - " + fullName
    EndIf
    
    ; Save prefs
    ForEach key()
      WritePreferenceString(MapKey(key()), key())
    Next
    ClosePreferences()
    
  EndProcedure
  
  Procedure.s MakeFileName(programName.s, extension.s, roaming.b = #False)
    
    Protected.s folder, myFullName, name = programName
    
    ; Select system folder.
    If roaming 
      folder = _getWindowsFolder(#GUID_Roaming)
    Else
      folder = _getWindowsFolder(#GUID_Local)
    EndIf
    folder + "\"
    
    ; Create company folder if needed.
    If FileSize(folder + #prefsCompany) > -1
      ProcedureReturn "1-" + #prefsCompany + " seem to be occupied in " + folder
    ElseIf FileSize(folder + #prefsCompany) = -1 And CreateDirectory(folder + #prefsCompany) = 0
      ProcedureReturn "2-Can't create directory " + #prefsCompany + " in " + folder
    EndIf
    folder + #prefsCompany + "\" ; extend path
    
    ; Create program folder if needed.
    If FileSize(folder + name) > -1
      ProcedureReturn "3-" + name + " seem to be occupied in " + folder
    ElseIf FileSize(folder + name) = -1 And CreateDirectory(folder + name) = 0
      ProcedureReturn "4-Can't create directory " + name + " in " + folder
    EndIf
    folder + name + "\" ; extend path
    If extension <> "" And Left(extension, 1) <> "."
      extension = "." + extension
    EndIf
    
    ; Be sure it's not a directory.
    myFullName = folder + name + extension
    If FileSize(myFullName) = -2
      ProcedureReturn "5-Not a file - " + myFullName
    EndIf
    
    ProcedureReturn myFullName
    
  EndProcedure

  Procedure.s _getWindowsFolder(guidString.s)
    
    ; Looks for the path of this users Local or Roaming folder.
    
    Protected path.s = ""
    Protected ole32, shell32
    Protected CLSIDFromString.Proto_CLSIDFromString
    Protected SHGetKnownFolderPath.Proto_SHGetKnownFolderPath
    Protected CoTaskMemFree.Proto_CoTaskMemFree
    Protected folderGUID.GUID
    Protected *pPath = 0
    
    ole32   = OpenLibrary(#PB_Any, "ole32.dll")
    shell32 = OpenLibrary(#PB_Any, "shell32.dll")
    If Not ole32 Or Not shell32
      ProcedureReturn
    EndIf
    
    CLSIDFromString      = GetFunction(ole32, "CLSIDFromString")
    SHGetKnownFolderPath = GetFunction(shell32, "SHGetKnownFolderPath")
    CoTaskMemFree        = GetFunction(ole32, "CoTaskMemFree")
    If Not CLSIDFromString Or Not SHGetKnownFolderPath Or Not CoTaskMemFree
      ProcedureReturn
    EndIf
    
    If CLSIDFromString(@GuidString, @FolderGUID) <> 0
      ProcedureReturn
    EndIf
    
    If SHGetKnownFolderPath(@FolderGUID, 0, 0, @*pPath) = 0 And *pPath
      path = PeekS(*pPath, -1, #PB_Unicode)
      CoTaskMemFree(*pPath) 
    EndIf
    
    CloseLibrary(ole32)
    CloseLibrary(shell32)
    
    ProcedureReturn path
    
  EndProcedure
  
EndModule
; IDE Options = PureBasic 6.40 (Windows - x64)
; CursorPosition = 35
; Folding = f-
; EnableXP
; DPIAware
; Compiler = PureBasic 6.40 - C Backend (Windows - x64)