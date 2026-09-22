; ShitCam - Windows API imports (kernel32 only, no CRT)
; NASM win64: extern <func> + link against kernel32.lib

extern GetStdHandle
extern GetCommandLineA
extern WriteFile
extern ReadFile
extern CreateFileA
extern CloseHandle
extern GetFileSizeEx
extern VirtualAlloc
extern VirtualFree
extern ExitProcess
extern HeapCreate
extern HeapAlloc
extern HeapFree
extern GetProcessHeap
extern MultiByteToWideChar
extern GetLastError
extern GetModuleFileNameA
extern CreateProcessA
extern WaitForSingleObject
extern GetExitCodeProcess
extern DeleteFileA
extern RtlMoveMemory
extern Sleep
extern GetTickCount64
extern Beep
extern LoadLibraryA
extern GetProcAddress
extern GetFileAttributesA
extern CreateDirectoryA
extern GetEnvironmentVariableA
extern SetEnvironmentVariableA
extern SetConsoleTextAttribute
extern GlobalAlloc
extern GlobalLock
extern GlobalUnlock
