; ShitCam import/module system
; import math        -> stdlib (already linked, no-op success)
; import "file.sc"  -> load+lex+parse+exec once (cache + circular detect)
; Paths compared as-given (CWD-relative). Import state table in BSS.

%define IMP_ENTRY_SIZE 16
%define IMP_ST_BUSY 1
%define IMP_ST_DONE 2

section .data
    imp_err_many    db "Error: too many imports (limit 64)", 13, 10, 0
    imp_err_circular db "Error: circular import detected for '", 0
    imp_err_circular2 db "'", 13, 10, 0
    imp_err_unknown db "Error: unknown module '", 0
    imp_err_unknown2 db "' (only stdlib 'math' or a .sc file path)", 13, 10, 0
    imp_mod_math    db "math", 0
    imp_ext_sc      db ".sc", 0

section .bss
    imp_count       resq 1
    imp_table       resb 1024    ; 64 * 16: [path ptr][state]

section .text

; ---------- imp_is_math(RSI=name) -> RAX 1/0 ----------
imp_is_math:
    mov rdi, imp_mod_math
    jmp streq

; ---------- imp_ends_sc(RSI=name) -> RAX 1/0 ----------
imp_ends_sc:
    push rbx
    call strlen                 ; rax = len
    cmp rax, 3
    jb .no
    mov rbx, rsi
    add rbx, rax
    sub rbx, 3
    mov eax, [rbx]              ; 3 bytes incl NUL? compare 3 chars: '.', 's', 'c'
    cmp ax, 0x732E              ; ".s" little-endian? '.'=0x2E, 's'=0x73 -> 0x732E
    jne .no
    cmp byte [rbx+2], 'c'
    jne .no
    mov eax, 1
    pop rbx
    ret
.no:
    xor eax, eax
    pop rbx
    ret

; ---------- imp_find(RSI=path) -> RAX index or -1 ----------
imp_find:
    push rbx
    push r12
    mov r12, rsi
    mov rcx, [imp_count]
    xor r8d, r8d
.loop:
    cmp r8, rcx
    jae .nf
    imul rbx, r8, IMP_ENTRY_SIZE
    lea rbx, [imp_table + rbx]
    mov rsi, [rbx]
    mov rdi, r12
    push r8
    push rcx
    call streq
    pop rcx
    pop r8
    test eax, eax
    jnz .found
    inc r8
    jmp .loop
.nf:
    mov rax, -1
    pop r12
    pop rbx
    ret
.found:
    mov rax, r8
    pop r12
    pop rbx
    ret

; ---------- imp_fatal_circular(RSI=path) / imp_fatal_unknown(RSI=path) ----------
imp_fatal_circular:
    push rsi
    lea rsi, [imp_err_circular]
    call print_cstr
    pop rsi
    push rsi
    call print_cstr
    lea rsi, [imp_err_circular2]
    call print_cstr
    pop rsi
    mov ecx, 1
    sub rsp, 0x28
    call ExitProcess

imp_fatal_unknown:
    push rsi
    lea rsi, [imp_err_unknown]
    call print_cstr
    pop rsi
    push rsi
    call print_cstr
    lea rsi, [imp_err_unknown2]
    call print_cstr
    pop rsi
    mov ecx, 1
    sub rsp, 0x28
    call ExitProcess

imp_fatal_many:
    lea rsi, [imp_err_many]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x28
    call ExitProcess

; ---------- interp_import_file(RSI=path): import with cache ----------
interp_import_file:
    push rbx
    push r12
    push r13
    mov r12, rsi
    call imp_is_math
    test eax, eax
    jnz .done_ok
    mov rsi, r12
    call imp_ends_sc
    test eax, eax
    jz .unknown
    mov rsi, r12
    call imp_find
    cmp rax, -1
    je .loadit
    ; found: check state
    imul rbx, rax, IMP_ENTRY_SIZE
    lea rbx, [imp_table + rbx]
    cmp qword [rbx+8], IMP_ST_DONE
    je .done_ok
    ; busy -> circular
    mov rsi, r12
    call imp_fatal_circular
.loadit:
    mov rax, [imp_count]
    cmp rax, SC_MAX_IMPORTS
    jae .many
    imul rbx, rax, IMP_ENTRY_SIZE
    lea rbx, [imp_table + rbx]
    mov [rbx], r12
    mov qword [rbx+8], IMP_ST_BUSY
    inc qword [imp_count]
    mov rsi, r12
    call load_file             ; RSI=buf, RDX=size (fatal on error)
    mov rbx, rsi
    mov r13, rdx
    mov rsi, r12
    mov rdx, rbx
    mov rcx, r13
    call lexer_init
    call lexer_run
    call parser_run
    mov rbx, [parser_root]
    mov rax, rbx
    call interp_exec
    ; mark done
    mov rsi, r12
    call imp_find
    imul rbx, rax, IMP_ENTRY_SIZE
    lea rbx, [imp_table + rbx]
    mov qword [rbx+8], IMP_ST_DONE
.done_ok:
    pop r13
    pop r12
    pop rbx
    ret
.unknown:
    mov rsi, r12
    call imp_fatal_unknown
.many:
    call imp_fatal_many
