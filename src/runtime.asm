; ShitCam runtime - tagged values, heap, variable and function tables
; Value: type in RAX, payload in RDX (int/float bits, bool 0/1, string ptr, etc.)

%define RT_VAR_ENTRY_SIZE 24
%define RT_FUNC_ENTRY_SIZE 32

section .data
    rt_err_nomem   db "Runtime error: out of memory", 13, 10, 0
    rt_err_undef   db "Runtime error: undefined variable '", 0
    rt_err_undef2  db "'", 13, 10, 0
    rt_err_div0    db "Runtime error: division by zero", 13, 10, 0
    rt_err_arg     db "Runtime error: wrong number of arguments for '", 0
    rt_err_arg2    db "'", 13, 10, 0
    rt_err_type    db "Runtime error: type error", 13, 10, 0
    rt_true_str    db "true", 0
    rt_false_str   db "false", 0
    rt_null_str    db "null", 0
    rt_print_sep   db " ", 0
    rt_dbg_set     db "SET ", 0
    rt_lbr_str     db "[", 0
    rt_rbr_str     db "]", 0
    rt_comma_str   db ", ", 0
    rt_lbrace_str  db "{", 0
    rt_rbrace_str  db "}", 0
    rt_colon_str   db ": ", 0
    rt_minus_str   db "-", 0
    rt_dot_str     db ".", 0
    rt_nan_str     db "nan", 0
    rt_arr_str     db "[array]", 0
    rt_obj_str     db "{object}", 0
    s_print        db "print", 0
    s_println      db "println", 0
    s_input        db "input", 0
    s_fib          db "fib", 0
    s_add          db "add", 0
    s_abs          db "abs", 0
    s_min          db "min", 0
    s_max          db "max", 0
    s_sqrt         db "sqrt", 0
    s_length       db "length", 0
    s_lower        db "lower", 0
    s_upper        db "upper", 0
    s_contains     db "contains", 0
    s_substring    db "substring", 0
    s_push         db "push", 0
    s_pop          db "pop", 0
    s_readfile     db "read_file", 0
    s_writefile    db "write_file", 0
    s_sleep        db "sleep", 0
    s_time         db "time", 0
    s_random       db "random", 0
    s_beep         db "beep", 0
    s_alert        db "alert", 0
    s_args         db "args", 0
    user32_dll     db "user32.dll", 0
    msgbox_proc    db "MessageBoxA", 0
    s_file_exists   db "file_exists", 0
    s_delete_file   db "delete_file", 0
    s_make_dir      db "make_dir", 0
    s_get_env       db "get_env", 0
    s_set_env       db "set_env", 0
    s_system        db "system", 0
    s_set_color     db "set_color", 0
    s_set_clip      db "set_clipboard", 0
    s_get_clip      db "get_clipboard", 0
    s_http_get      db "http_get", 0
    s_key_pressed   db "key_pressed", 0
    s_clear_screen  db "clear_screen", 0

    async_key_proc  db "GetAsyncKeyState", 0

    open_clip_proc  db "OpenClipboard", 0
    close_clip_proc db "CloseClipboard", 0
    empty_clip_proc db "EmptyClipboard", 0
    set_clip_proc   db "SetClipboardData", 0
    get_clip_proc   db "GetClipboardData", 0

    wininet_dll     db "wininet.dll", 0
    net_open_proc   db "InternetOpenA", 0
    net_url_proc    db "InternetOpenUrlA", 0
    net_read_proc   db "InternetReadFile", 0
    net_close_proc  db "InternetCloseHandle", 0
    http_ua         db "ShitCam/0.1", 0

section .bss
    rt_heap        resq 1
    rt_var_count   resq 1
    interp_inited  resq 1
    rt_vars        resb 98304  ; 4096 * 24
    rt_func_count  resq 1
    rt_funcs       resb 8192   ; 256 * 32 (name ptr, param_count, params ptr, body ptr)
    interp_has_ret resq 1
    interp_ret_type resq 1
    interp_ret_payload resq 1
    interp_has_break resq 1
    interp_has_continue resq 1
    prng_seed      resq 1
    rt_tmp_buf     resb 64
    env_buf        resb 4096
    http_buf       resb 65536
    net_bytes_read resd 1
    proc_info      resb 24
    start_info     resb 104
    async_key_ptr  resq 1

section .text

; ---------- rt_init ----------
rt_init:
    push rbx
    sub rsp, 0x20
    call GetProcessHeap
    mov [rt_heap], rax
    add rsp, 0x20
    mov qword [rt_var_count], 0
    mov qword [rt_func_count], 0
    mov qword [interp_has_ret], 0
    pop rbx
    ret

; ---------- rt_alloc(RCX=size) -> RAX ptr ----------
rt_alloc:
    push rbx
    mov rbx, rcx
    mov rcx, [rt_heap]
    xor edx, edx
    mov r8, rbx
    sub rsp, 0x20
    call HeapAlloc
    add rsp, 0x20
    test rax, rax
    jz .oom
    pop rbx
    ret
.oom:
    lea rsi, [rt_err_nomem]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x20
    call ExitProcess

; ---------- streq already defined in shitcam.asm, reuse ----------

; ---------- rt_find_var(RSI=name_ptr) -> RAX index or -1 ----------
rt_find_var:
    push rbx
    push r12
    mov r12, rsi
    mov rcx, [rt_var_count]
    xor eax, eax
    test rcx, rcx
    jz .notfound
.loop:
    cmp rax, rcx
    jae .notfound
    imul rbx, rax, RT_VAR_ENTRY_SIZE
    lea rbx, [rt_vars + rbx]
    mov rsi, [rbx]
    mov rdi, r12
    push rax
    push rcx
    call streq
    pop rcx
    pop rbx
    mov r12, rdi
    ; Actually streq clobbers RSI/RDI, need reload? Simplified: use compare
    ; We saved original? Let's redo with proper save
    jmp .after
.after:
    ; This is messy, reimplement simpler loop with stack save
    pop r12
    pop rbx
    ret
.notfound:
    mov rax, -1
    pop r12
    pop rbx
    ret

; Simple find var loop without extra calls that clobber? We'll implement inline streq loop
rt_find_var2:
    mov rax, -1
    mov rcx, [rt_var_count]
    test rcx, rcx
    jz .done2
    xor r8d, r8d
.loop2:
    cmp r8, rcx
    jae .done2
    imul r9, r8, RT_VAR_ENTRY_SIZE
    lea r9, [rt_vars + r9]
    mov r9, [r9] ; name ptr
    ; compare r9 vs RSI
    push rsi
    push r9
    push r8
    push rcx
    mov rsi, r9
    mov rdi, [rsp + 32] ; original RSI? stack offset messy
    call streq
    pop rcx
    pop r8
    pop r9
    pop rsi
    test eax, eax
    jnz .found2
    inc r8
    jmp .loop2
.found2:
    mov rax, r8
.done2:
    ret

; For now, implement simple find that works: we will use a helper that doesn't corrupt
; Let's implement rt_find_var properly with manual string compare inline

rt_find_var_proper:
    push rbx
    push r12
    push r13
    mov r12, rsi ; target
    mov r13, [rt_var_count]
    xor eax, eax
    test r13, r13
    jz .nf
.lp:
    cmp rax, r13
    jae .nf
    imul rbx, rax, RT_VAR_ENTRY_SIZE
    lea rbx, [rt_vars + rbx]
    mov rbx, [rbx]
    ; rbx = stored name, r12 = target
    push rax
    mov rsi, rbx
    mov rdi, r12
    call streq
    pop rbx
    mov rax, rbx
    test eax, eax
    jnz .found
    mov rax, rbx
    inc rax
    jmp .lp
.nf:
    mov rax, -1
    pop r13
    pop r12
    pop rbx
    ret
.found:
    mov rax, rbx
    pop r13
    pop r12
    pop rbx
    ret

; Actually the above is still broken due to pop confusion. Let's simplify: just use a tiny loop that compares manually without calling streq
; Searches from NEWEST to OLDEST so inner scopes shadow outer ones.
rt_find_var_simple:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rsi
    mov r13, [rt_var_count]
    test r13, r13
    jz .nf2
    lea r14, [r13-1]
.lp2:
    cmp r14, 0
    jl .nf2
    imul rbx, r14, RT_VAR_ENTRY_SIZE
    lea rbx, [rt_vars + rbx]
    mov rbx, [rbx] ; stored
    ; compare strings rbx vs r12
    push r14
    push r13
    mov rsi, rbx
    mov rdi, r12
    xor eax, eax
.cmp:
    mov cl, [rsi]
    mov dl, [rdi]
    cmp cl, dl
    jne .neq
    test cl, cl
    jz .eq
    inc rsi
    inc rdi
    jmp .cmp
.eq:
    mov eax, 1
    jmp .aftercmp
.neq:
    xor eax, eax
.aftercmp:
    pop r13
    pop r14
    test eax, eax
    jnz .found2
    dec r14
    jmp .lp2
.nf2:
    mov rax, -1
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.found2:
    mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------- rt_get_var(RSI=name) -> RAX type, RDX payload, RCX found 1/0 ----------
rt_get_var:
    push rbx
    call rt_find_var_simple
    cmp rax, -1
    je .notf
    imul rbx, rax, RT_VAR_ENTRY_SIZE
    lea rbx, [rt_vars + rbx]
    mov rax, [rbx + 8]
    mov rdx, [rbx + 16]
    mov rcx, 1
    pop rbx
    ret
.notf:
    xor eax, eax
    xor edx, edx
    xor ecx, ecx
    pop rbx
    ret

; ---------- rt_set_var(RSI=name, RAX=type, RDX=payload) ----------
rt_set_var:
    push rbx
    push r12
    push r13
    mov r13, rsi
    mov r12, rdx
    mov rbx, rax
    call rt_find_var_simple
    cmp rax, -1
    jne .update
    ; new
    mov rax, [rt_var_count]
    cmp rax, SC_MAX_VARS
    jae .oom2
    imul rdx, rax, RT_VAR_ENTRY_SIZE
    lea rdx, [rt_vars + rdx]
    mov [rdx], r13
    mov [rdx+8], rbx
    mov [rdx+16], r12
    inc qword [rt_var_count]
    pop r13
    pop r12
    pop rbx
    ret
.update:
    imul rdx, rax, RT_VAR_ENTRY_SIZE
    lea rdx, [rt_vars + rdx]
    mov [rdx+8], rbx
    mov [rdx+16], r12
    pop r13
    pop r12
    pop rbx
    ret
.oom2:
    lea rsi, [rt_err_nomem]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x28
    call ExitProcess

; ---------- rt_push_var(RSI=name, RAX=type, RDX=payload): always append new slot ----------
rt_push_var:
    push rbx
    mov rbx, [rt_var_count]
    cmp rbx, SC_MAX_VARS
    jae .oom
    imul rcx, rbx, RT_VAR_ENTRY_SIZE
    lea rcx, [rt_vars + rcx]
    mov [rcx], rsi
    mov [rcx+8], rax
    mov [rcx+16], rdx
    inc qword [rt_var_count]
    pop rbx
    ret
.oom:
    lea rsi, [rt_err_nomem]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x20
    call ExitProcess

; ---------- rt_find_func(RSI=name) -> RAX idx or -1 ----------
rt_find_func:
    push rbx
    push r12
    mov r12, rsi
    mov rcx, [rt_func_count]
    xor r8d, r8d
.lp:
    cmp r8, rcx
    jae .nf
    imul rbx, r8, RT_FUNC_ENTRY_SIZE
    lea rbx, [rt_funcs + rbx]
    mov rbx, [rbx]
    mov rsi, rbx
    mov rdi, r12
    push r8
    push rcx
    call streq
    pop rcx
    pop r8
    test eax, eax
    jnz .found
    inc r8
    jmp .lp
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

; ---------- rt_add_func(RSI=name, RDX=param_count, RCX=params_ptr, R8=body) ----------
rt_add_func:
    push rbx
    mov rax, [rt_func_count]
    cmp rax, 256
    jae .oom
    imul rbx, rax, RT_FUNC_ENTRY_SIZE
    lea rbx, [rt_funcs + rbx]
    mov [rbx], rsi
    mov [rbx+8], rdx
    mov [rbx+16], rcx
    mov [rbx+24], r8
    inc qword [rt_func_count]
    pop rbx
    ret
.oom:
    lea rsi, [rt_err_nomem]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x20
    call ExitProcess

; ---------- rt_error helpers ----------
rt_error_undef:
    push rsi
    lea rsi, [rt_err_undef]
    call print_cstr
    pop rsi
    push rsi
    call print_cstr
    lea rsi, [rt_err_undef2]
    call print_cstr
    pop rsi
    mov ecx, 1
    sub rsp, 0x28
    call ExitProcess

rt_error_div0:
    lea rsi, [rt_err_div0]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x28
    call ExitProcess

; ---------- rt_print_value(RAX=type, RDX=payload) ----------
rt_print_value:
    push rbx
    cmp rax, SC_T_NULL
    je .null
    cmp rax, SC_T_BOOL
    je .bool
    cmp rax, SC_T_INT
    je .int
    cmp rax, SC_T_FLOAT
    je .float
    cmp rax, SC_T_STRING
    je .str
    cmp rax, SC_T_ARRAY
    je .array
    cmp rax, SC_T_OBJECT
    je .object
    jmp .null
.null:
    lea rsi, [rt_null_str]
    call print_cstr
    pop rbx
    ret
.bool:
    test rdx, rdx
    jz .false
    lea rsi, [rt_true_str]
    call print_cstr
    pop rbx
    ret
.false:
    lea rsi, [rt_false_str]
    call print_cstr
    pop rbx
    ret
.int:
    test rdx, rdx
    jns .int_pos
    push rdx
    lea rsi, [rt_minus_str]
    call print_cstr
    pop rdx
    neg rdx
.int_pos:
    mov rax, rdx
    call print_u64
    pop rbx
    ret
.float:
    movq xmm0, rdx
    ucomisd xmm0, xmm0
    jp .f_nan
    mov rax, rdx
    test rax, rax
    jns .f_pos
    push rdx
    lea rsi, [rt_minus_str]
    call print_cstr
    pop rdx
    movq xmm0, rdx
    mov rax, 0x8000000000000000
    movq xmm1, rax
    xorpd xmm0, xmm1
.f_pos:
    cvttsd2si rax, xmm0
    push rdx              ; bits (xmm0 dies in print calls: XMM0-5 volatile)
    push rax              ; intpart
    mov rax, [rsp]
    call print_u64
    lea rsi, [rt_dot_str]
    call print_cstr
    pop rax               ; intpart
    pop rdx               ; bits
    movq xmm0, rdx
    mov rdx, 0x7FFFFFFFFFFFFFFF
    movq xmm1, rdx
    andpd xmm0, xmm1      ; |x| (idempotent for positives)
    cvtsi2sd xmm1, rax
    subsd xmm0, xmm1
    mov eax, 1000000
    cvtsi2sd xmm1, rax
    mulsd xmm0, xmm1
    cvttsd2si rax, xmm0
    call rt_print_frac6
    pop rbx
    ret
.f_nan:
    lea rsi, [rt_nan_str]
    call print_cstr
    pop rbx
    ret
.str:
    mov rsi, rdx
    call print_cstr
    pop rbx
    ret
.array:
    ; NOTE: rt_print_value already pushed rbx on entry; we must pop it here.
    ; This path uses no callee-saved regs (state lives in frame slots).
    sub rsp, 0x20
    mov [rsp], rdx            ; base
    mov rax, [rdx]            ; len
    mov [rsp+8], rax
    mov qword [rsp+16], 0     ; idx
    lea rsi, [rt_lbr_str]
    call print_cstr
.arr_loop:
    mov rcx, [rsp+16]
    cmp rcx, [rsp+8]
    jae .arr_done
    test rcx, rcx
    jz .arr_nosep
    lea rsi, [rt_comma_str]
    call print_cstr
.arr_nosep:
    mov rax, [rsp]            ; base
    mov rdx, [rsp+16]         ; idx
    imul rdx, rdx, 16
    lea rax, [rax+rdx+16]
    mov rdx, [rax+8]          ; payload
    mov rax, [rax]            ; type
    call rt_print_value
    inc qword [rsp+16]
    jmp .arr_loop
.arr_done:
    lea rsi, [rt_rbr_str]
    call print_cstr
    add rsp, 0x20
    pop rbx
    ret
.object:
    ; Same contract as .array: pop the entry rbx, use frame only.
    sub rsp, 0x20
    mov [rsp], rdx            ; base
    mov rax, [rdx]            ; count
    mov [rsp+8], rax
    mov qword [rsp+16], 0     ; idx
    lea rsi, [rt_lbrace_str]
    call print_cstr
.obj_loop:
    mov rcx, [rsp+16]
    cmp rcx, [rsp+8]
    jae .obj_done
    test rcx, rcx
    jz .obj_nosep
    lea rsi, [rt_comma_str]
    call print_cstr
.obj_nosep:
    mov rax, [rsp]            ; base
    mov rdx, [rsp+16]         ; idx
    imul rdx, rdx, 24
    lea rax, [rax+rdx+16]
    mov [rsp+24], rax         ; stash entry
    mov rsi, [rax]            ; key
    call print_cstr
    lea rsi, [rt_colon_str]
    call print_cstr
    mov rax, [rsp+24]
    mov rdx, [rax+16]         ; payload
    mov rax, [rax+8]          ; type
    call rt_print_value
    inc qword [rsp+16]
    jmp .obj_loop
.obj_done:
    lea rsi, [rt_rbrace_str]
    call print_cstr
    add rsp, 0x20
    pop rbx
    ret

; ---------- rt_print_frac6(RAX=0..999999): prints exactly 6 digits ----------
rt_print_frac6:
    push rbx
    push r12
    sub rsp, 0x28
    mov r12, rax
    mov rbx, 100000
.f6_loop:
    test rbx, rbx
    jz .f6_done
    mov rax, r12
    xor edx, edx
    div rbx
    add al, '0'
    mov [rsp], al
    mov r12, rdx
    push rbx
    lea rsi, [rsp+8]
    mov rdx, 1
    call print_bytes
    pop rbx
    mov rax, rbx
    xor edx, edx
    mov ecx, 10
    div rcx
    mov rbx, rax
    jmp .f6_loop
.f6_done:
    add rsp, 0x28
    pop r12
    pop rbx
    ret

; ---------- rt_str_new_copy(RSI=src) -> RAX new heap string ----------
rt_str_new_copy:
    push rbx
    push rsi
    call strlen
    mov rbx, rax
    inc rbx
    mov rcx, rbx
    call rt_alloc
    mov rdx, rax
    pop rsi
    push rdx
    xor ecx, ecx
.cp:
    cmp rcx, rbx
    jae .cp_done
    mov al, [rsi+rcx]
    mov [rdx+rcx], al
    inc rcx
    jmp .cp
.cp_done:
    pop rax
    pop rbx
    ret

; ---------- rt_str_lower_upper(RSI=src, RDX=1 lower / 0 upper) -> RAX new string ----------
rt_str_case:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13d, edx
    call strlen
    mov rbx, rax
    inc rbx
    mov rcx, rbx
    call rt_alloc
    mov rdx, rax
    xor ecx, ecx
.cp2:
    cmp rcx, rbx
    jae .cp2_done
    mov al, [r12+rcx]
    test r13d, r13d
    jz .to_upper
    cmp al, 'A'
    jb .store2
    cmp al, 'Z'
    ja .store2
    add al, 32
    jmp .store2
.to_upper:
    cmp al, 'a'
    jb .store2
    cmp al, 'z'
    ja .store2
    sub al, 32
.store2:
    mov [rdx+rcx], al
    inc rcx
    jmp .cp2
.cp2_done:
    mov rax, rdx
    pop r13
    pop r12
    pop rbx
    ret

; ---------- rt_str_contains(RSI=hay, RDI=needle) -> RAX 1/0 ----------
rt_str_contains:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdi
    mov al, [r13]
    test al, al
    jz .found
.outer:
    mov al, [r12]
    test al, al
    jz .notfound
    mov rsi, r12
    mov rdi, r13
.inner:
    mov bl, [rdi]
    test bl, bl
    jz .found
    mov bh, [rsi]
    cmp bh, bl
    jne .next
    inc rsi
    inc rdi
    jmp .inner
.next:
    inc r12
    jmp .outer
.found:
    mov eax, 1
    pop r13
    pop r12
    pop rbx
    ret
.notfound:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

; ---------- rt_str_substring(RSI=src, RDX=start, RCX=len) -> RAX new string (clamped) ----------
rt_str_substring:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rsi, r12
    call strlen            ; rax = slen
    cmp r13, rax
    jae .empty
    sub rax, r13           ; avail
    cmp r14, rax
    jbe .oklen
    mov r14, rax
.oklen:
    mov rbx, r14
    inc rbx
    mov rcx, rbx
    call rt_alloc
    mov rdx, rax
    xor ecx, ecx
.cp3:
    cmp rcx, r14
    jae .cp3_done
    lea rax, [r12+r13]
    mov al, [rax+rcx]
    mov [rdx+rcx], al
    inc rcx
    jmp .cp3
.cp3_done:
    mov byte [rdx+r14], 0
    mov rax, rdx
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.empty:
    mov rcx, 1
    call rt_alloc
    mov byte [rax], 0
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------- rt_int_to_str(RAX=value) -> RAX new heap string (signed decimal) ----------
rt_int_to_str:
    push rbx
    push r12
    mov r12, rax
    mov rcx, 32
    call rt_alloc
    mov rbx, rax
    add rbx, 31
    mov byte [rbx], 0
    mov rax, r12
    test rax, rax
    jns .pos
    neg rax
    mov r12, 1             ; negative flag
    jmp .digits
.pos:
    mov r12, 0
.digits:
    mov rcx, 10
    xor edx, edx
    div rcx
    add dl, '0'
    dec rbx
    mov [rbx], dl
    test rax, rax
    jnz .digits
    cmp r12, 0
    je .done
    dec rbx
    mov byte [rbx], '-'
.done:
    mov rax, rbx
    pop r12
    pop rbx
    ret

; ---------- rt_array_new(RCX=cap) -> RAX array ----------
rt_array_new:
    push rbx
    mov rbx, rcx
    imul rcx, rbx, 16
    add rcx, 16
    call rt_alloc
    mov qword [rax], 0     ; len
    mov [rax+8], rbx       ; cap
    pop rbx
    ret

; ---------- rt_array_push(RAX=array, RDX=type, RCX=payload) -> RAX array (maybe grown) ----------
rt_array_push:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rax          ; array
    mov r13, rdx          ; type
    mov r14, rcx          ; payload
    mov rbx, [r12]        ; len
    cmp rbx, [r12+8]
    jb .room
    ; grow: newcap = cap ? cap*2 : 4
    mov rax, [r12+8]
    test rax, rax
    jnz .dbl
    mov rax, 4
    jmp .mk
.dbl:
    imul rax, rax, 2
.mk:
    mov rcx, rax
    call rt_array_new     ; rax=new (preserves rbx,r12-r14: only uses rax,rbx,rcx + pushed rbx)
    mov rdx, rax          ; new
    mov rax, [r12]        ; len
    mov [rdx], rax        ; new len
    test rax, rax
    jz .swap
    push rsi
    push rdi
    mov rcx, rax
    imul rcx, rcx, 2      ; qwords per items
    lea rsi, [r12+16]
    lea rdi, [rdx+16]
    rep movsq
    pop rdi
    pop rsi
.swap:
    mov r12, rdx          ; array = new (old block leaks: arena, documented)
.room:
    mov rax, [r12]        ; len
    imul rax, rax, 16
    lea rax, [r12+rax+16]
    mov [rax], r13
    mov [rax+8], r14
    inc qword [r12]
    mov rax, r12
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------- rt_array_pop(RAX=array) -> RAX type, RDX payload (null if empty) ----------
rt_array_pop:
    mov rcx, [rax]
    test rcx, rcx
    jz .empty
    dec qword [rax]
    mov rcx, [rax]
    imul rcx, rcx, 16
    lea rcx, [rax+rcx+16]
    mov rdx, [rcx+8]
    mov rax, [rcx]
    ret
.empty:
    mov rax, SC_T_NULL
    xor edx, edx
    ret

; ---------- rt_array_get(RAX=array, RCX=index) -> RAX type, RDX payload (null if OOB) ----------
rt_array_get:
    cmp rcx, 0
    jl .oob
    cmp rcx, [rax]
    jae .oob
    imul rcx, rcx, 16
    lea rax, [rax+rcx+16]
    mov rdx, [rax+8]
    mov rax, [rax]
    ret
.oob:
    mov rax, SC_T_NULL
    xor edx, edx
    ret

; ---------- rt_object_new(RCX=cap) -> RAX object ----------
rt_object_new:
    push rbx
    mov rbx, rcx
    imul rcx, rbx, 24
    add rcx, 16
    call rt_alloc
    mov qword [rax], 0
    mov [rax+8], rbx
    pop rbx
    ret

; ---------- rt_object_set(RAX=obj, RSI=key, RDX=type, RCX=payload) -> RAX obj (maybe grown) ----------
rt_object_set:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rax
    mov r13, rsi
    mov r14, rdx
    mov r15, rcx
    mov rbx, [r12]
    xor ecx, ecx
.search:
    cmp rcx, rbx
    jae .append
    imul rax, rcx, 24
    lea rax, [r12+rax+16]
    mov rax, [rax]        ; stored key
    push rbx
    push rcx
    mov rsi, rax
    mov rdi, r13
    call streq
    pop rcx
    pop rbx
    test eax, eax
    jnz .update
    inc rcx
    jmp .search
.update:
    imul rax, rcx, 24
    lea rax, [r12+rax+16]
    mov [rax+8], r14
    mov [rax+16], r15
    mov rax, r12
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.append:
    cmp rbx, [r12+8]
    jb .room
    mov rax, [r12+8]
    test rax, rax
    jnz .dbl
    mov rax, 4
    jmp .mk
.dbl:
    imul rax, rax, 2
.mk:
    mov rcx, rax
    call rt_object_new
    mov rdx, rax
    mov rax, [r12]
    mov [rdx], rax
    test rax, rax
    jz .swap
    push rsi
    push rdi
    mov rcx, rax
    imul rcx, rcx, 3
    lea rsi, [r12+16]
    lea rdi, [rdx+16]
    rep movsq
    pop rdi
    pop rsi
.swap:
    mov r12, rdx
.room:
    mov rax, [r12]
    imul rax, rax, 24
    lea rax, [r12+rax+16]
    mov [rax], r13
    mov [rax+8], r14
    mov [rax+16], r15
    inc qword [r12]
    mov rax, r12
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------- rt_object_get(RAX=obj, RSI=key) -> RAX type, RDX payload (null if missing) ----------
rt_object_get:
    push rbx
    push r12
    push r13
    mov r12, rax
    mov r13, rsi
    mov rbx, [r12]
    xor ecx, ecx
.search2:
    cmp rcx, rbx
    jae .miss
    imul rax, rcx, 24
    lea rax, [r12+rax+16]
    mov rax, [rax]
    push rbx
    push rcx
    mov rsi, rax
    mov rdi, r13
    call streq
    pop rcx
    pop rbx
    test eax, eax
    jnz .hit2
    inc rcx
    jmp .search2
.hit2:
    imul rcx, rcx, 24
    lea rax, [r12+rcx+16]
    mov rdx, [rax+16]
    mov rax, [rax+8]
    pop r13
    pop r12
    pop rbx
    ret
.miss:
    mov rax, SC_T_NULL
    xor edx, edx
    pop r13
    pop r12
    pop rbx
    ret

; ---------- rt_input(RSI=prompt or 0) -> RAX string ----------
rt_input:
    push rbx
    push r12
    sub rsp, 0x28
    mov r12, rsi
    test rsi, rsi
    jz .noprompt
    call print_cstr
.noprompt:
    mov rcx, 4096
    call rt_alloc
    mov r12, rax
    xor ebx, ebx              ; count
.read_loop:
    cmp rbx, 4095
    jae .got_line
    mov rcx, [stdin_handle]
    lea rdx, [r12+rbx]
    mov r8, 1
    lea r9, [rsp+0x18]
    mov qword [rsp+0x18], 0
    mov qword [rsp+0x20], 0
    call ReadFile
    test eax, eax
    jz .got_line              ; error/EOF: return what we have
    cmp qword [rsp+0x18], 0
    je .got_line              ; EOF: return what we have
    mov al, [r12+rbx]
    inc rbx
    cmp al, 10
    je .got_line
    jmp .read_loop
.got_line:
    mov byte [r12+rbx], 0
    ; strip trailing CR/LF
    lea rax, [r12+rbx]
.strip:
    cmp rax, r12
    jbe .done
    dec rax
    mov cl, [rax]
    cmp cl, 10
    je .kill
    cmp cl, 13
    je .kill
    inc rax
    jmp .done_set
.kill:
    mov byte [rax], 0
    jmp .strip
.done_set:
    mov rax, r12
.done:
    add rsp, 0x28
    pop r12
    pop rbx
    ret

; ---------- rt_write_file(RSI=path, RDX=data, RCX=len) -> RAX bytes written or -1 ----------
rt_write_file:
    push rbx
    push r12
    push r13
    sub rsp, 0x40
    mov r12, rdx
    mov r13, rcx
    mov rcx, rsi
    mov rdx, GENERIC_WRITE
    xor r8d, r8d
    mov r9, 0
    mov qword [rsp+0x20], CREATE_ALWAYS
    mov qword [rsp+0x28], 0
    mov qword [rsp+0x30], 0
    call CreateFileA
    cmp rax, INVALID_HANDLE_VALUE
    je .fail
    mov rbx, rax
    mov rcx, rbx
    mov rdx, r12
    mov r8, r13
    lea r9, [rsp+0x18]
    mov qword [rsp+0x20], 0
    call WriteFile
    test eax, eax
    jz .fail_close
    mov rcx, rbx
    call CloseHandle
    mov rax, [rsp+0x18]
    add rsp, 0x40
    pop r13
    pop r12
    pop rbx
    ret
.fail_close:
    mov rcx, rbx
    call CloseHandle
.fail:
    mov rax, -1
    add rsp, 0x40
    pop r13
    pop r12
    pop rbx
    ret

; ---------- rt_str_concat(RSI=a, RDI=b) -> RAX new string ----------
rt_str_concat:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13, rdi
    call strlen
    mov rbx, rax
    mov rsi, r13
    call strlen
    add rax, rbx
    inc rax
    mov rcx, rax
    call rt_alloc
    mov rdx, rax
    xor ecx, ecx
.scc1:
    cmp rcx, rbx
    jae .scc2
    mov al, [r12+rcx]
    mov [rdx+rcx], al
    inc rcx
    jmp .scc1
.scc2:
    xor r8d, r8d
.scc3:
    mov al, [r13+r8]
    mov [rdx+rcx], al
    test al, al
    jz .scc_done
    inc rcx
    inc r8
    jmp .scc3
.scc_done:
    mov rax, rdx
    pop r13
    pop r12
    pop rbx
    ret

; ---------- rt_float_to_str(RAX=bits) -> RAX new heap string ----------
rt_float_to_str:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rax          ; bits
    mov rcx, 40
    call rt_alloc
    mov r13, rax          ; buf
    xor r14d, r14d        ; pos
    movq xmm0, r12
    ucomisd xmm0, xmm0
    jp .ff_nan
    mov rax, r12
    test rax, rax
    jns .ff_pos
    mov byte [r13+r14], '-'
    inc r14
    mov rax, 0x8000000000000000
    movq xmm1, rax
    xorpd xmm0, xmm1
.ff_pos:
    cvttsd2si rax, xmm0
    push rax
    call rt_int_to_str    ; rax = int string
    mov rsi, rax
    lea rdi, [r13+r14]
.ff_copyi:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .ff_afteri
    inc rsi
    inc rdi
    inc r14
    jmp .ff_copyi
.ff_afteri:
    pop rax               ; int part value
    movq xmm0, r12        ; restore float (r12=bits; xmm0 died in rt_int_to_str)
    mov rdx, 0x7FFFFFFFFFFFFFFF
    movq xmm1, rdx
    andpd xmm0, xmm1      ; |x|
    cvtsi2sd xmm1, rax
    subsd xmm0, xmm1
    mov eax, 1000000
    cvtsi2sd xmm1, rax
    mulsd xmm0, xmm1
    cvttsd2si rax, xmm0
    mov rbx, rax          ; frac value
    mov byte [r13+r14], '.'
    inc r14
    mov rcx, 100000       ; divisor
.ff_frac:
    test rcx, rcx
    jz .ff_done
    mov rax, rbx
    xor edx, edx
    div rcx
    add al, '0'
    mov [r13+r14], al
    inc r14
    mov rbx, rdx
    mov rax, rcx
    xor edx, edx
    push rbx
    mov ebx, 10
    div rbx
    mov rcx, rax
    pop rbx
    jmp .ff_frac
.ff_done:
    mov byte [r13+r14], 0
    mov rax, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.ff_nan:
    mov dword [r13], 'nan'
    mov byte [r13+3], 0
    mov rax, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------- rt_val_to_str(RAX=type, RDX=payload) -> RAX string ----------
rt_val_to_str:
    cmp rax, SC_T_STRING
    je .v_same
    cmp rax, SC_T_INT
    je .v_int
    cmp rax, SC_T_FLOAT
    je .v_float
    cmp rax, SC_T_BOOL
    je .v_bool
    cmp rax, SC_T_ARRAY
    je .v_arr
    cmp rax, SC_T_OBJECT
    je .v_obj
    lea rax, [rt_null_str]
    ret
.v_same:
    mov rax, rdx
    ret
.v_int:
    mov rax, rdx
    jmp rt_int_to_str
.v_float:
    mov rax, rdx
    jmp rt_float_to_str
.v_bool:
    test rdx, rdx
    jz .v_false
    lea rax, [rt_true_str]
    ret
.v_false:
    lea rax, [rt_false_str]
    ret
.v_arr:
    lea rax, [rt_arr_str]
    ret
.v_obj:
    lea rax, [rt_obj_str]
    ret
rt_print_value_nl:
    call rt_print_value
    lea rsi, [nl_str]
    call print_cstr
    ret
