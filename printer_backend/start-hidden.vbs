' RetailPOS Print Helper - Hidden Starter
' This script starts the print server without showing a window

Set WshShell = CreateObject("WScript.Shell")
WshShell.CurrentDirectory = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
WshShell.Run "cmd /c node server.js", 0, False
