Run, wt.exe
WinWaitActive, ahk_exe wt.exe
Sleep, 1000
SendInput, clau{Enter}
Sleep, 5000
SendInput, /gemini-cli:ask-gemini
