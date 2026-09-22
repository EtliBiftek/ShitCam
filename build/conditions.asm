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
mov rax, 15
mov [sc_v0+8], rax
mov qword [sc_v0], 0
mov rax, [sc_v0+8]
push rax
mov rax, 10
mov rcx, rax
pop rax
cmp rax, rcx
setg al
movzx eax, al
test rax, rax
jz L0
lea rsi, [sc_s0]
call sc_print_str
jmp L1
L0:
lea rsi, [sc_s1]
call sc_print_str
L1:
mov rax, [sc_v0+8]
push rax
mov rax, 15
mov rcx, rax
pop rax
cmp rax, rcx
sete al
movzx eax, al
test rax, rax
jz L2
lea rsi, [sc_s2]
call sc_print_str
jmp L3
L2:
L3:
mov rax, [sc_v0+8]
push rax
mov rax, 10
mov rcx, rax
pop rax
cmp rax, rcx
setne al
movzx eax, al
test rax, rax
jz L4
lea rsi, [sc_s3]
call sc_print_str
jmp L5
L4:
L5:
xor ecx, ecx
sub rsp, 0x28
call ExitProcess
sc_write:
push rbx
sub rsp, 0x30
mov rcx, [sc_stdout]
mov r8, rdx
mov rdx, rsi
lea r9, [rsp+0x28]
mov qword [rsp+0x20], 0
call WriteFile
add rsp, 0x30
pop rbx
ret
sc_strlen:
xor eax, eax
.l: cmp byte [rsi+rax], 0
je .d
inc rax
jmp .l
.d: ret
sc_print_int:
push rbx
push r12
sub rsp, 0x28
mov rbx, rax
xor r12d, r12d
test rbx, rbx
jns .pos
neg rbx
inc r12d
.pos: lea rsi, [sc_numbuf+31]
mov byte [rsi], 0
mov rax, rbx
mov rcx, 10
test rax, rax
jnz .digits
dec rsi
mov byte [rsi], 48
jmp .out
.digits: xor edx, edx
div rcx
add dl, 48
dec rsi
mov [rsi], dl
test rax, rax
jnz .digits
.out: test r12d, r12d
jz .nodash
dec rsi
mov byte [rsi], 45
.nodash: lea rdx, [sc_numbuf+31]
sub rdx, rsi
call sc_write
add rsp, 0x28
pop r12
pop rbx
ret
sc_print_str:
push rsi
call sc_strlen
mov rdx, rax
pop rsi
jmp sc_write
sc_print_sp:
lea rsi, [sc_space]
mov rdx, 1
jmp sc_write
sc_print_nl:
lea rsi, [sc_crlf]
mov rdx, 2
jmp sc_write
sc_div_zero:
sub rsp, 0x28
lea rsi, [sc_divmsg]
call sc_print_str
mov ecx, 1
call ExitProcess
section .data
sc_s0 db 108,97,114,103,101, 0
sc_s1 db 115,109,97,108,108, 0
sc_s2 db 102,105,102,116,101,101,110, 0
sc_s3 db 110,111,116,32,116,101,110, 0
section .bss
sc_v0 resq 2
