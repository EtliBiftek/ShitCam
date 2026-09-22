; ShitCam - x86-64 NASM, Windows x64 ABI, PE/COFF console, kernel32 only.
; Entry: main (linked with /ENTRY:main). No CRT.
; Calling convention: RCX,RDX,R8,R9 + 32-byte shadow space, stack 16-aligned.
; Callee-saved: RBX,RBP,RDI,RSI,R12-R15 preserved across calls.
;
; Register contract in this file:
;   RSI = string pointer (print helpers)
;   RDX = length where needed
;   RBX = stdout handle (cached after init, never clobbered across calls)

default rel
bits 64

%include "include/shitcam.inc"
%include "include/winapi.inc"
%include "src/lexer.asm"
%include "src/parser.asm"
%include "src/runtime.asm"
%include "src/interp.asm"
%include "src/import.asm"
%include "src/compiler.asm"
%include "build/cfg.inc"

section .data
    ver_str      db "ShitCam 0.1.0 (x86-64 NASM, Windows)", 13, 10, 0
    usage_str    db "Usage:", 13, 10
                 db "  shitcam hello.sc        Run a script (interpreter)", 13, 10
                 db "  shitcam run hello.sc    Same as above", 13, 10
                 db "  shitcam repl            Interactive REPL", 13, 10
                 db "  shitcam build hello.sc  Build native executable", 13, 10
                 db "  shitcam --version       Print version", 13, 10
                 db "  shitcam --help          Print this help", 13, 10, 0
    banner_str   db "ShitCam REPL 0.1.0 (type 'exit' to quit)", 13, 10, 0
    prompt_str   db "> ", 0
    nl_str       db 13, 10, 0
    run_pre      db "Running ", 0
    run_mid      db " (", 0
    run_suf      db " bytes)", 13, 10, 0
    build_pre    db "Building ", 0
    build_suf    db " -> <name>.exe", 13, 10, 0
    err_noarg    db "Error: no input file. Usage: shitcam hello.sc", 13, 10, 0
    err_open     db "Error: cannot open file '", 0
    err_open_suf db "'", 13, 10, 0
    err_big      db "Error: file too large (max 16 MB)", 13, 10, 0
    err_mem      db "Error: out of memory", 13, 10, 0
    err_build    db "Error: build needs a .sc file argument", 13, 10, 0
    s_version    db "--version", 0
    s_help       db "--help", 0
    s_h          db "-h", 0
    s_repl       db "repl", 0
    s_build      db "build", 0
    s_run        db "run", 0
    s_exit       db "exit", 0
    s_lextest    db "lextest", 0
    s_parsetest  db "parsetest", 0
    s_replecho   db "--repl-echo", 0
    repl_tmpname db SC_REPL_TMP
    repl_runarg  db " --repl-echo ", 0
    repl_outname db "shitcam_repl_out.txt", 0
    repl_quote   db '"', 0
    repl_cont    db ">> ", 0
    repl_trans_full db "Error: REPL history full (1 MB), restart repl", 13, 10, 0

section .bss
    stdout_handle resq 1
    stdin_handle  resq 1
    g_argc        resq 1
    g_argv        resq SC_MAX_ARGS
    g_script_arg_start resq 1
    numbuf        resb 32
    readbuf       resb SC_MAX_LINE
    repl_trans    resb SC_REPL_TRANS_MAX
    repl_trans_len resq 1
    repl_cur_len  resq 1
    repl_logic_len resq 1
    repl_eof      resq 1
    repl_prompt   resq 1          ; 1="> " 2=">> "
    repl_cmd      resb 2048
    repl_exe      resb SC_MAX_PATH
    repl_shown    resq 1
    repl_echo     resq 1

section .text
global main

; ---------- strlen(RSI) -> RAX ----------
strlen:
    xor eax, eax
.len_loop:
    cmp byte [rsi + rax], 0
    je .done
    inc rax
    jmp .len_loop
.done:
    ret

; ---------- print_bytes(RSI=ptr, RDX=len) ----------
; NOTE: lpNumberOfBytesWritten targets our own frame, never a saved register.
print_bytes:
    push rbx
    sub rsp, 0x30
    mov rcx, [stdout_handle]
    mov r8, rdx
    mov rdx, rsi
    lea r9, [rsp + 0x28]
    mov qword [rsp + 0x20], 0
    call WriteFile
    add rsp, 0x30
    pop rbx
    ret

; ---------- print_cstr(RSI) ----------
print_cstr:
    push rsi
    call strlen
    mov rdx, rax
    pop rsi
    jmp print_bytes

; ---------- print_u64(RAX) ----------
print_u64:
    lea rsi, [numbuf + 31]
    mov byte [rsi], 0
    mov rcx, 10
    test rax, rax
    jnz .digits
    dec rsi
    mov byte [rsi], '0'
    jmp .out
.digits:
    xor rdx, rdx
    div rcx
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rax, rax
    jnz .digits
.out:
    jmp print_cstr

; ---------- streq(RSI=a, RDI=b) -> RAX 1/0 ----------
streq:
    xor eax, eax
.cmp_loop:
    mov cl, [rsi]
    mov dl, [rdi]
    cmp cl, dl
    jne .no
    test cl, cl
    jz .yes
    inc rsi
    inc rdi
    jmp .cmp_loop
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; ---------- starts_with_exit(RSI) -> RAX 1/0 (for REPL quit) ----------
is_exit_cmd:
    push rsi
    mov rdi, s_exit
    call streq
    ret

; ---------- parse_args: splits GetCommandLineA buffer in place ----------
; Fills g_argc/g_argv. Skips argv[0] handling to caller. Returns RAX=argc.
parse_args:
    push rbx
    push rsi
    push rdi
    push r12
    sub rsp, 0x28
    call GetCommandLineA
    add rsp, 0x28
    mov rsi, rax                 ; cursor
    xor r12d, r12d               ; argc
.skip_ws:
    mov al, [rsi]
    test al, al
    jz .finish
    cmp al, ' '
    je .ws_next
    cmp al, 9
    je .ws_next
    jmp .token
.ws_next:
    inc rsi
    jmp .skip_ws
.token:
    cmp r12, SC_MAX_ARGS
    jae .finish
    cmp byte [rsi], '"'
    je .quoted
    mov [g_argv + r12*8], rsi
    inc r12
.scan:
    mov al, [rsi]
    test al, al
    jz .finish
    cmp al, ' '
    je .term
    cmp al, 9
    je .term
    inc rsi
    jmp .scan
.term:
    mov byte [rsi], 0
    inc rsi
    jmp .skip_ws
.quoted:
    inc rsi
    mov [g_argv + r12*8], rsi
    inc r12
.qscan:
    mov al, [rsi]
    test al, al
    jz .finish
    cmp al, '"'
    je .qterm
    inc rsi
    jmp .qscan
.qterm:
    mov byte [rsi], 0
    inc rsi
    jmp .skip_ws
.finish:
    mov [g_argc], r12
    mov rax, r12
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

; ---------- load_file(RSI=path) -> RSI=buffer, RDX=size ----------
; Fatal errors print + ExitProcess(1). Buffer is NUL-terminated.
load_file:
    push rbx
    push r12
    push r13
    mov r12, rsi                       ; path
    sub rsp, 0x40
    mov rcx, r12
    mov rdx, GENERIC_READ
    mov r8, FILE_SHARE_READ
    mov r9, 0
    mov qword [rsp + 0x20], OPEN_EXISTING
    mov qword [rsp + 0x28], 0
    mov qword [rsp + 0x30], 0
    call CreateFileA
    cmp rax, INVALID_HANDLE_VALUE
    je .open_err
    mov rbx, rax
    mov rcx, rbx
    lea rdx, [rsp + 0x18]
    mov qword [rsp + 0x18], 0
    call GetFileSizeEx
    test eax, eax
    jz .open_err_close
    mov r13, [rsp + 0x18]
    cmp r13, SC_MAX_FILE
    ja .too_big
    xor ecx, ecx
    lea rdx, [r13 + 1]
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_READWRITE
    call VirtualAlloc
    test rax, rax
    jz .oom
    mov rsi, rax
    mov rcx, rbx
    mov rdx, rsi
    mov r8, r13
    lea r9, [rsp + 0x10]
    mov qword [rsp + 0x20], 0
    call ReadFile
    mov byte [rsi + r13], 0
    mov rcx, rbx
    call CloseHandle
    mov rdx, r13
    add rsp, 0x40
    pop r13
    pop r12
    pop rbx
    ret
.open_err:
    add rsp, 0x40
    lea rsi, [err_open]
    call print_cstr
    mov rsi, r12
    call print_cstr
    lea rsi, [err_open_suf]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x20
    call ExitProcess
.open_err_close:
    mov rcx, rbx
    call CloseHandle
    add rsp, 0x40
    lea rsi, [err_open]
    call print_cstr
    mov rsi, r12
    call print_cstr
    lea rsi, [err_open_suf]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x20
    call ExitProcess
.too_big:
    mov rcx, rbx
    call CloseHandle
    add rsp, 0x40
    lea rsi, [err_big]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x20
    call ExitProcess
.oom:
    mov rcx, rbx
    call CloseHandle
    add rsp, 0x40
    lea rsi, [err_mem]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x20
    call ExitProcess

; ---------- run_file(RSI=path): open, read, report. Phase1+ executes. ----------
run_file:
    push rbx
    push r12
    push r13
    mov r12, rsi                       ; path
    call load_file                     ; RSI=buf, RDX=size
    mov rbx, rsi
    mov r13, rdx
    mov rsi, r12                       ; path
    mov rdx, rbx                       ; buf
    mov rcx, r13                       ; size
    call lexer_init
    call lexer_run
    call parser_run
    mov rbx, [parser_root]
    call interp_init_once
    mov rax, rbx
    call interp_exec
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

; ---------- lextest_file(RSI=path): lex + dump tokens ----------
lextest_file:
    push rbx
    push r12
    push r13
    mov r12, rsi                       ; path
    call load_file                     ; RSI=buf, RDX=size
    mov rbx, rsi
    mov r13, rdx
    mov rsi, r12                       ; path
    mov rdx, rbx                       ; buf
    mov rcx, r13                       ; size
    call lexer_init
    call lexer_run
    call lexer_dump
    pop r13
    pop r12
    pop rbx
    ret

; ---------- parsetest_file(RSI=path): lex + parse + dump ----------
parsetest_file:
    push rbx
    push r12
    push r13
    mov r12, rsi
    call load_file
    mov rbx, rsi
    mov r13, rdx
    mov rsi, r12
    mov rdx, rbx
    mov rcx, r13
    call lexer_init
    call lexer_run
    call parser_run
    call parser_dump
    pop r13
    pop r12
    pop rbx
    ret

; ---------- build_file(RSI=path): lex+parse+codegen+assemble+link ----------
build_file:
    push rbx
    push r12
    push r13
    mov r12, rsi
    call load_file
    mov rbx, rsi
    mov r13, rdx
    mov rsi, r12
    mov rdx, rbx
    mov rcx, r13
    call lexer_init
    call lexer_run
    call parser_run
    mov rsi, r12
    call compiler_run
    pop r13
    pop r12
    pop rbx
    ret

; ---------- repl_loop ----------
; Crash-safe REPL: keeps a cumulative transcript, evaluates it in a child
; process per input. Child failure rolls back; REPL itself never dies.
; Multiline: keeps reading while '{' count exceeds '}' count.
repl_loop:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 0x80                ; k=5 -> 40+128=168, aligned
    mov qword [repl_trans_len], 0
    lea rsi, [banner_str]
    call print_cstr
.next_input:
    mov qword [repl_cur_len], 0
    mov qword [repl_logic_len], 0
    mov qword [repl_prompt], 1
    jmp .read_more
.read_more:
    ; prompt only when actually reading
    cmp qword [repl_prompt], 1
    jne .prompt_cont
    lea rsi, [prompt_str]
    call print_cstr
    jmp .do_read
.prompt_cont:
    cmp qword [repl_prompt], 2
    jne .do_read
    lea rsi, [repl_cont]
    call print_cstr
.do_read:
    mov qword [repl_prompt], 0
    ; ReadFile(stdin, trans+trans_len+cur_len, remaining, &n, NULL)
    mov rcx, [stdin_handle]
    lea rdx, [repl_trans]
    add rdx, [repl_trans_len]
    add rdx, [repl_cur_len]
    mov rax, SC_MAX_LINE
    sub rax, [repl_cur_len]
    cmp rax, 2
    jle .trans_full
    mov r8, rax
    dec r8
    lea r9, [rsp+0x60]
    mov qword [rsp+0x60], 0
    mov qword [rsp+0x20], 0
    call ReadFile
    test eax, eax
    jz .eof
    mov rax, [rsp+0x60]
    test rax, rax
    jz .eof
    add [repl_cur_len], rax
    jmp .scan
.eof:
    cmp qword [repl_cur_len], 0
    je .quit
    ; flush partial with appended newline
    mov rax, [repl_trans_len]
    add rax, [repl_cur_len]
    cmp rax, SC_REPL_TRANS_MAX-1
    jae .quit
    lea rsi, [repl_trans]
    add rsi, [repl_trans_len]
    add rsi, [repl_cur_len]
    mov byte [rsi], 10
    inc qword [repl_cur_len]
    mov qword [repl_eof], 1
    jmp .scan
.scan:
    ; find '\n' in [base+logic .. base+cur)
    lea rsi, [repl_trans]
    add rsi, [repl_trans_len]
    mov rax, [repl_logic_len]
    lea rsi, [rsi+rax]
    mov rcx, [repl_cur_len]
    sub rcx, [repl_logic_len]
    xor eax, eax                  ; offset from search start
.find_nl:
    test rcx, rcx
    jz .no_nl
    cmp byte [rsi+rax], 10
    je .found_nl
    inc rax
    dec rcx
    jmp .find_nl
.no_nl:
    cmp qword [repl_eof], 1
    je .quit
    cmp qword [repl_logic_len], 0
    jne .prompt_cont2
    mov qword [repl_prompt], 1
    jmp .read_more
.prompt_cont2:
    mov qword [repl_prompt], 2
    jmp .read_more
.found_nl:
    ; L = logic + offset + 1 (candidate logical input length)
    mov rdx, [repl_logic_len]
    add rdx, rax
    inc rdx
    mov r13, rdx                  ; L in r13 (preserved across calls)
    cmp rdx, 5
    je .exit_maybe
    cmp rdx, 6
    jne .no_exit
    lea rsi, [repl_trans]
    add rsi, [repl_trans_len]
    mov eax, [rsi]
    cmp eax, 0x74697865          ; "exit"
    jne .no_exit
    cmp word [rsi+4], 0x0A0D     ; "\r\n"
    jne .no_exit
    jmp .quit
.exit_maybe:
    lea rsi, [repl_trans]
    add rsi, [repl_trans_len]
    mov eax, [rsi]
    cmp eax, 0x74697865          ; "exit"
    jne .no_exit
    cmp byte [rsi+4], 10
    jne .no_exit
    jmp .quit                     ; no stack garbage here
.no_exit:
    mov r13, rdx                  ; L in r13 (preserved across calls)
    ; brace balance over [base .. base+L)
    lea rsi, [repl_trans]
    add rsi, [repl_trans_len]
    mov rcx, r13                  ; L
    xor eax, eax
.bcount:
    test rcx, rcx
    jz .bcount_done
    mov dl, [rsi]
    cmp dl, '{'
    jne .not_open
    inc rax
    jmp .bnext
.not_open:
    cmp dl, '}'
    jne .bnext
    dec rax
.bnext:
    inc rsi
    dec rcx
    jmp .bcount
.bcount_done:
    test rax, rax
    jg .need_more_lines
    ; balanced: commit L bytes, evaluate (L already in r13, no pushes)
    mov rax, [repl_trans_len]
    add rax, r13
    cmp rax, SC_REPL_TRANS_MAX
    jae .trans_full
    mov [repl_trans_len], rax
    call repl_eval_trans          ; EAX = child exit code
    test eax, eax
    jnz .eval_failed
    ; success: remaining already in place (commit shifted base)
    sub [repl_cur_len], r13
    mov qword [repl_logic_len], 0
    mov qword [repl_prompt], 1
    jmp .scan
.eval_failed:
    sub [repl_trans_len], r13
    mov rax, [repl_cur_len]
    sub rax, r13                  ; remaining
    jz .fail_empty
    mov r8, rax                   ; len
    lea rcx, [repl_trans]
    add rcx, [repl_trans_len]     ; dst = rolled-back base
    lea rdx, [rcx+r13]            ; src = dst + L
    sub rsp, 0x20
    call RtlMoveMemory
    add rsp, 0x20
    sub [repl_cur_len], r13
    mov qword [repl_logic_len], 0
    mov qword [repl_prompt], 1
    jmp .scan
.fail_empty:
    sub [repl_cur_len], r13       ; cur = 0
    mov qword [repl_logic_len], 0
    mov qword [repl_prompt], 1
    jmp .scan
.need_more_lines:
    mov [repl_logic_len], r13     ; extend logical input
    mov qword [repl_prompt], 2
    jmp .scan
.trans_full:
    lea rsi, [repl_trans_full]
    call print_cstr
    mov qword [repl_cur_len], 0
    jmp .next_input
.quit:
    ; best-effort temp cleanup
    sub rsp, 0x20
    lea rcx, [repl_tmpname]
    call DeleteFileA
    lea rcx, [repl_outname]
    call DeleteFileA
    add rsp, 0x20
    add rsp, 0x80
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------- repl_eval_trans: write transcript to tmp file, run child ----------
repl_eval_trans:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 0x80
    ; write transcript file
    lea rcx, [repl_tmpname]
    mov rdx, GENERIC_WRITE
    xor r8d, r8d
    mov r9, 0
    mov qword [rsp+0x20], CREATE_ALWAYS
    mov qword [rsp+0x28], 0
    mov qword [rsp+0x30], 0
    call CreateFileA
    cmp rax, INVALID_HANDLE_VALUE
    je .write_err
    mov rbx, rax
    mov rcx, rbx
    lea rdx, [repl_trans]
    mov r8, [repl_trans_len]
    lea r9, [rsp+0x60]
    mov qword [rsp+0x20], 0
    call WriteFile
    mov rcx, rbx
    call CloseHandle
    ; create child-output file (inheritable handle)
    sub rsp, 0x40
    mov dword [rsp+0x38], 12     ; SECURITY_ATTRIBUTES.nLength
    mov qword [rsp+0x40], 0      ; .lpSecurityDescriptor
    mov qword [rsp+0x48], 1      ; .bInheritHandle
    lea rcx, [repl_outname]
    mov rdx, GENERIC_WRITE
    mov r8d, 3                   ; FILE_SHARE_READ|WRITE
    lea r9, [rsp+0x38]           ; &sa
    mov qword [rsp+0x20], CREATE_ALWAYS
    mov qword [rsp+0x28], 0
    mov qword [rsp+0x30], 0      ; hTemplate
    call CreateFileA
    add rsp, 0x40
    cmp rax, INVALID_HANDLE_VALUE
    je .run_err
    mov r15, rax                 ; out file (r15 scratch here)
    ; build cmdline: "<exe>" --repl-echo "<tmp>"
    sub rsp, 0x20
    xor ecx, ecx
    lea rdx, [repl_exe]
    mov r8, SC_MAX_PATH
    call GetModuleFileNameA
    add rsp, 0x20
    test eax, eax
    jz .run_err
    lea rdi, [repl_cmd]
    mov byte [rdi], '"'
    inc rdi
    lea rsi, [repl_exe]
.cp_exe:
    mov al, [rsi]
    test al, al
    jz .cp_exe_done
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .cp_exe
.cp_exe_done:
    mov byte [rdi], '"'
    inc rdi
    lea rsi, [repl_runarg]
.cp_run:
    mov al, [rsi]
    test al, al
    jz .cp_run_done
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .cp_run
.cp_run_done:
    mov byte [rdi], '"'
    inc rdi
    lea rsi, [repl_tmpname]
.cp_tmp:
    mov al, [rsi]
    test al, al
    jz .cp_tmp_done
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .cp_tmp
.cp_tmp_done:
    mov byte [rdi], '"'
    inc rdi
    mov byte [rdi], 0
    ; zero si (104) + pi (24)
    lea rdi, [rsp]
    mov ecx, 26                  ; 26 dwords = 104
    xor eax, eax
.zero_si:
    mov [rdi], eax
    add rdi, 4
    dec ecx
    jnz .zero_si
    mov dword [rsp], 104         ; si.cb
    mov dword [rsp+60], 0x100    ; si.dwFlags = STARTF_USESTDHANDLES
    mov rax, [stdin_handle]
    mov [rsp+80], rax            ; si.hStdInput (inherit console/pipe)
    mov [rsp+88], r15            ; si.hStdOutput = out file
    mov [rsp+96], r15            ; si.hStdError = out file
    lea r12, [rsp+104]           ; pi
    mov qword [r12], 0
    mov qword [r12+8], 0
    mov qword [r12+16], 0
    ; CreateProcessA(NULL, cmdline, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi)
    ; Frame rsp = F; si at [F..F+103], pi at [F+104..F+127].
    ; After sub 0x20: &si = rsp+0x20, pi = rsp+0x88.
    sub rsp, 0x20
    xor ecx, ecx
    lea rdx, [repl_cmd]
    xor r8d, r8d
    xor r9d, r9d
    mov qword [rsp+0x20], 1   ; bInheritHandles=TRUE
    mov qword [rsp+0x28], 0
    mov qword [rsp+0x30], 0
    mov qword [rsp+0x38], 0
    lea rax, [rsp+0x20]       ; &si
    mov [rsp+0x40], rax
    lea rax, [rsp+0x88]       ; &pi
    mov [rsp+0x48], rax
    call CreateProcessA
    add rsp, 0x20
    test eax, eax
    jz .run_err
    ; parent drops its out-file handle (child has its own via inherit)
    mov rcx, r15
    sub rsp, 0x20
    call CloseHandle
    add rsp, 0x20
    ; wait + exit code
    mov rcx, [r12]               ; hProcess
    mov rdx, INFINITE
    sub rsp, 0x20
    call WaitForSingleObject
    add rsp, 0x20
    mov rcx, [r12]
    lea rdx, [rsp+0x60]
    sub rsp, 0x20
    call GetExitCodeProcess
    add rsp, 0x20
    mov eax, [rsp+0x60]   ; child exit code
    mov r15, rax          ; save (r15 restored at epilogue)
    mov rcx, [r12]        ; hProcess
    sub rsp, 0x20
    call CloseHandle
    add rsp, 0x20
    mov rcx, [r12+8]      ; hThread
    sub rsp, 0x20
    call CloseHandle
    add rsp, 0x20
    ; read child output, display new tail (success) or all (failure)
    lea rsi, [repl_outname]
    call load_file        ; RSI=buf, RDX=size
    mov rbx, rsi
    mov r13, rdx          ; size
    test r15d, r15d
    jnz .fail_show
    mov rax, [repl_shown]
    cmp r13, rax
    jb .out_resync
    je .out_done_ok
    push r13
    push rbx
    lea rsi, [rbx+rax]
    mov rdx, r13
    sub rdx, rax
    call print_bytes
    pop rbx
    pop r13
    cmp byte [rbx+r13-1], 10
    je .out_done_ok
    push rbx
    lea rsi, [nl_str]
    call print_cstr
    pop rbx
.out_done_ok:
    mov [repl_shown], r13
    mov rax, r15
    jmp .skip_close
.out_resync:
    test r13, r13
    jz .out_done_ok
    push r13
    push rbx
    mov rsi, rbx
    mov rdx, r13
    call print_bytes
    pop rbx
    pop r13
    cmp byte [rbx+r13-1], 10
    je .out_done_ok
    push rbx
    lea rsi, [nl_str]
    call print_cstr
    pop rbx
    jmp .out_done_ok
.fail_show:
    test r13, r13
    jz .fail_done
    push r15
    push rbx
    mov rsi, rbx
    mov rdx, r13
    call print_bytes
    pop rbx
    pop r15
    cmp byte [rbx+r13-1], 10
    je .fail_done
    push r15
    push rbx
    lea rsi, [nl_str]
    call print_cstr
    pop rbx
    pop r15
.fail_done:
    mov rax, r15
    jmp .skip_close
.skip_close:
    test eax, eax
    jnz .rollback
    add rsp, 0x80
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.rollback:
    ; transcript rollback is the CALLER's job (.eval_failed);
    ; just return nonzero (rax already holds child exit code).
    add rsp, 0x80
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.write_err:
    add rsp, 0x80
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.run_err:
    mov eax, 1
    add rsp, 0x80
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------- main ----------
main:
    sub rsp, 0x28
    mov ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [stdout_handle], rax
    mov rbx, rax
    mov ecx, STD_INPUT_HANDLE
    call GetStdHandle
    mov [stdin_handle], rax
    add rsp, 0x28
    ; ABI: entry RSP%16==8. Resting state here is %16==8, so direct calls
    ; would violate the Windows x64 ABI (calls require RSP%16==0).
    ; Adjust once; all dispatch paths end in ExitProcess (never return).
    sub rsp, 8

    call parse_args
    cmp rax, 2
    jl .noarg
    mov rsi, [g_argv + 1*8]      ; command or file

    ; --repl-echo <file> (hidden: REPL child mode, echo bare expr values)
    mov rdi, s_replecho
    push rsi
    call streq
    pop rsi
    test eax, eax
    jnz .do_replecho

    ; --version
    mov rdi, s_version
    push rsi
    call streq
    pop rsi
    test eax, eax
    jnz .do_version

    ; --help / -h
    mov rdi, s_help
    push rsi
    call streq
    pop rsi
    test eax, eax
    jnz .do_help
    mov rdi, s_h
    push rsi
    call streq
    pop rsi
    test eax, eax
    jnz .do_help

    ; repl
    mov rdi, s_repl
    push rsi
    call streq
    pop rsi
    test eax, eax
    jnz .do_repl

    ; build <file>
    mov rdi, s_build
    push rsi
    call streq
    pop rsi
    test eax, eax
    jnz .do_build

    ; run <file>
    mov rdi, s_run
    push rsi
    call streq
    pop rsi
    test eax, eax
    jnz .do_run

    ; lextest <file> (debug: dump lexer tokens)
    mov rdi, s_lextest
    push rsi
    call streq
    pop rsi
    test eax, eax
    jnz .do_lextest

    mov rdi, s_parsetest
    push rsi
    call streq
    pop rsi
    test eax, eax
    jnz .do_parsetest

    ; default: shitcam <file> -> run
    cmp byte [rsi], '-'
    je .noarg
    mov qword [g_script_arg_start], 2
    call run_file
    xor ecx, ecx
    sub rsp, 0x20
    call ExitProcess

.do_version:
    lea rsi, [ver_str]
    call print_cstr
    xor ecx, ecx
    sub rsp, 0x20
    call ExitProcess

.do_help:
    lea rsi, [usage_str]
    call print_cstr
    xor ecx, ecx
    sub rsp, 0x20
    call ExitProcess

.do_repl:
    call repl_loop
    xor ecx, ecx
    sub rsp, 0x20
    call ExitProcess

.do_build:
    mov rax, [g_argc]
    cmp rax, 3
    jl .build_err
    mov rsi, [g_argv + 2*8]
    call build_file
    xor ecx, ecx
    sub rsp, 0x20
    call ExitProcess
.build_err:
    lea rsi, [err_build]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x20
    call ExitProcess

.do_run:
    mov rax, [g_argc]
    cmp rax, 3
    jl .noarg
    mov rsi, [g_argv + 2*8]
    mov qword [g_script_arg_start], 3
    call run_file
    xor ecx, ecx
    sub rsp, 0x20
    call ExitProcess

.do_lextest:
    mov rax, [g_argc]
    cmp rax, 3
    jl .noarg
    mov rsi, [g_argv + 2*8]
    call lextest_file
    xor ecx, ecx
    sub rsp, 0x20
    call ExitProcess

.do_parsetest:
    mov rax, [g_argc]
    cmp rax, 3
    jl .noarg
    mov rsi, [g_argv + 2*8]
    call parsetest_file
    xor ecx, ecx
    sub rsp, 0x20
    call ExitProcess

.do_replecho:
    mov rax, [g_argc]
    cmp rax, 3
    jl .noarg
    mov qword [repl_echo], 1
    mov rsi, [g_argv + 2*8]
    call run_file
    xor ecx, ecx
    sub rsp, 0x20
    call ExitProcess

.noarg:
    lea rsi, [err_noarg]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x20
    call ExitProcess
