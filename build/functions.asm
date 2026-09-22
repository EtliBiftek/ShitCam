default rel
bits 64
section .data
sc_space db 32, 0
sc_crlf db 13, 10, 0
sc_divmsg db 68, 105, 118, 105, 115, 105, 111, 110, 32, 98, 121, 32, 122, 101, 114, 111, 13, 10, 0
section .bss
sc_stdout resq 1
sc_numbuf resb 32
section .text
extern GetStdHandle, WriteFile, ExitProcess
global main
main:
sub rsp, 0x28
mov ecx, -11
call GetStdHandle
mov [sc_stdout], rax
add rsp, 0x28
