; ShitCam compiler - AST -> x86-64 NASM text -> assemble+link -> native .exe
; v1 subset: int/string literals+vars, int arithmetic+compare, print/println,
; if/else, while, assignment. Clean errors for the rest (use interpreter).
; Variables: flat table (matches interpreter block semantics).

%define CG_VAR_ENTRY_SIZE 24
%define CG_MAX_STRLITS 1024

section .data
    cg_err_line1  db "Compile error at line ", 0
    cg_err_line2  db ": ", 0
    cg_err_nonint db "integer arithmetic needs integer operands (interpreter supports more)", 0
    cg_err_undef  db "undefined variable (define before use in compiled code)", 0
    cg_err_unsup  db "not supported by compiler v1 (use interpreter for this file)", 0
    cg_err_nostr  db "compiler v1: string concat needs interpreter", 0
    cg_err_open   db "Error: cannot write output file '", 0
    cg_err_nasm   db "Error: assembler failed", 13, 10, 0
    cg_err_link   db "Error: linker failed", 13, 10, 0
    cg_err_tool   db "Error: build toolchain not found (rebuild shitcam first)", 13, 10, 0
    cg_built_pre  db "Built ", 0
    cg_h_default  db "default rel", 10, "bits 64", 10, 0
    cg_h_data     db "section .data", 10, 0
    cg_h_bss      db "section .bss", 10, 0
    cg_h_text     db "section .text", 10, 0
    cg_h_ext      db "extern GetStdHandle, WriteFile, ExitProcess", 10, "global main", 10, 0
    cg_h_main     db "main:", 10, "sub rsp, 0x28", 10, "mov ecx, -11", 10, "call GetStdHandle", 10, "mov [sc_stdout], rax", 10, "add rsp, 0x28", 10, 0
    cg_h_epil     db "xor ecx, ecx", 10, "sub rsp, 0x28", 10, "call ExitProcess", 10, 0
    cg_b_res      db "sc_stdout resq 1", 10, "sc_numbuf resb 32", 10, 0
    cg_d_init     db "sc_space db 32, 0", 10, "sc_crlf db 13, 10, 0", 10, "sc_divmsg db 68, 105, 118, 105, 115, 105, 111, 110, 32, 98, 121, 32, 122, 101, 114, 111, 13, 10, 0", 10, 0
    cg_t_write    db "sc_write:", 10, "push rbx", 10, "sub rsp, 0x30", 10, "mov rcx, [sc_stdout]", 10, "mov r8, rdx", 10, "mov rdx, rsi", 10, "lea r9, [rsp+0x28]", 10, "mov qword [rsp+0x20], 0", 10, "call WriteFile", 10, "add rsp, 0x30", 10, "pop rbx", 10, "ret", 10, 0
    cg_t_strlen   db "sc_strlen:", 10, "xor eax, eax", 10, ".l: cmp byte [rsi+rax], 0", 10, "je .d", 10, "inc rax", 10, "jmp .l", 10, ".d: ret", 10, 0
    cg_t_pint     db "sc_print_int:", 10, "push rbx", 10, "push r12", 10, "sub rsp, 0x28", 10, "mov rbx, rax", 10, "xor r12d, r12d", 10, "test rbx, rbx", 10, "jns .pos", 10, "neg rbx", 10, "inc r12d", 10, ".pos: lea rsi, [sc_numbuf+31]", 10, "mov byte [rsi], 0", 10, "mov rax, rbx", 10, "mov rcx, 10", 10, "test rax, rax", 10, "jnz .digits", 10, "dec rsi", 10, "mov byte [rsi], 48", 10, "jmp .out", 10, ".digits: xor edx, edx", 10, "div rcx", 10, "add dl, 48", 10, "dec rsi", 10, "mov [rsi], dl", 10, "test rax, rax", 10, "jnz .digits", 10, ".out: test r12d, r12d", 10, "jz .nodash", 10, "dec rsi", 10, "mov byte [rsi], 45", 10, ".nodash: lea rdx, [sc_numbuf+31]", 10, "sub rdx, rsi", 10, "call sc_write", 10, "add rsp, 0x28", 10, "pop r12", 10, "pop rbx", 10, "ret", 10, 0
    cg_t_pstr     db "sc_print_str:", 10, "push rsi", 10, "call sc_strlen", 10, "mov rdx, rax", 10, "pop rsi", 10, "jmp sc_write", 10, 0
    cg_t_psp      db "sc_print_sp:", 10, "lea rsi, [sc_space]", 10, "mov rdx, 1", 10, "jmp sc_write", 10, 0
    cg_t_pnl      db "sc_print_nl:", 10, "lea rsi, [sc_crlf]", 10, "mov rdx, 2", 10, "jmp sc_write", 10, 0
    cg_t_divz     db "sc_div_zero:", 10, "sub rsp, 0x28", 10, "lea rsi, [sc_divmsg]", 10, "call sc_print_str", 10, "mov ecx, 1", 10, "call ExitProcess", 10, 0
    cg_s_mov_rax  db "mov rax, ", 0
    cg_s_mov_rcx  db "mov rcx, ", 0
    cg_s_mov_r10  db "mov r10, ", 0
    cg_s_push     db "push rax", 10, 0
    cg_s_pop_rcx  db "pop rcx", 10, 0
    cg_s_pop_rbx  db "pop rbx", 10, 0
    cg_s_add      db "add rax, rcx", 10, 0
    cg_s_sub      db "sub rax, rcx", 10, 0
    cg_s_imul     db "imul rax, rcx", 10, 0
    cg_s_cqo      db "cqo", 10, 0
    cg_s_idiv     db "idiv rcx", 10, 0
    cg_s_neg      db "neg rax", 10, 0
    cg_s_test     db "test rax, rax", 10, 0
    cg_s_testrcx  db "test rcx, rcx", 10, 0
    cg_s_jzdiv    db "jnz ", 0
    cg_s_calldiv  db "call sc_div_zero", 10, 0
    cg_s_cmp      db "cmp rax, rcx", 10, 0
    cg_s_sete     db "sete al", 10, "movzx eax, al", 10, 0
    cg_s_setne    db "setne al", 10, "movzx eax, al", 10, 0
    cg_s_setg     db "setg al", 10, "movzx eax, al", 10, 0
    cg_s_setl     db "setl al", 10, "movzx eax, al", 10, 0
    cg_s_setge    db "setge al", 10, "movzx eax, al", 10, 0
    cg_s_setle    db "setle al", 10, "movzx eax, al", 10, 0
    cg_s_setnz    db "setnz al", 10, "movzx eax, al", 10, 0
    cg_s_and      db "and al, cl", 10, "movzx eax, al", 10, 0
    cg_s_or       db "or al, cl", 10, "movzx eax, al", 10, 0
    cg_s_testrax  db "test rax, rax", 10, 0
    cg_s_jz       db "jz ", 0
    cg_s_jmp      db "jmp ", 0
    cg_s_label    db "L", 0
    cg_s_colon    db ":", 10, 0
    cg_s_sc_s     db "sc_s", 0
    cg_s_sc_v     db "sc_v", 0
    cg_s_db       db " db ", 0
    cg_s_resq2    db " resq 2", 10, 0
    cg_s_comma    db ",", 0
    cg_s_zero     db ", 0", 10, 0
    cg_s_nl       db 10, 0
    cg_s_varidx   db "[sc_v", 0
    cg_s_varidx8  db "+8]", 0
    cg_s_varidx0  db "]", 0
    cg_s_mov_var  db "mov [sc_v", 0
    cg_s_lea_str  db "lea rax, [sc_s", 0
    cg_s_rbrack   db "]", 10, 0
    cg_s_mov_rsi  db "mov rsi, [sc_v", 0
    cg_s_call     db "call ", 0
    cg_s_pint     db "sc_print_int", 10, 0
    cg_s_pstr     db "sc_print_str", 10, 0
    cg_s_psp      db "sc_print_sp", 10, 0
    cg_s_pnl      db "sc_print_nl", 10, 0
    cg_e_mov_qword db "mov qword [sc_v", 0
    cg_e_idx0     db "], 0", 10, 0
    cg_e_idx1     db "], 1", 10, 0
    cg_e_idx8rax  db "+8], rax", 10, 0
    cg_e_lea_rax  db "lea rax, [sc_s", 0
    cg_e_lea_rsi  db "lea rsi, [sc_s", 0
    cg_e_rbrack   db "]", 10, 0
    cg_e_idx8     db "+8]", 10, 0
    cg_e_mov_rcx  db "mov rcx, rax", 10, 0
    cg_e_pop_rax  db "pop rax", 10, 0
    cg_e_mov_rdx  db "mov rax, rdx", 10, 0
    cg_e_testa    db "test rax, rax", 10, 0
    cg_e_setnza   db "setnz al", 10, 0
    cg_e_testc    db "test rcx, rcx", 10, 0
    cg_e_setnzc   db "setnz cl", 10, 0
    cg_e_setea    db "sete al", 10, 0
    cg_e_testjz   db "test rcx, rcx", 10, 0
    cg_e_ok       db "call sc_div_zero", 10, 0
    cg_e_movzx    db "movzx eax, al", 10, 0
    cg_e_neg      db "neg rax", 10, 0
    cg_q          db '"', 0
    cg_f_win64    db " -f win64 ", 0
    cg_o_out      db " -o ", 0
    cg_link_base  db " /NOLOGO /SUBSYSTEM:CONSOLE /ENTRY:main", 0
    cg_link_out   db " /OUT:", 0
    cg_link_mid   db " kernel32.lib /LIBPATH:", 0
    cg_sp         db " ", 0
    cg_build_dir  db "build/", 0
    cg_ext_asm    db ".asm", 0
    cg_ext_obj    db ".obj", 0
    cg_ext_exe    db ".exe", 0

section .bss
    cg_out        resq 1
    cg_vars       resb 98304    ; 4096 * 24: name, type(0 int/1 str), slot
    cg_varcount   resq 1
    cg_label      resq 1
    cg_loop_top   resq 1
    cg_loop_end   resq 1
    cg_strcount   resq 1
    cg_strs       resb 8192     ; 1024 * 8: string ptrs
    cg_numbuf     resb 32
    cg_asm        resb 1024
    cg_obj        resb 1024
    cg_exe        resb 1024
    cg_cmd        resb 2048

section .text

; ---------- cg_write_bytes(RSI=ptr, RDX=len) -> to cg_out ----------
cg_write_bytes:
    push rbx
    sub rsp, 0x30
    mov rcx, [cg_out]
    mov r8, rdx
    mov rdx, rsi
    lea r9, [rsp+0x28]
    mov qword [rsp+0x20], 0
    call WriteFile
    add rsp, 0x30
    pop rbx
    ret

; ---------- cg_emit(RSI=cstr) ----------
cg_emit:
    push rsi
    call strlen
    mov rdx, rax
    pop rsi
    jmp cg_write_bytes

; ---------- cg_nl ----------
cg_nl:
    lea rsi, [cg_s_nl]
    jmp cg_emit

; ---------- cg_emit_u64(RAX) ----------
cg_emit_u64:
    push rbx
    lea rsi, [cg_numbuf+31]
    mov byte [rsi], 0
    mov rbx, rax
    mov rcx, 10
    test rbx, rbx
    jnz .digits
    dec rsi
    mov byte [rsi], '0'
    jmp .out
.digits:
    mov rax, rbx
    xor edx, edx
    div rcx
    mov rbx, rax
    add dl, '0'
    dec rsi
    mov [rsi], dl
    test rbx, rbx
    jnz .digits
.out:
    call cg_emit
    pop rbx
    ret

; ---------- cg_emit_labelnum(RSI=prefix, RAX=id): prints prefix+id ----------
cg_emit_labelnum:
    push rax
    call cg_emit
    pop rax
    jmp cg_emit_u64

; ---------- cg_error(RSI=msg, RDX=node or 0): fatal with line ----------
cg_error:
    push rsi
    push rdx
    lea rsi, [cg_err_line1]
    call print_cstr
    pop rdx
    pop rsi
    push rsi
    push rdx
    test rdx, rdx
    jz .noline
    mov rax, [rdx+40]
    call print_u64
    jmp .msg
.noline:
    mov rax, 0
    call print_u64
.msg:
    pop rdx
    pop rsi
    push rsi
    lea rsi, [cg_err_line2]
    call print_cstr
    pop rsi
    push rsi
    call print_cstr
    lea rsi, [nl_str]
    call print_cstr
    pop rsi
    mov ecx, 1
    sub rsp, 0x28
    call ExitProcess

; ---------- cg_find_var(RSI=name) -> RAX idx or -1 ----------
cg_find_var:
    push rbx
    push r12
    mov r12, rsi
    mov rcx, [cg_varcount]
    xor r8d, r8d
.lp:
    cmp r8, rcx
    jae .nf
    imul rbx, r8, CG_VAR_ENTRY_SIZE
    lea rbx, [cg_vars + rbx]
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

; ---------- cg_def_var(RSI=name, RDX=type) -> RAX slot ----------
cg_def_var:
    push rbx
    push r12
    push rsi              ; save name across find call (find clobbers rsi)
    mov r12, rdx
    call cg_find_var
    pop rsi               ; restore name
    cmp rax, -1
    jne .have
    mov rax, [cg_varcount]
    cmp rax, 4096
    jae .oom
    imul rbx, rax, CG_VAR_ENTRY_SIZE
    lea rbx, [cg_vars + rbx]
    mov [rbx], rsi
    mov [rbx+8], r12
    mov [rbx+16], rax
    inc qword [cg_varcount]
    pop r12
    pop rbx
    ret
.have:
    imul rbx, rax, CG_VAR_ENTRY_SIZE
    lea rbx, [cg_vars + rbx]
    mov [rbx+8], r12
    mov rax, [rbx+16]
    pop r12
    pop rbx
    ret
.oom:
    lea rsi, [rt_err_nomem]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x28
    call ExitProcess

; ---------- cg_str_id(RSI=string) -> RAX id (dedupe) ----------
cg_str_id:
    push rbx
    push r12
    mov r12, rsi
    mov rcx, [cg_strcount]
    xor r8d, r8d
.lp:
    cmp r8, rcx
    jae .new
    mov rbx, [cg_strs + r8*8]
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
.new:
    mov rax, [cg_strcount]
    cmp rax, CG_MAX_STRLITS
    jae .oom
    mov [cg_strs + rax*8], r12
    inc qword [cg_strcount]
    pop r12
    pop rbx
    ret
.found:
    mov rax, r8
    pop r12
    pop rbx
    ret
.oom:
    lea rsi, [rt_err_nomem]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x28
    call ExitProcess

; ---------- cg_new_label() -> RAX id ----------
cg_new_label:
    mov rax, [cg_label]
    inc qword [cg_label]
    ret

; ---------- cg_expr_type(RAX=node) -> RAX 0=int,1=str,-1=other ----------
cg_expr_type:
    push rbx
    push r12
    push r13
    mov r12, rax
    mov rax, [r12]
    cmp rax, AST_INT
    je .int
    cmp rax, AST_STRING
    je .str
    cmp rax, AST_VAR
    je .var
    cmp rax, AST_BINARY
    je .binary
    cmp rax, AST_UNARY
    je .unary
    mov rax, -1
    jmp .done
.int:
    mov rax, 0
    jmp .done
.str:
    mov rax, 1
    jmp .done
.var:
    mov rsi, [r12+16]
    call cg_find_var
    cmp rax, -1
    je .undef
    imul rbx, rax, CG_VAR_ENTRY_SIZE
    lea rbx, [cg_vars + rbx]
    mov rax, [rbx+8]
    jmp .done
.undef:
    mov rax, -1
    jmp .done
.binary:
    mov rax, [r12+16]
    call cg_expr_type
    mov r13, rax
    mov rax, [r12+24]
    call cg_expr_type
    cmp r13, 0
    jne .other
    cmp rax, 0
    jne .other
    mov rax, 0
    jmp .done
.other:
    mov rax, -1
    jmp .done
.unary:
    mov rax, [r12+16]
    call cg_expr_type
    cmp rax, 0
    jne .other2
    mov rax, 0
    jmp .done
.other2:
    mov rax, -1
.done:
    pop r13
    pop r12
    pop rbx
    ret

; ---------- cg_emit_str_bytes(RSI=ptr): emit "72,101,..." ----------
; Uses r12-r14 (preserved by cg_emit* callees), no stack juggling.
cg_emit_str_bytes:
    push rbx
    push r12
    push r13
    push r14
    mov r12, rsi
    call strlen
    mov r13, rax
    test r13, r13
    jz .empty
    xor r14d, r14d
.loop:
    cmp r14, r13
    jae .done
    test r14, r14
    jz .first
    lea rsi, [cg_s_comma]
    call cg_emit
.first:
    movzx eax, byte [r12+r14]
    call cg_emit_u64
    inc r14
    jmp .loop
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.empty:
    mov rax, 0
    call cg_emit_u64
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------- cg_expr_int(RAX=node): emit int expr, result in rax ----------
cg_expr_int:
    push rbx
    push r12
    push r13
    mov r12, rax
    mov rax, [r12]
    cmp rax, AST_INT
    je .int
    cmp rax, AST_VAR
    je .var
    cmp rax, AST_BINARY
    je .binary
    cmp rax, AST_UNARY
    je .unary
    lea rsi, [cg_err_unsup]
    mov rdx, r12
    call cg_error
.int:
    lea rsi, [cg_s_mov_rax]
    call cg_emit
    mov rax, [r12+16]
    call cg_emit_u64
    lea rsi, [cg_s_nl]
    call cg_emit
    pop r13
    pop r12
    pop rbx
    ret
.var:
    mov rsi, [r12+16]
    call cg_find_var
    cmp rax, -1
    je .undefv
    imul rbx, rax, CG_VAR_ENTRY_SIZE
    lea rbx, [cg_vars + rbx]
    cmp qword [rbx+8], 0
    jne .notint
    mov rax, [rbx+16]
    push rax
    lea rsi, [cg_s_mov_rax]
    call cg_emit
    lea rsi, [cg_s_varidx]
    call cg_emit
    pop rax
    call cg_emit_u64
    lea rsi, [cg_s_varidx8]
    call cg_emit
    lea rsi, [cg_s_nl]
    call cg_emit
    pop r13
    pop r12
    pop rbx
    ret
.undefv:
    lea rsi, [cg_err_undef]
    mov rdx, r12
    call cg_error
.notint:
    lea rsi, [cg_err_nonint]
    mov rdx, r12
    call cg_error
.binary:
    ; typecheck both sides int
    mov rax, [r12+16]
    call cg_expr_type
    cmp rax, 0
    jne .bin_nonint
    mov rax, [r12+24]
    call cg_expr_type
    cmp rax, 0
    jne .bin_nonint
    mov r13, [r12+8]      ; op
    ; emit left, push, right, pop to rcx
    mov rax, [r12+16]
    call cg_expr_int
    lea rsi, [cg_s_push]
    call cg_emit
    mov rax, [r12+24]
    call cg_expr_int
    lea rsi, [cg_e_mov_rcx]
    call cg_emit
    lea rsi, [cg_e_pop_rax]
    call cg_emit
    cmp r13, TOK_PLUS
    je .b_add
    cmp r13, TOK_MINUS
    je .b_sub
    cmp r13, TOK_STAR
    je .b_mul
    cmp r13, TOK_SLASH
    je .b_div
    cmp r13, TOK_PERCENT
    je .b_mod
    cmp r13, TOK_EQEQ
    je .b_eq
    cmp r13, TOK_NEQ
    je .b_neq
    cmp r13, TOK_GT
    je .b_gt
    cmp r13, TOK_LT
    je .b_lt
    cmp r13, TOK_GTE
    je .b_gte
    cmp r13, TOK_LTE
    je .b_lte
    cmp r13, TOK_ANDAND
    je .b_and
    cmp r13, TOK_OROR
    je .b_or
    lea rsi, [cg_err_unsup]
    mov rdx, r12
    call cg_error
.b_add:
    lea rsi, [cg_s_add]
    call cg_emit
    jmp .b_done
.b_sub:
    lea rsi, [cg_s_sub]
    call cg_emit
    jmp .b_done
.b_mul:
    lea rsi, [cg_s_imul]
    call cg_emit
    jmp .b_done
.b_div:
    call cg_emit_divcheck
    lea rsi, [cg_s_cqo]
    call cg_emit
    lea rsi, [cg_s_idiv]
    call cg_emit
    jmp .b_done
.b_mod:
    call cg_emit_divcheck
    lea rsi, [cg_s_cqo]
    call cg_emit
    lea rsi, [cg_s_idiv]
    call cg_emit
    lea rsi, [cg_e_mov_rdx]
    call cg_emit
    jmp .b_done
.b_eq:
    lea rsi, [cg_s_cmp]
    call cg_emit
    lea rsi, [cg_s_sete]
    call cg_emit
    jmp .b_done
.b_neq:
    lea rsi, [cg_s_cmp]
    call cg_emit
    lea rsi, [cg_s_setne]
    call cg_emit
    jmp .b_done
.b_gt:
    lea rsi, [cg_s_cmp]
    call cg_emit
    lea rsi, [cg_s_setg]
    call cg_emit
    jmp .b_done
.b_lt:
    lea rsi, [cg_s_cmp]
    call cg_emit
    lea rsi, [cg_s_setl]
    call cg_emit
    jmp .b_done
.b_gte:
    lea rsi, [cg_s_cmp]
    call cg_emit
    lea rsi, [cg_s_setge]
    call cg_emit
    jmp .b_done
.b_lte:
    lea rsi, [cg_s_cmp]
    call cg_emit
    lea rsi, [cg_s_setle]
    call cg_emit
    jmp .b_done
.b_and:
    lea rsi, [cg_e_testa]
    call cg_emit
    lea rsi, [cg_e_setnza]
    call cg_emit
    lea rsi, [cg_e_testc]
    call cg_emit
    lea rsi, [cg_e_setnzc]
    call cg_emit
    lea rsi, [cg_s_and]
    call cg_emit
    jmp .b_done
.b_or:
    lea rsi, [cg_e_testa]
    call cg_emit
    lea rsi, [cg_e_setnza]
    call cg_emit
    lea rsi, [cg_e_testc]
    call cg_emit
    lea rsi, [cg_e_setnzc]
    call cg_emit
    lea rsi, [cg_s_or]
    call cg_emit
    jmp .b_done
.b_done:
    pop r13
    pop r12
    pop rbx
    ret
.bin_nonint:
    lea rsi, [cg_err_nonint]
    mov rdx, r12
    call cg_error
.unary:
    mov rax, [r12+16]
    call cg_expr_type
    cmp rax, 0
    jne .un_nonint
    mov r13, [r12+8]
    mov rax, [r12+16]
    call cg_expr_int
    cmp r13, TOK_MINUS
    je .u_neg
    cmp r13, TOK_BANG
    je .u_not
    lea rsi, [cg_err_unsup]
    mov rdx, r12
    call cg_error
.u_neg:
    lea rsi, [cg_e_neg]
    call cg_emit
    pop r13
    pop r12
    pop rbx
    ret
.u_not:
    lea rsi, [cg_e_testa]
    call cg_emit
    lea rsi, [cg_e_setea]
    call cg_emit
    lea rsi, [cg_e_movzx]
    call cg_emit
    pop r13
    pop r12
    pop rbx
    ret
.un_nonint:
    lea rsi, [cg_err_nonint]
    mov rdx, r12
    call cg_error

; ---------- cg_emit_divcheck: test rcx,rcx; jnz Lok; call sc_div_zero; Lok: ----------
cg_emit_divcheck:
    push rbx
    call cg_new_label
    mov rbx, rax
    lea rsi, [cg_e_testjz]
    call cg_emit
    lea rsi, [cg_s_jzdiv]
    call cg_emit
    lea rsi, [cg_s_label]
    call cg_emit
    mov rax, rbx
    call cg_emit_u64
    lea rsi, [cg_s_nl]
    call cg_emit
    lea rsi, [cg_e_ok]
    call cg_emit
    lea rsi, [cg_s_label]
    call cg_emit
    mov rax, rbx
    call cg_emit_u64
    lea rsi, [cg_s_colon]
    call cg_emit
    pop rbx
    ret

; ---------- cg_stmt(RAX=node) ----------
cg_stmt:
    push rbx
    push r12
    push r13
    mov r12, rax
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
    cmp rax, AST_BREAK
    je .break
    cmp rax, AST_CONTINUE
    je .continue
    lea rsi, [cg_err_unsup]
    mov rdx, r12
    call cg_error
.program:
    mov r13, [r12+16]
    mov rbx, [r12+8]
    xor r12d, r12d
.ploop:
    cmp r12, rbx
    jae .sdone
    mov rax, [r13+r12*8]
    push rbx
    push r13
    push r12
    sub rsp, 8
    call cg_stmt
    add rsp, 8
    pop r12
    pop r13
    pop rbx
    inc r12
    jmp .ploop
.sdone:
    pop r13
    pop r12
    pop rbx
    ret
.block:
    mov r13, [r12+16]
    mov rbx, [r12+8]
    xor r12d, r12d
.bloop:
    cmp r12, rbx
    jae .sdone
    mov rax, [r13+r12*8]
    push rbx
    push r13
    push r12
    sub rsp, 8
    call cg_stmt
    add rsp, 8
    pop r12
    pop r13
    pop rbx
    inc r12
    jmp .bloop
.assign:
    ; left=[r12+16]=varnode, mid=[r12+24]=expr
    mov rbx, [r12+16]
    mov rsi, [rbx+16]     ; name
    push rsi              ; save name
    mov rax, [r12+24]
    call cg_expr_type
    cmp rax, 0
    je .as_int
    cmp rax, 1
    je .as_str
    add rsp, 8
    lea rsi, [cg_err_unsup]
    mov rdx, [r12+24]
    call cg_error
.as_int:
    mov rax, [r12+24]
    call cg_expr_int
    pop rsi               ; name
    mov rdx, 0
    call cg_def_var       ; rax = slot
    mov rbx, rax          ; slot in rbx (safe across emits)
    lea rsi, [cg_s_mov_var]
    call cg_emit
    mov rax, rbx
    call cg_emit_u64
    lea rsi, [cg_e_idx8rax]
    call cg_emit
    lea rsi, [cg_e_mov_qword]
    call cg_emit
    mov rax, rbx
    call cg_emit_u64
    lea rsi, [cg_e_idx0]
    call cg_emit
    pop r13
    pop r12
    pop rbx
    ret
.as_str:
    mov rax, [r12+24]
    mov rbx, [rax]        ; expr kind
    cmp rbx, AST_STRING
    je .as_strlit
    cmp rbx, AST_VAR
    je .as_strvar
    add rsp, 8
    lea rsi, [cg_err_unsup]
    mov rdx, [r12+24]
    call cg_error
.as_strlit:
    mov rsi, [rax+16]     ; literal ptr
    call cg_str_id        ; rax = id
    mov rbx, rax          ; id in rbx
    lea rsi, [cg_e_lea_rax]
    call cg_emit
    mov rax, rbx
    call cg_emit_u64
    lea rsi, [cg_e_rbrack]
    call cg_emit
    pop rsi               ; name
    mov rdx, 1
    call cg_def_var       ; rax = slot
    mov rbx, rax          ; slot in rbx
    lea rsi, [cg_s_mov_var]
    call cg_emit
    mov rax, rbx
    call cg_emit_u64
    lea rsi, [cg_e_idx8rax]
    call cg_emit
    lea rsi, [cg_e_mov_qword]
    call cg_emit
    mov rax, rbx
    call cg_emit_u64
    lea rsi, [cg_e_idx1]
    call cg_emit
    pop r13
    pop r12
    pop rbx
    ret
.as_strvar:
    mov rbx, [rax+16]     ; src name
    mov rsi, rbx
    call cg_find_var
    cmp rax, -1
    je .as_undef
    push rax              ; src slot
    lea rsi, [cg_s_mov_rax]
    call cg_emit
    lea rsi, [cg_s_varidx]
    call cg_emit
    pop rax
    push rax
    call cg_emit_u64
    pop rax
    lea rsi, [cg_e_idx8]
    call cg_emit
    lea rsi, [cg_s_nl]
    call cg_emit
    pop rsi               ; name (dst)
    mov rdx, 1
    call cg_def_var       ; rax = dst slot
    mov rbx, rax          ; slot in rbx
    lea rsi, [cg_s_mov_var]
    call cg_emit
    mov rax, rbx
    call cg_emit_u64
    lea rsi, [cg_e_idx8rax]
    call cg_emit
    lea rsi, [cg_e_mov_qword]
    call cg_emit
    mov rax, rbx
    call cg_emit_u64
    lea rsi, [cg_e_idx1]
    call cg_emit
    pop r13
    pop r12
    pop rbx
    ret
    pop r13
    pop r12
    pop rbx
    ret
.as_undef:
    add rsp, 8
    lea rsi, [cg_err_undef]
    mov rdx, [r12+24]
    call cg_error

.exprstmt:
    ; expr = [r12+16]. Calls -> print/println builtin or error. Others eval+discard.
    mov rax, [r12+16]
    cmp qword [rax], AST_CALL
    je .es_call
    mov rax, [r12+16]
    call cg_expr_type
    cmp rax, 0
    je .es_int
    cmp rax, 1
    je .es_done            ; bare string: no side effect, emit nothing
    lea rsi, [cg_err_unsup]
    mov rdx, [r12+16]
    call cg_error
.es_int:
    mov rax, [r12+16]
    call cg_expr_int       ; result discarded
    pop r13
    pop r12
    pop rbx
    ret
.es_done:
    pop r13
    pop r12
    pop rbx
    ret
.es_call:
    mov rbx, [r12+16]     ; call node
    mov rax, [rbx+16]     ; callee
    cmp qword [rax], AST_VAR
    jne .es_bad
    mov rsi, [rax+16]     ; name
    push rsi
    mov rdi, s_print
    call streq
    pop rsi
    test eax, eax
    jnz .es_print
    mov rdi, s_println
    push rsi
    call streq
    pop rsi
    test eax, eax
    jnz .es_println
.es_bad:
    lea rsi, [cg_err_unsup]
    mov rdx, [r12+16]
    call cg_error
.es_print:
    mov rax, rbx          ; call node
    xor r8d, r8d          ; no trailing newline
    call cg_emit_printargs
    pop r13
    pop r12
    pop rbx
    ret
.es_println:
    mov rax, rbx
    mov r8d, 1            ; trailing newline
    call cg_emit_printargs
    pop r13
    pop r12
    pop rbx
    ret

.if:
    ; cond=[r12+16] must be int; then=[r12+24]; else=[r12+32] or 0
    mov rax, [r12+16]
    call cg_expr_type
    cmp rax, 0
    jne .if_bad
    mov rax, [r12+16]
    call cg_expr_int
    call cg_new_label
    push rax              ; [rsp+8] = else-id
    call cg_new_label
    push rax              ; [rsp] = end-id
    lea rsi, [cg_e_testa]
    call cg_emit
    lea rsi, [cg_s_jz]
    call cg_emit
    lea rsi, [cg_s_label]
    call cg_emit
    mov rax, [rsp+8]      ; else-id
    call cg_emit_u64
    lea rsi, [cg_s_nl]
    call cg_emit
    mov rax, [r12+24]     ; then
    call cg_stmt
    lea rsi, [cg_s_jmp]
    call cg_emit
    lea rsi, [cg_s_label]
    call cg_emit
    mov rax, [rsp]        ; end-id
    call cg_emit_u64
    lea rsi, [cg_s_nl]
    call cg_emit
    lea rsi, [cg_s_label]
    call cg_emit
    mov rax, [rsp+8]      ; else-id
    call cg_emit_u64
    lea rsi, [cg_s_colon]
    call cg_emit
    mov rax, [r12+32]     ; else or 0
    test rax, rax
    jz .if_noelse
    call cg_stmt
.if_noelse:
    lea rsi, [cg_s_label]
    call cg_emit
    pop rax               ; end-id
    call cg_emit_u64
    lea rsi, [cg_s_colon]
    call cg_emit
    pop rax               ; else-id (discard)
    pop r13
    pop r12
    pop rbx
    ret

.break:
    cmp qword [cg_loop_end], 0
    je .cg_break_err
    lea rsi, [cg_s_jmp]
    call cg_emit
    lea rsi, [cg_s_label]
    call cg_emit
    mov rax, [cg_loop_end]
    call cg_emit_u64
    lea rsi, [cg_s_nl]
    call cg_emit
    pop r13
    pop r12
    pop rbx
    ret
.cg_break_err:
    lea rsi, [cg_err_unsup]
    mov rdx, r12
    call cg_error

.continue:
    cmp qword [cg_loop_top], 0
    je .cg_cont_err
    lea rsi, [cg_s_jmp]
    call cg_emit
    lea rsi, [cg_s_label]
    call cg_emit
    mov rax, [cg_loop_top]
    call cg_emit_u64
    lea rsi, [cg_s_nl]
    call cg_emit
    pop r13
    pop r12
    pop rbx
    ret
.cg_cont_err:
    lea rsi, [cg_err_unsup]
    mov rdx, r12
    call cg_error

.if_bad:
    lea rsi, [cg_err_nonint]
    mov rdx, [r12+16]
    call cg_error

.while:
    mov rax, [r12+16]
    call cg_expr_type
    cmp rax, 0
    jne .wh_bad
    call cg_new_label
    push rax              ; [rsp+8] = top-id
    call cg_new_label
    push rax              ; [rsp] = end-id
    push qword [cg_loop_top]
    push qword [cg_loop_end]
    mov rax, [rsp+24]     ; top-id
    mov [cg_loop_top], rax
    mov rax, [rsp+16]     ; end-id
    mov [cg_loop_end], rax

    lea rsi, [cg_s_label]
    call cg_emit
    mov rax, [rsp+24]     ; top-id
    call cg_emit_u64
    lea rsi, [cg_s_colon]
    call cg_emit
    mov rax, [r12+16]
    call cg_expr_int
    lea rsi, [cg_e_testa]
    call cg_emit
    lea rsi, [cg_s_jz]
    call cg_emit
    lea rsi, [cg_s_label]
    call cg_emit
    mov rax, [rsp+16]     ; end-id
    call cg_emit_u64
    lea rsi, [cg_s_nl]
    call cg_emit
    mov rax, [r12+24]     ; body
    call cg_stmt
    lea rsi, [cg_s_jmp]
    call cg_emit
    lea rsi, [cg_s_label]
    call cg_emit
    mov rax, [rsp+24]     ; top-id
    call cg_emit_u64
    lea rsi, [cg_s_nl]
    call cg_emit
    lea rsi, [cg_s_label]
    call cg_emit
    mov rax, [rsp+16]     ; end-id
    call cg_emit_u64
    lea rsi, [cg_s_colon]
    call cg_emit

    pop qword [cg_loop_end]
    pop qword [cg_loop_top]
    pop rax               ; end-id
    pop rax               ; top-id
    pop r13
    pop r12
    pop rbx
    ret
.wh_bad:
    lea rsi, [cg_err_nonint]
    mov rdx, [r12+16]
    call cg_error

; ---------- cg_emit_printargs(RAX=callnode, R8=0/1 newline) ----------
cg_emit_printargs:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12, rax          ; call node
    mov r13, [r12+8]      ; count
    mov r14, [r12+24]     ; args base
    mov [rsp], r8         ; newline flag in frame scratch
    xor ebx, ebx          ; idx
.pa_loop:
    cmp rbx, r13
    jae .pa_done
    test rbx, rbx
    jz .pa_nosep
    lea rsi, [cg_s_call]
    call cg_emit
    lea rsi, [cg_s_psp]
    call cg_emit
.pa_nosep:
    mov rax, [r14+rbx*8]  ; arg node
    call cg_expr_type
    cmp rax, 0
    je .pa_int
    cmp rax, 1
    je .pa_str
    lea rsi, [cg_err_unsup]
    mov rax, [r14+rbx*8]
    mov rdx, rax
    call cg_error
.pa_int:
    mov rax, [r14+rbx*8]
    call cg_expr_int
    lea rsi, [cg_s_call]
    call cg_emit
    lea rsi, [cg_s_pint]
    call cg_emit
    inc rbx
    jmp .pa_loop
.pa_str:
    mov rax, [r14+rbx*8]
    mov rdx, [rax]        ; kind
    cmp rdx, AST_STRING
    je .pa_strlit
    cmp rdx, AST_VAR
    je .pa_strvar
    lea rsi, [cg_err_unsup]
    mov rdx, rax
    call cg_error
.pa_strlit:
    mov rsi, [rax+16]
    call cg_str_id        ; rax = id
    push rax
    lea rsi, [cg_e_lea_rsi]
    call cg_emit
    pop rax
    push rax
    call cg_emit_u64
    pop rax
    lea rsi, [cg_e_rbrack]
    call cg_emit
    lea rsi, [cg_s_call]
    call cg_emit
    lea rsi, [cg_s_pstr]
    call cg_emit
    inc rbx
    jmp .pa_loop
.pa_strvar:
    mov rsi, [rax+16]     ; name
    call cg_find_var
    cmp rax, -1
    je .pa_undef
    push rax              ; slot
    lea rsi, [cg_s_mov_rsi]
    call cg_emit
    pop rax
    call cg_emit_u64
    lea rsi, [cg_e_idx8]
    call cg_emit
    lea rsi, [cg_s_call]
    call cg_emit
    lea rsi, [cg_s_pstr]
    call cg_emit
    inc rbx
    jmp .pa_loop
.pa_undef:
    lea rsi, [cg_err_undef]
    mov rax, [r14+rbx*8]
    mov rdx, rax
    call cg_error
.pa_done:
    mov rax, [rsp]        ; newline flag
    test rax, rax
    jz .pa_ret
    lea rsi, [cg_s_call]
    call cg_emit
    lea rsi, [cg_s_pnl]
    call cg_emit
.pa_ret:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------- cg_emit_prologue ----------
cg_emit_prologue:
    lea rsi, [cg_h_default]
    call cg_emit
    lea rsi, [cg_h_data]
    call cg_emit
    lea rsi, [cg_d_init]
    call cg_emit
    lea rsi, [cg_h_bss]
    call cg_emit
    lea rsi, [cg_b_res]
    call cg_emit
    lea rsi, [cg_h_text]
    call cg_emit
    lea rsi, [cg_h_ext]
    call cg_emit
    lea rsi, [cg_h_main]
    call cg_emit
    ret

; ---------- cg_emit_epilogue_runtime ----------
cg_emit_epilogue_runtime:
    lea rsi, [cg_h_epil]
    call cg_emit
    lea rsi, [cg_t_write]
    call cg_emit
    lea rsi, [cg_t_strlen]
    call cg_emit
    lea rsi, [cg_t_pint]
    call cg_emit
    lea rsi, [cg_t_pstr]
    call cg_emit
    lea rsi, [cg_t_psp]
    call cg_emit
    lea rsi, [cg_t_pnl]
    call cg_emit
    lea rsi, [cg_t_divz]
    call cg_emit
    ret

; ---------- cg_emit_strings_vars ----------
cg_emit_strings_vars:
    push rbx
    push r12
    lea rsi, [cg_h_data]
    call cg_emit
    mov rbx, [cg_strcount]
    xor r12d, r12d
.str_loop:
    cmp r12, rbx
    jae .str_done
    push rbx
    push r12
    lea rsi, [cg_s_sc_s]
    call cg_emit
    pop r12
    pop rbx
    push rbx
    push r12
    mov rax, r12
    call cg_emit_u64
    pop r12
    pop rbx
    push rbx
    push r12
    lea rsi, [cg_s_db]
    call cg_emit
    pop r12
    pop rbx
    push rbx
    push r12
    mov rsi, [cg_strs + r12*8]
    call cg_emit_str_bytes
    pop r12
    pop rbx
    push rbx
    push r12
    lea rsi, [cg_s_zero]
    call cg_emit
    pop r12
    pop rbx
    inc r12
    jmp .str_loop
.str_done:
    lea rsi, [cg_h_bss]
    call cg_emit
    mov rbx, [cg_varcount]
    xor r12d, r12d
.var_loop:
    cmp r12, rbx
    jae .var_done
    push rbx
    push r12
    lea rsi, [cg_s_sc_v]
    call cg_emit
    pop r12
    pop rbx
    push rbx
    push r12
    mov rax, r12
    call cg_emit_u64
    pop r12
    pop rbx
    push rbx
    push r12
    lea rsi, [cg_s_resq2]
    call cg_emit
    pop r12
    pop rbx
    inc r12
    jmp .var_loop
.var_done:
    pop r12
    pop rbx
    ret

; ---------- cg_build_paths(RSI=srcpath): fills cg_asm/cg_obj/cg_exe ----------
cg_build_paths:
    push rbx
    push r12
    push r13
    push r14
    push r15
    cld
    mov r12, rsi              ; src
    call strlen
    mov r13, rax              ; srclen
    lea r14, [r12+rax]        ; end
    mov rbx, r12              ; stem start = after last sep
    mov r15, r12              ; cursor
.scan_base:
    cmp r15, r14
    jae .base_done
    mov al, [r15]
    cmp al, '/'
    je .is_sep
    cmp al, '\'
    je .is_sep
    inc r15
    jmp .scan_base
.is_sep:
    lea rbx, [r15+1]
    inc r15
    jmp .scan_base
.base_done:
    ; dot search from stem start
    mov r15, rbx
    mov rax, -1
.scan_dot:
    cmp r15, r14
    jae .dot_done
    cmp byte [r15], '.'
    jne .not_dot
    mov rax, r15
.not_dot:
    inc r15
    jmp .scan_dot
.dot_done:
    cmp rax, -1
    jne .has_ext
    mov rax, r14
.has_ext:
    sub rax, rbx              ; rax = stem len
    mov r15, rax
    ; cg_asm = "build/" + stem + ".asm"
    lea rdi, [cg_asm]
    lea rsi, [cg_build_dir]
    call cg_copy_cstr         ; rdi advanced
    mov rsi, rbx
    mov rcx, r15
    rep movsb
    lea rsi, [cg_ext_asm]
    call cg_copy_cstr
    mov byte [rdi], 0
    ; cg_obj = "build/" + stem + ".obj"
    lea rdi, [cg_obj]
    lea rsi, [cg_build_dir]
    call cg_copy_cstr
    mov rsi, rbx
    mov rcx, r15
    rep movsb
    lea rsi, [cg_ext_obj]
    call cg_copy_cstr
    mov byte [rdi], 0
    ; cg_exe = srcdir + stem + ".exe"  (srcdir = srcpath up to stem)
    lea rdi, [cg_exe]
    mov rsi, r12
    mov rcx, rbx
    sub rcx, r12              ; srcdir len
    rep movsb
    mov rsi, rbx
    mov rcx, r15
    rep movsb
    lea rsi, [cg_ext_exe]
    call cg_copy_cstr
    mov byte [rdi], 0
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------- cg_copy_cstr(RSI=src, RDI=dst): copies w/o NUL, RDI advanced, cld assumed ----------
cg_copy_cstr:
.cp:
    mov al, [rsi]
    test al, al
    jz .done
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .cp
.done:
    ret

; ---------- cg_cmd_reset / cg_cmd_add(RSI) / cg_cmd_add_q(RSI) ----------
cg_cmd_reset:
    mov byte [cg_cmd], 0
    ret

cg_cmd_add:
    push rdi
    lea rdi, [cg_cmd]
.find_end:
    cmp byte [rdi], 0
    je .at_end
    inc rdi
    jmp .find_end
.at_end:
    call cg_copy_cstr
    mov byte [rdi], 0
    pop rdi
    ret

cg_cmd_add_q:
    push rdi
    lea rdi, [cg_cmd]
.find_end2:
    cmp byte [rdi], 0
    je .at_end2
    inc rdi
    jmp .find_end2
.at_end2:
    mov byte [rdi], '"'
    inc rdi
    call cg_copy_cstr
    mov byte [rdi], '"'
    inc rdi
    mov byte [rdi], 0
    pop rdi
    ret

; ---------- cg_spawn(RSI=cmdline writable) -> EAX exit code (0 ok) ----------
cg_spawn:
    push rbx
    push r12
    push r13
    sub rsp, 0xE0
    mov r13, rsi
    lea rdi, [rsp+0x50]
    mov ecx, 26
    xor eax, eax
.zsi:
    mov [rdi], eax
    add rdi, 4
    dec ecx
    jnz .zsi
    mov dword [rsp+0x50], 104
    lea r12, [rsp+0xB8]
    mov qword [r12], 0
    mov qword [r12+8], 0
    mov qword [r12+16], 0
    xor ecx, ecx
    mov rdx, r13
    xor r8d, r8d
    xor r9d, r9d
    mov qword [rsp+0x20], 0
    mov qword [rsp+0x28], 0
    mov qword [rsp+0x30], 0
    mov qword [rsp+0x38], 0
    lea rax, [rsp+0x50]
    mov [rsp+0x40], rax
    lea rax, [rsp+0xB8]
    mov [rsp+0x48], rax
    call CreateProcessA
    test eax, eax
    jz .spawn_fail
    mov rcx, [r12]
    mov rdx, INFINITE
    sub rsp, 0x20
    call WaitForSingleObject
    add rsp, 0x20
    mov rcx, [r12]
    lea rdx, [rsp+0xD0]
    sub rsp, 0x20
    call GetExitCodeProcess
    add rsp, 0x20
    mov eax, [rsp+0xD0]
    mov [rsp+0xD8], eax
    mov rcx, [r12]
    sub rsp, 0x20
    call CloseHandle
    add rsp, 0x20
    mov rcx, [r12+8]
    sub rsp, 0x20
    call CloseHandle
    add rsp, 0x20
    mov eax, [rsp+0xD8]
    add rsp, 0xE0
    pop r13
    pop r12
    pop rbx
    ret
.spawn_fail:
    mov eax, 0xFFFFFFFF
    add rsp, 0xE0
    pop r13
    pop r12
    pop rbx
    ret

; ---------- cg_build_nasm_cmd / cg_build_link_cmd ----------
cg_build_nasm_cmd:
    call cg_cmd_reset
    lea rsi, [cfg_nasm_exe]
    call cg_cmd_add_q
    lea rsi, [cg_f_win64]
    call cg_cmd_add
    lea rsi, [cg_asm]
    call cg_cmd_add_q
    lea rsi, [cg_o_out]
    call cg_cmd_add
    lea rsi, [cg_obj]
    call cg_cmd_add_q
    ret

cg_build_link_cmd:
    call cg_cmd_reset
    lea rsi, [cfg_link_exe]
    call cg_cmd_add_q
    lea rsi, [cg_link_base]
    call cg_cmd_add
    lea rsi, [cg_link_out]
    call cg_cmd_add
    lea rsi, [cg_exe]
    call cg_cmd_add_q
    lea rsi, [cg_sp]
    call cg_cmd_add
    lea rsi, [cg_obj]
    call cg_cmd_add_q
    lea rsi, [cg_link_mid]
    call cg_cmd_add
    lea rsi, [cfg_sdk_lib]
    call cg_cmd_add_q
    ret

; ---------- compiler_run(RSI=srcpath) ----------
compiler_run:
    push rbx
    push r12
    push r13
    mov r12, rsi
    call cg_build_paths
    sub rsp, 0x40
    lea rcx, [cg_asm]
    mov rdx, GENERIC_WRITE
    xor r8d, r8d
    mov r9, 0
    mov qword [rsp+0x20], CREATE_ALWAYS
    mov qword [rsp+0x28], 0
    mov qword [rsp+0x30], 0
    call CreateFileA
    add rsp, 0x40
    cmp rax, INVALID_HANDLE_VALUE
    je .open_err
    mov [cg_out], rax
    mov qword [cg_varcount], 0
    mov qword [cg_label], 0
    mov qword [cg_strcount], 0
    call cg_emit_prologue
    mov rax, [parser_root]
    call cg_stmt
    call cg_emit_epilogue_runtime
    call cg_emit_strings_vars
    mov rcx, [cg_out]
    call CloseHandle
    call cg_build_nasm_cmd
    lea rsi, [cg_cmd]
    call cg_spawn
    test eax, eax
    jnz .nasm_fail
    call cg_build_link_cmd
    lea rsi, [cg_cmd]
    call cg_spawn
    test eax, eax
    jnz .link_fail
    lea rsi, [cg_built_pre]
    call print_cstr
    lea rsi, [cg_exe]
    call print_cstr
    lea rsi, [nl_str]
    call print_cstr
    pop r13
    pop r12
    pop rbx
    ret
.open_err:
    lea rsi, [cg_err_open]
    call print_cstr
    lea rsi, [cg_asm]
    call print_cstr
    lea rsi, [err_open_suf]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x20
    call ExitProcess
.nasm_fail:
    lea rsi, [cg_err_nasm]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x20
    call ExitProcess
.link_fail:
    lea rsi, [cg_err_link]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x20
    call ExitProcess
