; Press F1 to execute this script

F1::
; Open new tab in Windows Terminal (or new window if none exists)
Run, wt.exe -w 0 nt

; Wait for terminal to open/new tab to load
Sleep, 2000

; Type "clau" and press Enter
SendRaw, clau
Send, {Enter}

; Wait 5 seconds as requested
Sleep, 5000

; Type the gemini command
SendRaw, for the following task use gemini --yolo every step:     


Sleep, 10000
; Optionally press Enter (remove the semicolon below if you want it to auto-execute)
; Send, {Enter}
return

; Press Escape to exit the script
Esc::ExitApp
