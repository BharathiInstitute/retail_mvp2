' RetailPOS Print Helper - VBScript Launcher
' This script starts the Node.js server completely hidden (no window)

Option Explicit

Dim WshShell, fso, scriptDir, nodeExe, serverJs, port

Set WshShell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Get the directory where this script is located
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)

' Set paths
nodeExe = scriptDir & "\node\node.exe"
serverJs = scriptDir & "\server.js"
port = 5005

' Check if Node.js exists
If Not fso.FileExists(nodeExe) Then
    MsgBox "Error: Node.js not found at:" & vbCrLf & nodeExe & vbCrLf & vbCrLf & "Please reinstall the Print Helper.", vbCritical, "RetailPOS Print Helper"
    WScript.Quit 1
End If

' Check if server.js exists
If Not fso.FileExists(serverJs) Then
    MsgBox "Error: Server file not found at:" & vbCrLf & serverJs & vbCrLf & vbCrLf & "Please reinstall the Print Helper.", vbCritical, "RetailPOS Print Helper"
    WScript.Quit 1
End If

' Check if already running by trying to connect to the port
On Error Resume Next
Dim xmlhttp
Set xmlhttp = CreateObject("MSXML2.ServerXMLHTTP.6.0")
xmlhttp.setTimeouts 1000, 1000, 1000, 1000
xmlhttp.Open "GET", "http://localhost:" & port & "/health", False
xmlhttp.Send

If xmlhttp.Status = 200 Then
    ' Already running, exit silently
    WScript.Quit 0
End If
On Error GoTo 0

' Start Node.js server hidden via cmd.exe (0 = hidden window)
' Using cmd.exe /c ensures proper process detachment
WshShell.CurrentDirectory = scriptDir
WshShell.Run "cmd.exe /c cd /d """ & scriptDir & """ && """ & nodeExe & """ """ & serverJs & """", 0, False

WScript.Quit 0
