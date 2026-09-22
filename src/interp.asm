; ShitCam interpreter - tree walk on AST, dynamic types

section .data
    interp_err_return db "Runtime error: return outside function", 13, 10, 0

section .text

; Forward decls
; interp_eval(RAX=node) -> RAX type, RDX payload
; interp_exec(RAX=node) -> void

; ---------- interp_init ----------
interp_init:
    jmp rt_init

; ---------- interp_init_once: init runtime only on first call (imports reuse env) ----------
interp_init_once:
    push rax
    mov rax, [interp_inited]
    test rax, rax
    jnz .done
    mov qword [interp_inited], 1
    call rt_init
    push rbx
    push r12
    push r13
    mov rcx, 16
    call rt_array_new
    mov r12, rax
    mov r13, [g_script_arg_start]
    test r13, r13
    jz .args_set
.args_loop:
    cmp r13, [g_argc]
    jae .args_set
    mov rsi, [g_argv + r13*8]
    call rt_str_new_copy
    mov rcx, rax
    mov rdx, SC_T_STRING
    mov rax, r12
    call rt_array_push
    mov r12, rax
    inc r13
    jmp .args_loop
.args_set:
    lea rsi, [s_args]
    mov rax, SC_T_ARRAY
    mov rdx, r12
    call rt_set_var
    pop r13
    pop r12
    pop rbx
.done:
    pop rax
    ret

; ---------- interp_is_truthy(RAX type, RDX payload) -> RAX 1/0 ----------
interp_is_truthy:
    cmp rax, SC_T_BOOL
    je .bool
    cmp rax, SC_T_NULL
    je .false
    cmp rax, SC_T_INT
    je .int
    cmp rax, SC_T_FLOAT
    je .true
    cmp rax, SC_T_STRING
    je .str
    jmp .true
.bool:
    test rdx, rdx
    setnz al
    movzx eax, al
    ret
.int:
    test rdx, rdx
    setnz al
    movzx eax, al
    ret
.str:
    test rdx, rdx
    jz .false
    mov al, [rdx]
    test al, al
    setnz al
    movzx eax, al
    ret
.true:
    mov eax, 1
    ret
.false:
    xor eax, eax
    ret

; ---------- interp_eval ----------
interp_eval:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 0x20
    mov r12, rax ; node
    mov rax, [r12]
    cmp rax, AST_INT
    je .int
    cmp rax, AST_FLOAT
    je .float
    cmp rax, AST_STRING
    je .string
    cmp rax, AST_BOOL
    je .bool
    cmp rax, AST_NULL
    je .null
    cmp rax, AST_VAR
    je .var
    cmp rax, AST_BINARY
    je .binary
    cmp rax, AST_UNARY
    je .unary
    cmp rax, AST_CALL
    je .call
    cmp rax, AST_ARRAY
    je .array
    cmp rax, AST_OBJECT
    je .object
    cmp rax, AST_INDEX
    je .index
    cmp rax, AST_MEMBER
    je .member
    ; for others, error
    lea rsi, [rt_err_type]
    call print_cstr
    mov ecx, 1
    call ExitProcess
.int:
    mov rax, SC_T_INT
    mov rdx, [r12+16]
    jmp .done
.float:
    mov rax, SC_T_FLOAT
    mov rdx, [r12+16]
    jmp .done
.string:
    mov rax, SC_T_STRING
    mov rdx, [r12+16]
    jmp .done
.bool:
    mov rax, SC_T_BOOL
    mov rdx, [r12+8]
    jmp .done
.null:
    mov rax, SC_T_NULL
    xor edx, edx
    jmp .done
.var:
    mov rsi, [r12+16]
    call rt_get_var
    test rcx, rcx
    jz .undef
    jmp .done
.undef:
    mov rsi, [r12+16]
    call rt_error_undef
.binary:
    ; left in [r12+16], right in [r12+24], op in [r12+8]
    mov rax, [r12+16]
    call interp_eval
    mov r13, rax ; left type
    mov r14, rdx ; left payload
    push r13
    push r14
    mov rbx, [r12+8] ; op
    push rbx
    mov rax, [r12+24]
    call interp_eval
    mov r15, rax ; right type
    mov rcx, rdx ; right payload
    pop rbx ; op
    pop r14 ; left payload
    pop r13 ; left type
    ; dispatch based on op
    cmp rbx, TOK_PLUS
    je .add
    cmp rbx, TOK_MINUS
    je .sub
    cmp rbx, TOK_STAR
    je .mul
    cmp rbx, TOK_SLASH
    je .div
    cmp rbx, TOK_PERCENT
    je .mod
    cmp rbx, TOK_EQEQ
    je .eq
    cmp rbx, TOK_NEQ
    je .neq
    cmp rbx, TOK_GT
    je .gt
    cmp rbx, TOK_LT
    je .lt
    cmp rbx, TOK_GTE
    je .gte
    cmp rbx, TOK_LTE
    je .lte
    cmp rbx, TOK_ANDAND
    je .and
    cmp rbx, TOK_OROR
    je .or
    jmp .bin_done
.add:
    ; string concat if either is string
    cmp r13, SC_T_STRING
    je .str_concat
    cmp r15, SC_T_STRING
    je .str_concat
    ; float if either float
    cmp r13, SC_T_FLOAT
    je .fadd
    cmp r15, SC_T_FLOAT
    je .fadd
    ; int
    mov rax, r14
    add rax, rcx
    mov rdx, rax
    mov rax, SC_T_INT
    jmp .bin_done
.fadd:
    ; convert ints to float if needed
    cmp r13, SC_T_INT
    jne .f1
    cvtsi2sd xmm0, r14
    jmp .f2
.f1:
    movq xmm0, r14
.f2:
    cmp r15, SC_T_INT
    jne .f3
    cvtsi2sd xmm1, rcx
    jmp .f4
.f3:
    movq xmm1, rcx
.f4:
    addsd xmm0, xmm1
    movq rdx, xmm0
    mov rax, SC_T_FLOAT
    jmp .bin_done
.str_concat:
    ; r13=lt r14=lp r15=rt rcx=rp. Convert both via rt_val_to_str, concat.
    push rcx              ; right payload
    push r15              ; right type
    mov rax, r13
    mov rdx, r14
    call rt_val_to_str
    mov rsi, rax          ; left string
    pop rax               ; right type
    pop rdx               ; right payload
    push rsi              ; save left
    call rt_val_to_str
    mov rdi, rax          ; right string
    pop rsi               ; left string
    call rt_str_concat
    mov rdx, rax
    mov rax, SC_T_STRING
    jmp .bin_done
.sub:
    cmp r13, SC_T_FLOAT
    je .fsub
    cmp r15, SC_T_FLOAT
    je .fsub
    mov rax, r14
    sub rax, rcx
    mov rdx, rax
    mov rax, SC_T_INT
    jmp .bin_done
.fsub:
    cmp r13, SC_T_INT
    jne .fs1
    cvtsi2sd xmm0, r14
    jmp .fs2
.fs1:
    movq xmm0, r14
.fs2:
    cmp r15, SC_T_INT
    jne .fs3
    cvtsi2sd xmm1, rcx
    jmp .fs4
.fs3:
    movq xmm1, rcx
.fs4:
    subsd xmm0, xmm1
    movq rdx, xmm0
    mov rax, SC_T_FLOAT
    jmp .bin_done
.mul:
    cmp r13, SC_T_FLOAT
    je .fmul
    cmp r15, SC_T_FLOAT
    je .fmul
    mov rax, r14
    imul rax, rcx
    mov rdx, rax
    mov rax, SC_T_INT
    jmp .bin_done
.fmul:
    cmp r13, SC_T_INT
    jne .fm1
    cvtsi2sd xmm0, r14
    jmp .fm2
.fm1:
    movq xmm0, r14
.fm2:
    cmp r15, SC_T_INT
    jne .fm3
    cvtsi2sd xmm1, rcx
    jmp .fm4
.fm3:
    movq xmm1, rcx
.fm4:
    mulsd xmm0, xmm1
    movq rdx, xmm0
    mov rax, SC_T_FLOAT
    jmp .bin_done
.div:
    test rcx, rcx
    jz .div0
    cmp r13, SC_T_FLOAT
    je .fdiv
    cmp r15, SC_T_FLOAT
    je .fdiv
    mov rax, r14
    cqo
    idiv rcx
    mov rdx, rax
    mov rax, SC_T_INT
    jmp .bin_done
.fdiv:
    cmp r13, SC_T_INT
    jne .fd1
    cvtsi2sd xmm0, r14
    jmp .fd2
.fd1:
    movq xmm0, r14
.fd2:
    cmp r15, SC_T_INT
    jne .fd3
    cvtsi2sd xmm1, rcx
    jmp .fd4
.fd3:
    movq xmm1, rcx
.fd4:
    divsd xmm0, xmm1
    movq rdx, xmm0
    mov rax, SC_T_FLOAT
    jmp .bin_done
.div0:
    call rt_error_div0
.mod:
    test rcx, rcx
    jz .div0
    mov rax, r14
    cqo
    idiv rcx
    mov rdx, rdx
    mov rax, SC_T_INT
    jmp .bin_done
.eq:
    cmp r13, r15
    jne .neq_true
    cmp r13, SC_T_STRING
    jne .eq_raw
    mov rsi, r14
    mov rdi, rcx
    call streq
    movzx rdx, al
    mov rax, SC_T_BOOL
    jmp .bin_done
.eq_raw:
    cmp r14, rcx
    sete al
    movzx rdx, al
    mov rax, SC_T_BOOL
    jmp .bin_done
.neq_true:
    mov rdx, 0
    mov rax, SC_T_BOOL
    jmp .bin_done
.neq:
    cmp r13, r15
    jne .neq2_true
    cmp r13, SC_T_STRING
    jne .neq_raw
    mov rsi, r14
    mov rdi, rcx
    call streq
    xor eax, 1
    movzx rdx, al
    mov rax, SC_T_BOOL
    jmp .bin_done
.neq_raw:
    cmp r13, r15
    jne .neq2_true
    cmp r14, rcx
    setne al
    movzx rdx, al
    mov rax, SC_T_BOOL
    jmp .bin_done
.neq2_true:
    mov rdx, 1
    mov rax, SC_T_BOOL
    jmp .bin_done
.gt:
    cmp r13, SC_T_FLOAT
    je .fgt
    cmp r15, SC_T_FLOAT
    je .fgt
    cmp r14, rcx
    setg al
    movzx rdx, al
    mov rax, SC_T_BOOL
    jmp .bin_done
.fgt:
    cmp r13, SC_T_INT
    jne .fg1
    cvtsi2sd xmm0, r14
    jmp .fg2
.fg1:
    movq xmm0, r14
.fg2:
    cmp r15, SC_T_INT
    jne .fg3
    cvtsi2sd xmm1, rcx
    jmp .fg4
.fg3:
    movq xmm1, rcx
.fg4:
    comisd xmm0, xmm1
    seta al
    movzx rdx, al
    mov rax, SC_T_BOOL
    jmp .bin_done
.lt:
    cmp r13, SC_T_FLOAT
    je .flt
    cmp r15, SC_T_FLOAT
    je .flt
    cmp r14, rcx
    setl al
    movzx rdx, al
    mov rax, SC_T_BOOL
    jmp .bin_done
.flt:
    cmp r13, SC_T_INT
    jne .fl1
    cvtsi2sd xmm0, r14
    jmp .fl2
.fl1:
    movq xmm0, r14
.fl2:
    cmp r15, SC_T_INT
    jne .fl3
    cvtsi2sd xmm1, rcx
    jmp .fl4
.fl3:
    movq xmm1, rcx
.fl4:
    comisd xmm0, xmm1
    setb al
    movzx rdx, al
    mov rax, SC_T_BOOL
    jmp .bin_done
.gte:
    cmp r13, SC_T_FLOAT
    je .fgte
    cmp r15, SC_T_FLOAT
    je .fgte
    cmp r14, rcx
    setge al
    movzx rdx, al
    mov rax, SC_T_BOOL
    jmp .bin_done
.fgte:
    cmp r13, SC_T_INT
    jne .fge1
    cvtsi2sd xmm0, r14
    jmp .fge2
.fge1:
    movq xmm0, r14
.fge2:
    cmp r15, SC_T_INT
    jne .fge3
    cvtsi2sd xmm1, rcx
    jmp .fge4
.fge3:
    movq xmm1, rcx
.fge4:
    comisd xmm0, xmm1
    setae al
    movzx rdx, al
    mov rax, SC_T_BOOL
    jmp .bin_done
.lte:
    cmp r13, SC_T_FLOAT
    je .flte
    cmp r15, SC_T_FLOAT
    je .flte
    cmp r14, rcx
    setle al
    movzx rdx, al
    mov rax, SC_T_BOOL
    jmp .bin_done
.flte:
    cmp r13, SC_T_INT
    jne .fle1
    cvtsi2sd xmm0, r14
    jmp .fle2
.fle1:
    movq xmm0, r14
.fle2:
    cmp r15, SC_T_INT
    jne .fle3
    cvtsi2sd xmm1, rcx
    jmp .fle4
.fle3:
    movq xmm1, rcx
.fle4:
    comisd xmm0, xmm1
    setbe al
    movzx rdx, al
    mov rax, SC_T_BOOL
    jmp .bin_done
.and:
    call interp_is_truthy
    ; Actually we already have left truthy? Need to evaluate left truthiness, if false return false, else evaluate right truthiness
    ; For simplicity, treat as boolean and
    mov rax, r13
    mov rdx, r14
    call interp_is_truthy
    test eax, eax
    jz .and_false
    mov rax, r15
    mov rdx, rcx
    call interp_is_truthy
    movzx rdx, al
    mov rax, SC_T_BOOL
    jmp .bin_done
.and_false:
    mov rax, SC_T_BOOL
    xor edx, edx
    jmp .bin_done
.or:
    mov rax, r13
    mov rdx, r14
    call interp_is_truthy
    test eax, eax
    jnz .or_true
    mov rax, r15
    mov rdx, rcx
    call interp_is_truthy
    movzx rdx, al
    mov rax, SC_T_BOOL
    jmp .bin_done
.or_true:
    mov rax, SC_T_BOOL
    mov rdx, 1
.bin_done:
    add rsp, 0x20
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.unary:
    mov rax, [r12+16]
    call interp_eval
    mov r13, rax
    mov r14, rdx
    mov rbx, [r12+8]
    cmp rbx, TOK_BANG
    je .not
    cmp rbx, TOK_MINUS
    je .neg
    jmp .done
.not:
    call interp_is_truthy
    xor eax, 1
    movzx rdx, al
    mov rax, SC_T_BOOL
    jmp .done
.neg:
    cmp r13, SC_T_INT
    je .neg_int
    cmp r13, SC_T_FLOAT
    je .neg_float
    mov rax, SC_T_INT
    mov rdx, 0
    jmp .done
.neg_int:
    mov rax, r14
    neg rax
    mov rdx, rax
    mov rax, SC_T_INT
    jmp .done
.neg_float:
    movq xmm0, r14
    xorps xmm1, xmm1
    subsd xmm1, xmm0
    movq rdx, xmm1
    mov rax, SC_T_FLOAT
    jmp .done
.call:
    ; callee in [r12+16], args in [r12+24], count in [r12+8]
    mov r13, [r12+16] ; callee node
    mov r14, [r12+24] ; args base
    mov r15, [r12+8]  ; count
    ; check if callee is Var with builtin name
    mov rax, [r13]
    cmp rax, AST_VAR
    jne .user_call
    mov rsi, [r13+16]
    mov rdi, s_print
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_print
    mov rsi, [r13+16]
    mov rdi, s_println
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_println
    mov rsi, [r13+16]
    mov rdi, s_length
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_length
    mov rsi, [r13+16]
    mov rdi, s_input
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_input
    mov rsi, [r13+16]
    mov rdi, s_lower
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_lower
    mov rsi, [r13+16]
    mov rdi, s_upper
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_upper
    mov rsi, [r13+16]
    mov rdi, s_contains
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_contains
    mov rsi, [r13+16]
    mov rdi, s_substring
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_substring
    mov rsi, [r13+16]
    mov rdi, s_push
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_push
    mov rsi, [r13+16]
    mov rdi, s_pop
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_pop
    mov rsi, [r13+16]
    mov rdi, s_readfile
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_readfile
    mov rsi, [r13+16]
    mov rdi, s_writefile
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_writefile
    mov rsi, [r13+16]
    mov rdi, s_abs
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_abs
    mov rsi, [r13+16]
    mov rdi, s_min
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_min
    mov rsi, [r13+16]
    mov rdi, s_max
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_max
    mov rsi, [r13+16]
    mov rdi, s_sqrt
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_sqrt
    mov rsi, [r13+16]
    mov rdi, s_sleep
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_sleep
    mov rsi, [r13+16]
    mov rdi, s_time
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_time
    mov rsi, [r13+16]
    mov rdi, s_random
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_random
    mov rsi, [r13+16]
    mov rdi, s_beep
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_beep
    mov rsi, [r13+16]
    mov rdi, s_alert
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_alert
    mov rsi, [r13+16]
    mov rdi, s_file_exists
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_file_exists
    mov rsi, [r13+16]
    mov rdi, s_delete_file
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_delete_file
    mov rsi, [r13+16]
    mov rdi, s_make_dir
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_make_dir
    mov rsi, [r13+16]
    mov rdi, s_get_env
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_get_env
    mov rsi, [r13+16]
    mov rdi, s_set_env
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_set_env
    mov rsi, [r13+16]
    mov rdi, s_system
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_system
    mov rsi, [r13+16]
    mov rdi, s_set_color
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_set_color
    mov rsi, [r13+16]
    mov rdi, s_set_clip
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_set_clip
    mov rsi, [r13+16]
    mov rdi, s_get_clip
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_get_clip
    mov rsi, [r13+16]
    mov rdi, s_http_get
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_http_get
    mov rsi, [r13+16]
    mov rdi, s_key_pressed
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_key_pressed
    mov rsi, [r13+16]
    mov rdi, s_clear_screen
    push r15
    push r14
    push r13
    call streq
    pop r13
    pop r14
    pop r15
    test eax, eax
    jnz .builtin_clear_screen
    jmp .user_call
.builtin_print:
    xor r12d, r12d
.print_loop:
    cmp r12, r15
    jae .print_done
    mov rax, [r14 + r12*8]
    call interp_eval
    call rt_print_value
    inc r12
    cmp r12, r15
    jae .print_done
    lea rsi, [rt_print_sep]
    call print_cstr
    jmp .print_loop
.print_done:
    mov rax, SC_T_NULL
    xor edx, edx
    jmp .done
.builtin_println:
    xor r12d, r12d
.pln_loop:
    cmp r12, r15
    jae .pln_done
    mov rax, [r14 + r12*8]
    call interp_eval
    call rt_print_value
    inc r12
    cmp r12, r15
    jae .pln_done
    lea rsi, [rt_print_sep]
    call print_cstr
    jmp .pln_loop
.pln_done:
    lea rsi, [nl_str]
    call print_cstr
    mov rax, SC_T_NULL
    xor edx, edx
    jmp .done
.builtin_length:
    cmp r15, 1
    jne .arg_err
    mov rax, [r14]
    call interp_eval
    cmp rax, SC_T_STRING
    je .len_str
    cmp rax, SC_T_ARRAY
    je .len_arr
    mov rax, SC_T_INT
    xor edx, edx
    jmp .done
.len_str:
    mov rsi, rdx
    call strlen
    mov rdx, rax
    mov rax, SC_T_INT
    jmp .done
.len_arr:
    mov rdx, [rdx]        ; array len
    mov rax, SC_T_INT
    jmp .done
.null_ret:
    mov rax, SC_T_NULL
    xor edx, edx
    jmp .done
.builtin_input:
    cmp r15, 0
    je .in_noprompt
    cmp r15, 1
    jne .arg_err
    mov rax, [r14]
    call interp_eval
    cmp rax, SC_T_STRING
    jne .in_noprompt
    mov rsi, rdx
    call rt_input
    mov rdx, rax
    mov rax, SC_T_STRING
    jmp .done
.in_noprompt:
    xor esi, esi
    call rt_input
    mov rdx, rax
    mov rax, SC_T_STRING
    jmp .done
.builtin_lower:
    cmp r15, 1
    jne .arg_err
    mov rax, [r14]
    call interp_eval
    cmp rax, SC_T_STRING
    jne .null_ret
    mov rsi, rdx
    mov edx, 1
    call rt_str_case
    mov rdx, rax
    mov rax, SC_T_STRING
    jmp .done
.builtin_upper:
    cmp r15, 1
    jne .arg_err
    mov rax, [r14]
    call interp_eval
    cmp rax, SC_T_STRING
    jne .null_ret
    mov rsi, rdx
    xor edx, edx
    call rt_str_case
    mov rdx, rax
    mov rax, SC_T_STRING
    jmp .done
.builtin_contains:
    cmp r15, 2
    jne .arg_err
    mov rax, [r14]
    call interp_eval
    cmp rax, SC_T_STRING
    jne .null_ret
    push rdx              ; hay
    mov rax, [r14+8]
    call interp_eval
    cmp rax, SC_T_STRING
    jne .contains_pop_null
    mov rdi, rdx          ; needle
    pop rsi               ; hay
    call rt_str_contains
    mov rdx, rax
    mov rax, SC_T_BOOL
    jmp .done
.contains_pop_null:
    pop rsi
    jmp .null_ret
.builtin_substring:
    cmp r15, 2
    jl .arg_err
    cmp r15, 3
    jg .arg_err
    mov rax, [r14]
    call interp_eval
    cmp rax, SC_T_STRING
    jne .null_ret
    push rdx              ; s
    mov rax, [r14+8]
    call interp_eval
    cmp rax, SC_T_INT
    jne .sub_pop1_null
    push rdx              ; start
    cmp r15, 3
    je .sub_len3
    mov rdx, 0x7FFFFFFFFFFFFFFF
    jmp .sub_do
.sub_len3:
    mov rax, [r14+16]
    call interp_eval
    cmp rax, SC_T_INT
    jne .sub_pop2_null
.sub_do:
    mov rcx, rdx          ; len
    pop rdx               ; start
    pop rsi               ; s
    call rt_str_substring
    mov rdx, rax
    mov rax, SC_T_STRING
    jmp .done
.sub_pop1_null:
    pop rsi
    jmp .null_ret
.sub_pop2_null:
    pop rdx
    pop rsi
    jmp .null_ret
.builtin_push:
    cmp r15, 2
    jne .arg_err
    mov rax, [r14]
    call interp_eval
    cmp rax, SC_T_ARRAY
    jne .null_ret
    push rdx              ; array
    mov rax, [r14+8]
    call interp_eval      ; vtype, vpayload
    mov r8, rax
    mov r9, rdx
    pop rax               ; array
    mov rdx, r8
    mov rcx, r9
    call rt_array_push    ; rax = new array
    push rax
    mov rax, [r14]        ; arg0 node
    cmp qword [rax], AST_VAR
    jne .push_done_pop
    mov rsi, [rax+16]     ; name
    mov rax, SC_T_ARRAY
    mov rdx, [rsp]        ; new array
    call rt_set_var
.push_done_pop:
    pop rdx
    mov rax, SC_T_ARRAY
    jmp .done
.builtin_pop:
    cmp r15, 1
    jne .arg_err
    mov rax, [r14]
    call interp_eval
    cmp rax, SC_T_ARRAY
    jne .null_ret
    mov rax, rdx
    call rt_array_pop
    jmp .done
.builtin_readfile:
    cmp r15, 1
    jne .arg_err
    mov rax, [r14]
    call interp_eval
    cmp rax, SC_T_STRING
    jne .null_ret
    mov rsi, rdx
    call load_file        ; RSI=buf, RDX=size (fatal on error)
    mov rdx, rsi
    mov rax, SC_T_STRING
    jmp .done
.builtin_writefile:
    cmp r15, 2
    jne .arg_err
    mov rax, [r14]
    call interp_eval
    cmp rax, SC_T_STRING
    jne .null_ret
    push rdx              ; path
    mov rax, [r14+8]
    call interp_eval
    cmp rax, SC_T_STRING
    jne .wf_pop_null
    mov rsi, rdx          ; data
    call strlen
    mov rcx, rax          ; len
    mov rdx, rsi          ; data
    pop rsi               ; path
    call rt_write_file
    cmp rax, -1
    je .null_ret
    mov rdx, rax
    mov rax, SC_T_INT
    jmp .done
.wf_pop_null:
    pop rsi
    jmp .null_ret
.builtin_abs:
    cmp r15, 1
    jne .arg_err
    mov rax, [r14]
    call interp_eval
    cmp rax, SC_T_INT
    je .abs_int
    cmp rax, SC_T_FLOAT
    je .abs_float
    jmp .null_ret
.abs_int:
    test rdx, rdx
    jns .abs_done
    neg rdx
.abs_done:
    mov rax, SC_T_INT
    jmp .done
.abs_float:
    mov rax, 0x7FFFFFFFFFFFFFFF
    movq xmm0, rdx
    movq xmm1, rax
    andpd xmm0, xmm1
    movq rdx, xmm0
    mov rax, SC_T_FLOAT
    jmp .done
.builtin_min:
    cmp r15, 2
    jne .arg_err
    mov rax, [r14]
    call interp_eval
    push rax
    push rdx
    mov rax, [r14+8]
    call interp_eval
    mov r8, rax
    mov r9, rdx
    pop rdx
    pop rax
    cmp rax, SC_T_FLOAT
    je .min_float
    cmp r8, SC_T_FLOAT
    je .min_float
    cmp rax, SC_T_INT
    jne .null_ret
    cmp r8, SC_T_INT
    jne .null_ret
    cmp rdx, r9
    jle .min_keep
    mov rax, r8
    mov rdx, r9
.min_keep:
    jmp .done
.min_float:
    cmp rax, SC_T_INT
    jne .min_fa
    cvtsi2sd xmm0, rdx
    jmp .min_fb
.min_fa:
    cmp rax, SC_T_FLOAT
    jne .null_ret
    movq xmm0, rdx
.min_fb:
    cmp r8, SC_T_INT
    jne .min_gb
    cvtsi2sd xmm1, r9
    jmp .min_cmp
.min_gb:
    cmp r8, SC_T_FLOAT
    jne .null_ret
    movq xmm1, r9
.min_cmp:
    comisd xmm0, xmm1
    jbe .min_keep
    mov rax, r8
    mov rdx, r9
    jmp .done
.builtin_max:
    cmp r15, 2
    jne .arg_err
    mov rax, [r14]
    call interp_eval
    push rax
    push rdx
    mov rax, [r14+8]
    call interp_eval
    mov r8, rax
    mov r9, rdx
    pop rdx
    pop rax
    cmp rax, SC_T_FLOAT
    je .max_float
    cmp r8, SC_T_FLOAT
    je .max_float
    cmp rax, SC_T_INT
    jne .null_ret
    cmp r8, SC_T_INT
    jne .null_ret
    cmp rdx, r9
    jge .max_keep
    mov rax, r8
    mov rdx, r9
.max_keep:
    jmp .done
.max_float:
    cmp rax, SC_T_INT
    jne .max_fa
    cvtsi2sd xmm0, rdx
    jmp .max_fb
.max_fa:
    cmp rax, SC_T_FLOAT
    jne .null_ret
    movq xmm0, rdx
.max_fb:
    cmp r8, SC_T_INT
    jne .max_gb
    cvtsi2sd xmm1, r9
    jmp .max_cmp
.max_gb:
    cmp r8, SC_T_FLOAT
    jne .null_ret
    movq xmm1, r9
.max_cmp:
    comisd xmm0, xmm1
    jae .max_keep
    mov rax, r8
    mov rdx, r9
    jmp .done
.builtin_sqrt:
    cmp r15, 1
    jne .arg_err
    mov rax, [r14]
    call interp_eval
    cmp rax, SC_T_INT
    je .sqrt_int
    cmp rax, SC_T_FLOAT
    jne .null_ret
    movq xmm0, rdx
    sqrtsd xmm0, xmm0
    movq rdx, xmm0
    mov rax, SC_T_FLOAT
    jmp .done
.sqrt_int:
    cvtsi2sd xmm0, rdx
    sqrtsd xmm0, xmm0
    movq rdx, xmm0
    mov rax, SC_T_FLOAT
    jmp .done
.arg_err:
    mov rsi, [r13+16]
    lea rsi, [rt_err_arg]
    call print_cstr
    mov rsi, [r13+16]
    call print_cstr
    lea rsi, [rt_err_arg2]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x20
    call ExitProcess
.builtin_sleep:
    test r15, r15
    jz .sleep_zero
    mov rax, [r14]
    call interp_eval
    mov ecx, edx
    sub rsp, 0x20
    call Sleep
    add rsp, 0x20
    mov rax, SC_T_NULL
    xor edx, edx
    jmp .done
.sleep_zero:
    xor ecx, ecx
    sub rsp, 0x20
    call Sleep
    add rsp, 0x20
    mov rax, SC_T_NULL
    xor edx, edx
    jmp .done

.builtin_time:
    sub rsp, 0x20
    call GetTickCount64
    add rsp, 0x20
    mov rdx, rax
    mov rax, SC_T_INT
    jmp .done

.builtin_beep:
    mov ecx, 750
    mov edx, 300
    test r15, r15
    jz .do_beep
    mov rax, [r14]
    call interp_eval
    mov r12, rdx
    cmp r15, 1
    je .beep_one
    push r12
    mov rax, [r14 + 1*8]
    call interp_eval
    pop r12
    mov ecx, r12d
    jmp .do_beep
.beep_one:
    mov ecx, r12d
    mov edx, 300
.do_beep:
    sub rsp, 0x20
    call Beep
    add rsp, 0x20
    mov rax, SC_T_NULL
    xor edx, edx
    jmp .done

.builtin_random:
    mov rax, [prng_seed]
    test rax, rax
    jnz .prng_step
    sub rsp, 0x20
    call GetTickCount64
    add rsp, 0x20
    test rax, rax
    jnz .prng_seeded
    mov rax, 0x9E3779B97F4A7C15
.prng_seeded:
    mov [prng_seed], rax
.prng_step:
    mov rax, [prng_seed]
    mov rdx, rax
    shl rdx, 12
    xor rax, rdx
    mov rdx, rax
    shr rdx, 25
    xor rax, rdx
    mov rdx, rax
    shl rdx, 27
    xor rax, rdx
    mov [prng_seed], rax
    mov rcx, 0x2545F4914F6CDD1D
    imul rax, rcx
    btr rax, 63
    mov rbx, rax
    test r15, r15
    jz .rand_zero
    cmp r15, 1
    je .rand_one
    push rbx
    mov rax, [r14]
    call interp_eval
    mov r12, rdx
    mov rax, [r14 + 1*8]
    call interp_eval
    mov r13, rdx
    pop rbx
    sub r13, r12
    inc r13
    cmp r13, 0
    jle .rand_min_only
    xor edx, edx
    mov rax, rbx
    div r13
    add rdx, r12
    mov rax, SC_T_INT
    jmp .done
.rand_min_only:
    mov rdx, r12
    mov rax, SC_T_INT
    jmp .done
.rand_one:
    push rbx
    mov rax, [r14]
    call interp_eval
    mov rcx, rdx
    pop rbx
    test rcx, rcx
    jle .rand_zero
    xor edx, edx
    mov rax, rbx
    div rcx
    mov rax, SC_T_INT
    jmp .done
.rand_zero:
    mov rcx, 1000000
    xor edx, edx
    mov rax, rbx
    div rcx
    mov rax, SC_T_INT
    jmp .done

.builtin_alert:
    test r15, r15
    jz .alert_empty
    cmp r15, 1
    je .alert_one_arg
    mov rax, [r14]
    call interp_eval
    mov r12, rdx
    mov rax, [r14 + 1*8]
    call interp_eval
    mov r13, rdx
    jmp .do_alert
.alert_one_arg:
    lea r12, [s_alert]
    mov rax, [r14]
    call interp_eval
    mov r13, rdx
    jmp .do_alert
.alert_empty:
    lea r12, [s_alert]
    lea r13, [s_alert]
.do_alert:
    lea rcx, [user32_dll]
    sub rsp, 0x20
    call LoadLibraryA
    add rsp, 0x20
    test rax, rax
    jz .alert_done
    mov rbx, rax
    mov rcx, rbx
    lea rdx, [msgbox_proc]
    sub rsp, 0x20
    call GetProcAddress
    add rsp, 0x20
    test rax, rax
    jz .alert_done
    mov r10, rax
    xor ecx, ecx
    mov rdx, r13
    mov r8, r12
    xor r9d, r9d
    sub rsp, 0x28
    call r10
    add rsp, 0x28
.alert_done:
    mov rax, SC_T_NULL
    xor edx, edx
    jmp .done

.builtin_file_exists:
    test r15, r15
    jz .fe_no
    mov rax, [r14]
    call interp_eval
    mov rcx, rdx
    sub rsp, 0x20
    call GetFileAttributesA
    add rsp, 0x20
    cmp eax, 0xFFFFFFFF
    je .fe_no
    mov rax, SC_T_INT
    mov rdx, 1
    jmp .done
.fe_no:
    mov rax, SC_T_INT
    xor edx, edx
    jmp .done

.builtin_delete_file:
    test r15, r15
    jz .del_no
    mov rax, [r14]
    call interp_eval
    mov rcx, rdx
    sub rsp, 0x20
    call DeleteFileA
    add rsp, 0x20
    test eax, eax
    jz .del_no
    mov rax, SC_T_INT
    mov rdx, 1
    jmp .done
.del_no:
    mov rax, SC_T_INT
    xor edx, edx
    jmp .done

.builtin_make_dir:
    test r15, r15
    jz .md_no
    mov rax, [r14]
    call interp_eval
    mov rcx, rdx
    xor edx, edx
    sub rsp, 0x20
    call CreateDirectoryA
    add rsp, 0x20
    test eax, eax
    jz .md_no
    mov rax, SC_T_INT
    mov rdx, 1
    jmp .done
.md_no:
    mov rax, SC_T_INT
    xor edx, edx
    jmp .done

.builtin_get_env:
    test r15, r15
    jz .ge_null
    mov rax, [r14]
    call interp_eval
    mov rcx, rdx
    lea rdx, [env_buf]
    mov r8d, 4096
    sub rsp, 0x20
    call GetEnvironmentVariableA
    add rsp, 0x20
    test eax, eax
    jz .ge_null
    lea rsi, [env_buf]
    call rt_str_new_copy
    mov rdx, rax
    mov rax, SC_T_STRING
    jmp .done
.ge_null:
    mov rax, SC_T_NULL
    xor edx, edx
    jmp .done

.builtin_set_env:
    cmp r15, 2
    jl .se_no
    mov rax, [r14]
    call interp_eval
    mov r12, rdx
    mov rax, [r14 + 1*8]
    call interp_eval
    mov rcx, r12
    sub rsp, 0x20
    call SetEnvironmentVariableA
    add rsp, 0x20
    test eax, eax
    jz .se_no
    mov rax, SC_T_INT
    mov rdx, 1
    jmp .done
.se_no:
    mov rax, SC_T_INT
    xor edx, edx
    jmp .done

.builtin_set_color:
    test r15, r15
    jz .sc_done
    mov rax, [r14]
    call interp_eval
    mov r12, rdx
    mov ecx, STD_OUTPUT_HANDLE
    call GetStdHandle
    mov rcx, rax
    mov edx, r12d
    sub rsp, 0x20
    call SetConsoleTextAttribute
    add rsp, 0x20
.sc_done:
    mov rax, SC_T_NULL
    xor edx, edx
    jmp .done

.builtin_system:
    test r15, r15
    jz .sys_no
    mov rax, [r14]
    call interp_eval
    mov r12, rdx
    lea rdi, [start_info]
    xor eax, eax
    mov ecx, 104
    rep stosb
    mov dword [start_info], 104
    lea rdi, [proc_info]
    mov ecx, 24
    rep stosb
    xor ecx, ecx
    mov rdx, r12
    xor r8d, r8d
    xor r9d, r9d
    sub rsp, 0x40
    mov qword [rsp + 0x20], 0
    mov qword [rsp + 0x28], 0
    mov qword [rsp + 0x30], 0
    mov qword [rsp + 0x38], 0
    lea rax, [start_info]
    mov [rsp + 0x40], rax
    lea rax, [proc_info]
    mov [rsp + 0x48], rax
    call CreateProcessA
    add rsp, 0x40
    test eax, eax
    jz .sys_no
    mov rcx, [proc_info]
    mov edx, 0xFFFFFFFF
    sub rsp, 0x20
    call WaitForSingleObject
    add rsp, 0x20
    mov rcx, [proc_info]
    lea rdx, [env_buf]
    sub rsp, 0x20
    call GetExitCodeProcess
    add rsp, 0x20
    mov rcx, [proc_info]
    call CloseHandle
    mov rcx, [proc_info + 8]
    call CloseHandle
    mov eax, dword [env_buf]
    movsxd rdx, eax
    mov rax, SC_T_INT
    jmp .done
.sys_no:
    mov rax, SC_T_INT
    mov rdx, -1
    jmp .done

.builtin_set_clip:
    test r15, r15
    jz .clip_fail
    mov rax, [r14]
    call interp_eval
    mov r12, rdx
    lea rcx, [user32_dll]
    sub rsp, 0x20
    call LoadLibraryA
    add rsp, 0x20
    test rax, rax
    jz .clip_fail
    mov rbx, rax
    mov rcx, rbx
    lea rdx, [open_clip_proc]
    sub rsp, 0x20
    call GetProcAddress
    add rsp, 0x20
    test rax, rax
    jz .clip_fail
    xor ecx, ecx
    sub rsp, 0x20
    call rax
    add rsp, 0x20
    test eax, eax
    jz .clip_fail
    mov rcx, rbx
    lea rdx, [empty_clip_proc]
    sub rsp, 0x20
    call GetProcAddress
    add rsp, 0x20
    sub rsp, 0x20
    call rax
    add rsp, 0x20
    mov rsi, r12
    call strlen
    inc rax
    mov r13, rax
    mov ecx, 2
    mov rdx, r13
    sub rsp, 0x20
    call GlobalAlloc
    add rsp, 0x20
    test rax, rax
    jz .clip_close
    mov r14, rax
    mov rcx, r14
    sub rsp, 0x20
    call GlobalLock
    add rsp, 0x20
    mov rdi, rax
    mov rsi, r12
    mov rcx, r13
    rep movsb
    mov rcx, r14
    sub rsp, 0x20
    call GlobalUnlock
    add rsp, 0x20
    mov rcx, rbx
    lea rdx, [set_clip_proc]
    sub rsp, 0x20
    call GetProcAddress
    add rsp, 0x20
    mov ecx, 1
    mov rdx, r14
    sub rsp, 0x20
    call rax
    add rsp, 0x20
.clip_close:
    mov rcx, rbx
    lea rdx, [close_clip_proc]
    sub rsp, 0x20
    call GetProcAddress
    add rsp, 0x20
    sub rsp, 0x20
    call rax
    add rsp, 0x20
    mov rax, SC_T_INT
    mov rdx, 1
    jmp .done
.clip_fail:
    mov rax, SC_T_INT
    xor edx, edx
    jmp .done

.builtin_get_clip:
    lea rcx, [user32_dll]
    sub rsp, 0x20
    call LoadLibraryA
    add rsp, 0x20
    test rax, rax
    jz .gclip_null
    mov rbx, rax
    mov rcx, rbx
    lea rdx, [open_clip_proc]
    sub rsp, 0x20
    call GetProcAddress
    add rsp, 0x20
    test rax, rax
    jz .gclip_null
    xor ecx, ecx
    sub rsp, 0x20
    call rax
    add rsp, 0x20
    test eax, eax
    jz .gclip_null
    mov rcx, rbx
    lea rdx, [get_clip_proc]
    sub rsp, 0x20
    call GetProcAddress
    add rsp, 0x20
    mov ecx, 1
    sub rsp, 0x20
    call rax
    add rsp, 0x20
    mov r12, rax
    test r12, r12
    jz .gclip_close
    mov rsi, r12
    call rt_str_new_copy
    mov r13, rax
    mov rcx, rbx
    lea rdx, [close_clip_proc]
    sub rsp, 0x20
    call GetProcAddress
    add rsp, 0x20
    sub rsp, 0x20
    call rax
    add rsp, 0x20
    mov rax, SC_T_STRING
    mov rdx, r13
    jmp .done
.gclip_close:
    mov rcx, rbx
    lea rdx, [close_clip_proc]
    sub rsp, 0x20
    call GetProcAddress
    add rsp, 0x20
    sub rsp, 0x20
    call rax
    add rsp, 0x20
.gclip_null:
    mov rax, SC_T_NULL
    xor edx, edx
    jmp .done

.builtin_http_get:
    test r15, r15
    jz .http_null
    mov rax, [r14]
    call interp_eval
    mov r12, rdx
    lea rcx, [wininet_dll]
    sub rsp, 0x20
    call LoadLibraryA
    add rsp, 0x20
    test rax, rax
    jz .http_null
    mov rbx, rax
    mov rcx, rbx
    lea rdx, [net_open_proc]
    sub rsp, 0x20
    call GetProcAddress
    add rsp, 0x20
    test rax, rax
    jz .http_null
    lea rcx, [http_ua]
    mov edx, 1
    xor r8d, r8d
    xor r9d, r9d
    sub rsp, 0x30
    mov qword [rsp + 0x20], 0
    call rax
    add rsp, 0x30
    test rax, rax
    jz .http_null
    mov r13, rax
    mov rcx, rbx
    lea rdx, [net_url_proc]
    sub rsp, 0x20
    call GetProcAddress
    add rsp, 0x20
    mov rcx, r13
    mov rdx, r12
    xor r8d, r8d
    xor r9d, r9d
    sub rsp, 0x30
    mov r10, 0x80000000
    mov [rsp + 0x20], r10
    mov qword [rsp + 0x28], 0
    call rax
    add rsp, 0x30
    test rax, rax
    jz .http_close_net
    mov r14, rax
    mov rcx, rbx
    lea rdx, [net_read_proc]
    sub rsp, 0x20
    call GetProcAddress
    add rsp, 0x20
    mov rcx, r14
    lea rdx, [http_buf]
    mov r8d, 65535
    lea r9, [net_bytes_read]
    sub rsp, 0x20
    call rax
    add rsp, 0x20
    mov eax, [net_bytes_read]
    mov byte [http_buf + rax], 0
    mov rcx, rbx
    lea rdx, [net_close_proc]
    sub rsp, 0x20
    call GetProcAddress
    add rsp, 0x20
    mov r15, rax
    mov rcx, r14
    sub rsp, 0x20
    call r15
    add rsp, 0x20
    mov rcx, r13
    sub rsp, 0x20
    call r15
    add rsp, 0x20
    lea rsi, [http_buf]
    call rt_str_new_copy
    mov rdx, rax
    mov rax, SC_T_STRING
    jmp .done
.http_close_net:
    mov rcx, rbx
    lea rdx, [net_close_proc]
    sub rsp, 0x20
    call GetProcAddress
    add rsp, 0x20
    mov rcx, r13
    sub rsp, 0x20
    call rax
    add rsp, 0x20
.http_null:
    mov rax, SC_T_NULL
    xor edx, edx
    jmp .done

.builtin_clear_screen:
    mov ecx, STD_OUTPUT_HANDLE
    sub rsp, 0x20
    call GetStdHandle
    mov rcx, rax
    xor edx, edx
    call SetConsoleCursorPosition
    add rsp, 0x20
    mov rax, SC_T_NULL
    xor edx, edx
    jmp .done

.builtin_key_pressed:
    mov rax, [async_key_ptr]
    test rax, rax
    jnz .kp_ready
    lea rcx, [user32_dll]
    sub rsp, 0x20
    call LoadLibraryA
    add rsp, 0x20
    test rax, rax
    jz .kp_fail
    mov rcx, rax
    lea rdx, [async_key_proc]
    sub rsp, 0x20
    call GetProcAddress
    add rsp, 0x20
    test rax, rax
    jz .kp_fail
    mov [async_key_ptr], rax

.kp_ready:
    test r15, r15
    jz .kp_default
    mov rax, [r14]
    call interp_eval
    cmp rax, SC_T_STRING
    je .kp_str
    mov ecx, edx
    jmp .kp_call
.kp_str:
    test rdx, rdx
    jz .kp_fail
    movzx ecx, byte [rdx]
    cmp cl, 'a'
    jb .kp_call
    cmp cl, 'z'
    ja .kp_call
    sub ecx, 32
.kp_call:
    mov rax, [async_key_ptr]
    sub rsp, 0x20
    call rax
    add rsp, 0x20
    test ax, 0x8000
    jnz .kp_true
    jmp .kp_false

.kp_default:
    mov ecx, 32
    mov rax, [async_key_ptr]
    sub rsp, 0x20
    call rax
    add rsp, 0x20
    test ax, 0x8000
    jnz .kp_true
    mov ecx, 38
    mov rax, [async_key_ptr]
    sub rsp, 0x20
    call rax
    add rsp, 0x20
    test ax, 0x8000
    jnz .kp_true
    mov ecx, 87
    mov rax, [async_key_ptr]
    sub rsp, 0x20
    call rax
    add rsp, 0x20
    test ax, 0x8000
    jnz .kp_true
    jmp .kp_false

.kp_true:
    mov rax, SC_T_INT
    mov rdx, 1
    jmp .done

.kp_false:
.kp_fail:
    mov rax, SC_T_INT
    xor edx, edx
    jmp .done

.user_call:
    ; r13=callee node, r14=args base, r15=arg count
    ; Frame (8 slots, 64 bytes, keeps RSP%16==0 so calls stay aligned):
    ; [rsp]=index [rsp+8]=name [rsp+16]=pcount [rsp+24]=params
    ; [rsp+32]=body [rsp+40]=argsbase [rsp+48]=argcount [rsp+56]=varcount
    mov rsi, [r13+16]
    call rt_find_func
    cmp rax, -1
    je .undef_func
    imul rbx, rax, 32
    lea rbx, [rt_funcs+rbx]
    mov rax, [rbx+8]              ; param count
    cmp rax, r15
    jne .arg_err2                 ; r13 still = callee node here
    push qword [rt_var_count]     ; varcount
    push r15                      ; argcount
    push r14                      ; argsbase
    push qword [rbx+24]           ; body
    push qword [rbx+16]           ; params
    push rax                      ; pcount
    push qword [rbx]              ; name
    push qword 0                  ; index
.ucl_loop:
    mov r15, [rsp]                ; index
    mov rax, [rsp+16]             ; pcount
    cmp r15, rax
    jae .ucl_body
    mov rbx, [rsp+40]             ; argsbase
    mov rax, [rbx+r15*8]
    call interp_eval              ; rax=type, rdx=payload
    mov r15, [rsp]                ; index (reload: eval preserves regs but be safe)
    mov r13, [rsp+24]             ; params
    mov rsi, [r13+r15*8]
    call rt_push_var              ; params shadow outer vars (recursion-safe)
    inc qword [rsp]
    jmp .ucl_loop
.ucl_body:
    mov rax, [rsp+32]             ; body
    call interp_exec
    cmp qword [interp_has_ret], 0
    je .ucl_noret
    mov rax, [interp_ret_type]
    mov rdx, [interp_ret_payload]
    mov qword [interp_has_ret], 0
    jmp .ucl_finish
.ucl_noret:
    mov rax, SC_T_NULL
    xor edx, edx
.ucl_finish:
    mov rbx, rax
    mov r12, rdx
    add rsp, 56                   ; drop index..argcount (7 slots)
    pop r15                       ; varcount
    mov [rt_var_count], r15
    mov rax, rbx
    mov rdx, r12
    jmp .done
.undef_func:
    mov rsi, [r13+16]
    call rt_error_undef
    jmp .done
.arg_err2:
    push r13
    lea rsi, [rt_err_arg]
    call print_cstr
    pop r13
    push r13
    mov rsi, [r13+16]
    call print_cstr
    lea rsi, [rt_err_arg2]
    call print_cstr
    pop r13
    mov ecx, 1
    sub rsp, 0x28
    call ExitProcess
.array:
    mov r13, [r12+16]   ; elem base
    mov r15, [r12+8]    ; count
    mov rcx, r15
    call rt_array_new   ; rax=array (preserves r13/r15)
    push rax            ; array   [rsp+24]
    push r13            ; base    [rsp+16]
    push r15            ; count   [rsp+8]
    push qword 0        ; index   [rsp]
.arr_loop:
    mov rax, [rsp]
    cmp rax, [rsp+8]
    jae .arr_done
    mov rdx, [rsp+16]
    mov rax, [rdx+rax*8]
    call interp_eval    ; rax=type, rdx=payload
    mov r8, rax
    mov r9, rdx
    mov rax, [rsp]      ; index
    mov rcx, [rsp+24]   ; array
    imul rax, rax, 16
    lea rax, [rcx+rax+16]
    mov [rax], r8
    mov [rax+8], r9
    mov rax, [rsp+24]
    inc qword [rax]
    inc qword [rsp]
    jmp .arr_loop
.arr_done:
    mov rbx, [rsp+24]
    add rsp, 32
    mov rdx, rbx
    mov rax, SC_T_ARRAY
    jmp .done
.object:
    mov r13, [r12+16]   ; keys
    mov r14, [r12+24]   ; vals
    mov r15, [r12+8]    ; count
    mov rcx, r15
    call rt_object_new  ; rax=obj (preserves r13-r15)
    push rax            ; obj     [rsp+40]
    push r13            ; keys    [rsp+32]
    push r14            ; vals    [rsp+24]
    push r15            ; count   [rsp+16]
    push qword 0        ; index   [rsp+8]
    push qword 0        ; pad     [rsp]
.obj_loop:
    mov rax, [rsp+8]    ; index
    cmp rax, [rsp+16]   ; count
    jae .obj_done
    mov rdx, [rsp+24]   ; vals
    mov rax, [rdx+rax*8]
    call interp_eval    ; rax=type, rdx=payload
    mov r8, rax
    mov r9, rdx
    mov rax, [rsp+8]    ; index
    mov rdx, [rsp+32]   ; keys
    mov rsi, [rdx+rax*8]
    mov rdx, r8         ; type
    mov rcx, r9         ; payload
    mov rax, [rsp+40]   ; obj
    call rt_object_set  ; rax=obj (maybe grown)
    mov [rsp+40], rax
    inc qword [rsp+8]
    jmp .obj_loop
.obj_done:
    mov rbx, [rsp+40]
    add rsp, 48
    mov rdx, rbx
    mov rax, SC_T_OBJECT
    jmp .done
.index:
    mov rax, [r12+16]
    call interp_eval
    push rax            ; btype
    push rdx            ; bpayload
    mov rax, [r12+24]
    call interp_eval    ; itype, ipayload
    mov r8, rax
    mov r9, rdx
    pop rdx             ; bpayload
    pop rax             ; btype
    cmp rax, SC_T_ARRAY
    jne .idx_null
    cmp r8, SC_T_INT
    jne .idx_null
    mov rax, rdx        ; array
    mov rcx, r9         ; index
    call rt_array_get
    jmp .done
.idx_null:
    mov rax, SC_T_NULL
    xor edx, edx
    jmp .done
.member:
    mov rax, [r12+16]
    call interp_eval
    cmp rax, SC_T_OBJECT
    jne .mem_null
    mov rax, rdx        ; obj
    mov rsi, [r12+24]   ; key
    call rt_object_get
    jmp .done
.mem_null:
    mov rax, SC_T_NULL
    xor edx, edx
    jmp .done
.done:
    add rsp, 0x20
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------- interp_exec(RAX=node) ----------
interp_exec:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 0x08
    mov r12, rax
    cmp qword [interp_has_ret], 0
    jne .ret
    mov rax, [r12]
    cmp rax, AST_PROGRAM
    je .program
    cmp rax, AST_BLOCK
    je .block
    cmp rax, AST_ASSIGN
    je .assign
    cmp rax, AST_EXPRSTMT
    je .exprstmt
    cmp rax, AST_IF
    je .if
    cmp rax, AST_WHILE
    je .while
    cmp rax, AST_FNDEF
    je .fndef
    cmp rax, AST_RETURN
    je .return
    cmp rax, AST_IMPORT
    je .import
    cmp rax, AST_BREAK
    je .break
    cmp rax, AST_CONTINUE
    je .continue
    cmp rax, AST_FOR
    je .for
    ; unknown
    jmp .ret
.program:
    mov r13, [r12+16] ; base
    mov r14, [r12+8]  ; count
    xor r15d, r15d
.prog_loop:
    cmp r15, r14
    jae .ret
    cmp qword [interp_has_ret], 0
    jne .ret
    cmp qword [interp_has_break], 0
    jne .ret
    cmp qword [interp_has_continue], 0
    jne .ret
    mov rax, [r13 + r15*8]
    call interp_exec
    inc r15
    jmp .prog_loop
.block:
    mov r13, [r12+16]
    mov r14, [r12+8]
    xor r15d, r15d
.blk_loop:
    cmp r15, r14
    jae .ret
    cmp qword [interp_has_ret], 0
    jne .ret
    cmp qword [interp_has_break], 0
    jne .ret
    cmp qword [interp_has_continue], 0
    jne .ret
    mov rax, [r13 + r15*8]
    call interp_exec
    inc r15
    jmp .blk_loop
.assign:
    mov r13, [r12+16] ; var node
    mov r14, [r12+24] ; expr
    mov rax, r14
    call interp_eval
    mov r14, rax
    mov r15, rdx
    mov rsi, [r13+16]
    mov rax, r14
    mov rdx, r15
    call rt_set_var
    jmp .ret
.exprstmt:
    mov rax, [r12+16]
    call interp_eval
    cmp qword [repl_echo], 0
    je .ret
    ; REPL echo: print value unless it's a print/println call
    push rax
    push rdx
    mov rax, [r12+16]         ; expr node
    cmp qword [rax], AST_CALL
    jne .echo_it
    mov rax, [rax+16]         ; callee
    cmp qword [rax], AST_VAR
    jne .echo_it
    mov rsi, [rax+16]         ; name
    mov rdi, s_print
    push rsi
    call streq
    pop rsi
    test eax, eax
    jnz .no_echo_pop
    mov rdi, s_println
    push rsi
    call streq
    pop rsi
    test eax, eax
    jnz .no_echo_pop
.echo_it:
    pop rdx
    pop rax
    push rax
    push rdx
    call rt_print_value_nl
    pop rdx
    pop rax
    jmp .ret
.no_echo_pop:
    pop rdx
    pop rax
    jmp .ret
.if:
    mov rax, [r12+16]
    call interp_eval
    call interp_is_truthy
    test eax, eax
    jz .if_else
    mov rax, [r12+24]
    call interp_exec
    jmp .ret
.if_else:
    mov rax, [r12+32]
    test rax, rax
    jz .ret
    call interp_exec
    jmp .ret
.while:
    mov r13, [r12+16] ; cond
    mov r14, [r12+24] ; body
.while_loop:
    cmp qword [interp_has_ret], 0
    jne .ret
    mov rax, r13
    call interp_eval
    call interp_is_truthy
    test eax, eax
    jz .ret
    mov rax, r14
    call interp_exec
    cmp qword [interp_has_ret], 0
    jne .ret
    cmp qword [interp_has_break], 0
    jne .while_break
    mov qword [interp_has_continue], 0
    jmp .while_loop
.while_break:
    mov qword [interp_has_break], 0
    jmp .ret
.fndef:
    mov rsi, [r12+16]
    mov rdx, [r12+8]
    mov rcx, [r12+24]
    mov r8, [r12+32]
    call rt_add_func
    jmp .ret
.return:
    mov rax, [r12+16]
    test rax, rax
    jz .ret_null
    call interp_eval
    mov [interp_ret_type], rax
    mov [interp_ret_payload], rdx
    mov qword [interp_has_ret], 1
    jmp .ret
.ret_null:
    mov qword [interp_ret_type], SC_T_NULL
    mov qword [interp_ret_payload], 0
    mov qword [interp_has_ret], 1
    jmp .ret
.import:
    mov rsi, [r12+16]     ; module name/path string
    call interp_import_file
    jmp .ret
.break:
    mov qword [interp_has_break], 1
    jmp .ret
.continue:
    mov qword [interp_has_continue], 1
    jmp .ret
.for:
    mov r13, [r12+16] ; var name
    mov rax, [r12+24] ; arr expr
    call interp_eval
    cmp rax, SC_T_ARRAY
    jne .ret
    mov r14, rdx      ; array heap ptr
    mov rbx, [r14]    ; array length
    xor r15d, r15d    ; index i = 0
.for_loop:
    cmp r15, [r14]
    jae .for_done
    cmp qword [interp_has_ret], 0
    jne .for_done
    cmp qword [interp_has_break], 0
    jne .for_break
    mov rcx, r15
    shl rcx, 4
    add rcx, r14
    mov rax, [rcx + 16]
    mov rdx, [rcx + 24]
    mov rsi, r13
    call rt_set_var
    mov rax, [r12+32] ; body block
    call interp_exec
    cmp qword [interp_has_ret], 0
    jne .for_done
    cmp qword [interp_has_break], 0
    jne .for_break
    mov qword [interp_has_continue], 0
    inc r15
    jmp .for_loop
.for_break:
    mov qword [interp_has_break], 0
.for_done:
    jmp .ret
.ret:
    add rsp, 0x08
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
