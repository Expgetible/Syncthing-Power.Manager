; ==============================================================================
; Module Network Tools
; PureBasic 6.40 - Windows 10
; © 2026 Peter Bergström - Licensed under the MIT License
; ==============================================================================

; ScanNet() will take a while (20 seconds or more). But it can be started threaded if you need the time for other stuff.
;   The procedure should be fairly thread safe but if you need access to the sent structure before ScanNet is done,
;   you should use a mutex, just in case. Specially if you want to read the built in list of devices.
;   You can also limit how many IPs the scan should cover with scanStart and scanLast.

CompilerIf Not #PB_Compiler_Thread
  CompilerError "Module NetworkTools needs the thread safe option."
CompilerEndIf

DeclareModule NetworkTools
  
  Global debugValue
  
  Structure details
    mac$          
    ip$           
    lookUpName.s
  EndStructure
  
  Structure scan
    List devices.details()
    subNet$       ; like "10.0.0" or "10.0.0."
    scanStart.l   ; start address (min 1 and max 254)
    scanLast.l    ; last address to scan (scanStart and max 254)
    scanDone.b    ; #True = done, will be set when all is scanned. Will auto reset to zero when starting a scan.
    quitScan.b    ; Tells ScanNet to exit gracefully. There can be a delay since some windows calls can't be canceled.
    errorMsg.s    ; Will contain a string if an error occured.
    sharedMutex.i ; Use this mutex to interact with the list devices() while ScanNet is running.
    i.l           ; for internal use only
    ip.l          ; for internal use only
  EndStructure
  
  Declare   ScanNet(*netData.scan)              ; returns #false on fail and #true on success
  Declare.l WakeOnLAN(mac$, subNet$)
  Declare.i PingIP(targetIP$, timeOut.l = 1000)
  
EndDeclareModule

Module NetworkTools
  
  EnableExplicit
  
  Structure threadParam
    *netData.scan
    ipAddress.i
  EndStructure
  
  Global numThreads.l
  
  Declare.l _ipStringToAddress(ip$)
  Declare.s _getHostnameFromIP(destIP)
  Declare   _outputIPInfo(Array mac.a(1), *netData.scan)
  Declare   _ipScanThread(*param.threadParam)
  
  Prototype.i Proto_IcmpCreateFile()
  Prototype.i Proto_IcmpCloseHandle(InitHandle.i)
  Prototype.i Proto_IcmpSendEcho(IcmpHandle.i, DestinationAddress.l, RequestData.p-ascii, RequestSize.w, RequestOptions.i, ReplyBuffer.i, ReplySize.l, Timeout.l)
  Prototype.l Proto_SendARP(destIP.l, sourceIP.l, *macAddr, *phyAddrLen)
  
  Procedure.b _initARPFunction()
    
    Global hDll.i = OpenLibrary(#PB_Any, "iphlpapi.dll")
    If Not hDll 
      Debug "Failed to open library iphlpapi.dll"
      ProcedureReturn #False
    EndIf
    
    Global SendARP.Proto_SendARP = GetFunction(hDll, "SendARP")
    If Not SendARP
      Debug "Failed to init function SendARP"
      CloseLibrary(hDll)
      ProcedureReturn #False
    EndIf
    
    ProcedureReturn #True
    
  EndProcedure
  
  Procedure ScanNet(*netData.scan)
    
    ; Several error messages can be returned. Only the ARP fail will return a failure
    
    #maxSimultaneousIPScans = 300
    #startThreadDelay = 10
    
    If Not *netData\sharedMutex
      *netData\errorMsg = "1 - No mutex provided."
      ProcedureReturn
    EndIf
    
    *netData\scanDone = #False
    
    ; auto preset if both scanStart and scanLast is zero
    If *netData\scanStart = 0 And *netData\scanLast = 0
      *netData\scanStart = 1
      *netData\scanLast = 254
      *netData\errorMsg = "2 - Scan area is preset to 1-254."
    EndIf
    
    ; scanStart be min 1 and max 254.
    If *netData\scanStart > 254
      *netData\scanStart = 254
      *netData\errorMsg = "5 - Overflow in scanStart. Preset to 254."
    ElseIf *netData\scanStart < 1
      *netData\scanStart = 1
      *netData\errorMsg = "6 - Underflow in scanStart. Preset to 1."
    EndIf
    
    ; scanLast must be min scanStart and max 254
    If *netData\scanLast > 254
      *netData\scanLast = 254
      *netData\errorMsg = "3 - Overflow in scanLast. Preset to 254."
    ElseIf *netData\scanLast < *netData\scanStart
      *netData\scanLast = *netData\scanStart
      *netData\errorMsg = "4 - Underflow in scanLast. Preset to scanStart."
    EndIf
    
    If Right(*netData\subNet$, 1) <> "."
      *netData\subNet$ + "."
    EndIf
    
    Dim allThreads(254)
    
    If Not _initARPFunction()
      *netData\errorMsg = "7 - Couldn't initiate the ARP function."
      ProcedureReturn
    EndIf
    
    ; send all requests by threading, but with a delay and maximum simultaneous requests
    *netData\i = *netData\scanStart
    Repeat
      Protected *param.threadParam = AllocateMemory(SizeOf(threadParam))
      *param\netData = *netData
      *param\ipAddress = _ipStringToAddress(*netData\subNet$ + Str(*netData\i))
      
      allThreads(*netData\i) = CreateThread(@_ipScanThread(), *param)
      *netData\i + 1
      
      LockMutex(*netData\sharedMutex)
      numThreads + 1
      UnlockMutex(*netData\sharedMutex)
      
      Repeat
        Delay(#startThreadDelay)
      Until numThreads < #maxSimultaneousIPScans Or *netData\quitScan
    Until *netData\i > *netData\scanLast Or *netData\quitScan
    
    ; Wait for the last threads to finnish before quiting
    *netData\i = *netData\scanStart
    While *netData\i <= *netData\scanLast
      If IsThread(allThreads(*netData\i))
        WaitThread(allThreads(*netData\i))
      EndIf
      *netData\i + 1
    Wend
    
    CloseLibrary(hDll)
    *netData\scanDone = #True
    ProcedureReturn
    
  EndProcedure
  
  Procedure.l _ipStringToAddress(ip$)
    
    Protected destIP
    
    destIP = MakeIPAddress(Val(StringField(ip$, 1, ".")), 
                           Val(StringField(ip$, 2, ".")), 
                           Val(StringField(ip$, 3, ".")), 
                           Val(StringField(ip$, 4, ".")))
    
    ProcedureReturn destIP
    
  EndProcedure
  
  Procedure _ipScanThread(*param.ThreadParam)
    
    Protected *netData.scan = *param\netData
    Protected destIP = *param\ipAddress
    FreeMemory(*param)
    
    Protected macLen.l = 6
    Protected Dim macAddr.a(6)
    Protected lookUpName.s
    
    macLen = 6
    FillMemory(@macAddr(0), 6, 0)
    
    If SendARP(destIP, 0, @macAddr(0), @macLen) = 0
      lookUpName = _getHostnameFromIP(destIP)
      
      LockMutex(*netData\sharedMutex)
      AddElement(*netData\devices())
      *netData\devices()\ip$ = IPString(destIP)
      *netData\devices()\lookUpName = lookUpName
      
      _outputIPInfo(macAddr(), *netData)
      UnlockMutex(*netData\sharedMutex)
    EndIf
    
    LockMutex(*netData\sharedMutex)
    numThreads - 1
    UnlockMutex(*netData\sharedMutex)
    
  EndProcedure
  
  Procedure.s _getHostnameFromIP(destIP)
    
    Protected sa.sockaddr_in
    Protected *hostNameBuffer
    Protected result.l
    Protected hostName.s
    
    sa\sin_family = 2 ; #AF_INET (IPv4)
    
    sa\sin_addr = destIP
    *hostNameBuffer = AllocateMemory(256)
    
    If *hostNameBuffer
      result = getnameinfo_(@sa, SizeOf(sockaddr_in), *hostNameBuffer, 256, #Null, 0, 1) ; NI_NAMEREQD = 1
      
      If result = 0
        hostName = PeekS(*hostNameBuffer, -1, #PB_Ascii)
      EndIf
      
      FreeMemory(*hostNameBuffer)
    EndIf
    
    If hostName = "" Or hostName = IPString(destIP)
      hostName = "'unknown'"
    EndIf
    
    ProcedureReturn hostName
    
  EndProcedure
  
  Procedure _outputIPInfo(Array mac.a(1), *netData.scan)
    
    *netData\devices()\mac$ = RSet(Hex(mac(0) & $FF), 2, "0") + ":" +
                              RSet(Hex(mac(1) & $FF), 2, "0") + ":" +
                              RSet(Hex(mac(2) & $FF), 2, "0") + ":" +
                              RSet(Hex(mac(3) & $FF), 2, "0") + ":" +
                              RSet(Hex(mac(4) & $FF), 2, "0") + ":" +
                              RSet(Hex(mac(5) & $FF), 2, "0")
    
    Debug LSet(*netData\devices()\ip$, 15) + " | " + *netData\devices()\mac$ + " | " + *netData\devices()\lookUpName
    
  EndProcedure
  
  Declare   _macToAddress(mac$, *macAddr.sMac)
  Procedure.l WakeOnLAN(mac$, subNet$)
    
    #macRowLength = 6
    #macRows = 16
    
    Structure sMac
      indirectChar.a[ #macRowLength ]
    EndStructure
    Structure sMagic
      indirectChar.a[ (#macRows + 1) * #macRowLength ]
    EndStructure
    
    Protected macAddress.sMac
    Protected magicPacket.sMagic
    Protected char.l, row.l
    Protected connectionID.i
    Protected success.l
    
    If Len(mac$) <> 17
      Debug "Error: Faulty MAC address"
      ProcedureReturn #False
    EndIf
    
    If CountString(subNet$, ".") = 2
      subNet$ + ".255"
    EndIf
    If StringField(subNet$, 4, ".") = ""
      subNet$ + "255"
    EndIf
    
    connectionID = OpenNetworkConnection(subNet$, 9, #PB_Network_UDP) ; port 9 is standard, can be 7 sometimes according to the internet
    If Not connectionID
      Debug "Error: Couldn't open a network connection to " + subNet$
      ProcedureReturn #False
    EndIf
    
    _macToAddress(mac$, macAddress)
    
    ; Build the Magic Packet (6x $FF followed by 16x MAC)
    For char = 0 To #macRowLength - 1 ; this is row zero
      magicPacket\indirectChar[ char ] = $FF
    Next char
    For row = 1 To #macRows
      For char = 0 To #macRowLength - 1
        magicPacket\indirectChar[ (row * #macRowLength) + char ] = macAddress\indirectChar[ char ]
      Next char
    Next row
    
    If SendNetworkData(connectionID, @magicPacket, SizeOf(sMagic)) = SizeOf(sMagic)
      success = #True
    EndIf
    
    ; Stäng anslutningen
    CloseNetworkConnection(connectionID)
    
    ProcedureReturn success
    
  EndProcedure
  
  Procedure   _macToAddress(mac$, *macAddr.sMac)
    
    Protected i.l
    
    mac$ = ReplaceString(mac$, "-", ":")
    
    For i = 0 To #macRowLength - 1
      *macAddr\indirectChar[ i ] = Val("$" + StringField(mac$, i + 1, ":"))
    Next i
    
  EndProcedure
  
  Procedure.i PingIP(targetIP$, timeOut.l = 1000)
    
    Protected.l ip, pingTime.l = -1
    Protected.i iphlp, hIcmp
    Protected   IcmpCreateFile.Proto_IcmpCreateFile
    Protected   IcmpCloseHandle.Proto_IcmpCloseHandle
    Protected   IcmpSendEcho.Proto_IcmpSendEcho
    Protected   sendData.s
    Protected.i replySize, echoes
    Protected   *replyBuffer, *reply.ICMP_ECHO_REPLY
    
    iphlp = OpenLibrary(#PB_Any, "iphlpapi.dll")
    If Not iphlp : Goto ExitNow : EndIf
    
    IcmpCreateFile  = GetFunction(iphlp, "IcmpCreateFile")
    IcmpCloseHandle = GetFunction(iphlp, "IcmpCloseHandle")
    IcmpSendEcho    = GetFunction(iphlp, "IcmpSendEcho")
    If Not IcmpCreateFile Or Not IcmpCloseHandle Or Not IcmpSendEcho : Goto ExitNow : EndIf
    
    hIcmp = IcmpCreateFile()
    If Not hIcmp : Goto ExitNow : EndIf
    
    ip = MakeIPAddress(Val(StringField(targetIP$, 1, ".")), 
                       Val(StringField(targetIP$, 2, ".")), 
                       Val(StringField(targetIP$, 3, ".")), 
                       Val(StringField(targetIP$, 4, ".")))
    
    sendData = "Module NetworkTools PingData"
    replySize = SizeOf(ICMP_ECHO_REPLY) + Len(sendData)
    
    *replyBuffer = AllocateMemory(replySize)
    If Not *replyBuffer : Goto ExitNow : EndIf
    
    echoes = IcmpSendEcho(hIcmp, ip, sendData, Len(sendData), #Null, *replyBuffer, replySize, timeOut)
    If echoes <= 0 : Goto ExitNow : EndIf
    
    *reply.ICMP_ECHO_REPLY = *replyBuffer
    If *reply\Status = 0 ; 0 means IP_SUCCESS
      pingTime = *reply\RoundTripTime
    EndIf
    
    ; -----------------------
    ExitNow:
    
    If *replyBuffer
      FreeMemory(*replyBuffer)
    EndIf
    If hIcmp
      IcmpCloseHandle(hIcmp)
    EndIf
    If iphlp
      CloseLibrary(iphlp)
    EndIf
    
    ProcedureReturn pingTime
    
  EndProcedure
  
EndModule

CompilerIf #PB_Compiler_IsMainFile
  
  #run_Ping     = 1
  #run_WOL      = 2
  #run_ScanNet  = 3
  
  runTest.l = #run_ScanNet
  Select runTest
      
    Case #run_Ping
      testIP$ = "192.168.1.1"
      resultingTime = NetworkTools::PingIP(testIP$)
      If resultingTime = -1
        Debug "No contact with " + testIP$
      Else
        Debug "Response time " + Str(resultingTime) + " ms."
      EndIf
      
    Case #run_WOL
      success =  NetworkTools::WakeOnLAN("28:D2:44:3B:8C:2A", "192.168.1.255")
      If success
        Debug "Packet successfully sent."
      Else
        Debug "Error, couldn't send the complete packet."
      EndIf
      
    Case #run_ScanNet
      Define netData.NetworkTools::scan
      netData\subNet$ = "192.168.1"
      ElapsedMilliseconds()
      netData\sharedMutex = CreateMutex()
      Define myThread = CreateThread(NetworkTools::@ScanNet(), netData)
      WaitThread(myThread)
      If netData\errorMsg
        Debug netData\errorMsg
      EndIf
      Debug ""
      Debug "Time to scan: " + Str(ElapsedMilliseconds())
      Debug ""
      
  EndSelect
  
CompilerEndIf

; IDE Options = PureBasic 6.40 (Windows - x64)
; CursorPosition = 3
; Folding = ----
; EnableThread
; EnableXP
; DPIAware
; Compiler = PureBasic 6.40 - C Backend (Windows - x64)