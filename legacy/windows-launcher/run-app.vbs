' Silent launcher for Reactive Resume offline desktop package.
' Double-click this file (or a shortcut to it) to start the app with no
' CMD / PowerShell flash. Pair the desktop shortcut with "Run as administrator"
' so launch-resume.ps1 can start/stop the PostgreSQL Windows service.
'
' WindowStyle 0 = hidden. Third argument False = do not wait (lifecycle is
' owned by launch-resume.ps1 which waits on the browser window).

Option Explicit

Dim shell, fso, scriptDir, ps1, cmd
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = scriptDir & "\launch-resume.ps1"

If Not fso.FileExists(ps1) Then
  MsgBox "launch-resume.ps1 not found next to run-app.vbs:" & vbCrLf & ps1, vbCritical, "Reactive Resume"
  WScript.Quit 1
End If

' -NoProfile avoids loading a profile that can flash UI or alter PATH unexpectedly.
' -ExecutionPolicy Bypass applies only to this invocation.
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & ps1 & """"
shell.Run cmd, 0, False
