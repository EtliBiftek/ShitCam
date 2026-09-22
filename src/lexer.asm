; ShitCam lexer - x86-64 NASM, Windows x64 ABI.
; Tokenizes UTF-8/ASCII source into 24-byte records: [kind][payload][line].
; String/ident payloads are NUL-terminated copies in a 4 MB bump pool.
; Errors are fatal in v1 (print + ExitProcess(1)); REPL phase makes them resumable.
; Register contract: R12 = current offset, R13 = src base, R14 = src len.
; R12-R15 callee-saved: saved/restored by lexer_run.

%define LEX_TOK_SIZE 24
%define LEX_POOL_SIZE 4194304

section .data
    lex_err_unexp  db "unexpected character '", 0
    lex_err_unexp2 db "'", 0
    lex_err_unterm db "unterminated string literal", 0
    lex_err_badesc db "unknown escape sequence", 0
    lex_err_tokens db "too many tokens (limit 65536)", 0
    lex_err_pool   db "out of string memory", 0
    lex_err_mem    db "Error: out of memory", 13, 10, 0
    lex_err_pre    db "Error: ", 0
    lex_file_pre   db "File: ", 0
    lex_line_pre   db "Line: ", 0
    lex_col_pre    db "Column: ", 0
    ; keyword spellings
    kw_true   db "true", 0
    kw_false  db "false", 0
    kw_null   db "null", 0
    kw_fn     db "fn", 0
    kw_if     db "if", 0
    kw_else   db "else", 0
    kw_while  db "while", 0
    kw_return db "return", 0
    kw_import db "import", 0
    kw_break  db "break", 0
    kw_continue db "continue", 0
    kw_for    db "for", 0
    kw_in     db "in", 0
    ; token kind names for --lextest dump
    tn_eof     db "EOF", 0
    tn_int     db "INT", 0
    tn_float   db "FLOAT", 0
    tn_string  db "STRING", 0
    tn_ident   db "IDENT", 0
    tn_true    db "TRUE", 0
    tn_false   db "FALSE", 0
    tn_null    db "NULL", 0
    tn_fn      db "FN", 0
    tn_if      db "IF", 0
    tn_else    db "ELSE", 0
    tn_while   db "WHILE", 0
    tn_return  db "RETURN", 0
    tn_import  db "IMPORT", 0
    tn_break   db "BREAK", 0
    tn_continue db "CONTINUE", 0
    tn_for     db "FOR", 0
    tn_in      db "IN", 0
    tn_pluseq  db "+=", 0
    tn_minuseq db "-=", 0
    tn_stareq  db "*=", 0
    tn_slasheq db "/=", 0
    tn_plus    db "+", 0
    tn_minus   db "-", 0
    tn_star    db "*", 0
    tn_slash   db "/", 0
    tn_pct     db "%", 0
    tn_eqeq    db "==", 0
    tn_neq     db "!=", 0
    tn_gt      db ">", 0
    tn_lt      db "<", 0
    tn_gte     db ">=", 0
    tn_lte     db "<=", 0
    tn_and     db "&&", 0
    tn_or      db "||", 0
    tn_bang    db "!", 0
    tn_assign  db "=", 0
    tn_lp      db "(", 0
    tn_rp      db ")", 0
    tn_lb      db "{", 0
    tn_rb      db "}", 0
    tn_lbr     db "[", 0
    tn_rbr     db "]", 0
    tn_comma   db ",", 0
    tn_colon   db ":", 0
    tn_dot     db ".", 0
    tn_semi    db ";", 0
    tn_q       db '"', 0
    tn_sp      db " ", 0
    tn_lparen2 db " (line ", 0
    tn_rparen  db ")", 13, 10, 0
    hex_digits db "0123456789ABCDEF", 0

section .bss
    lex_src        resq 1
    lex_len        resq 1
    lex_path       resq 1
    lex_line       resq 1
    lex_line_start resq 1
    lex_tokcount   resq 1
    lex_pool       resq 1
    lex_pool_used  resq 1
    lex_tokens     resb 1572864    ; SC_MAX_TOKENS(65536) * 24
    lex_errbuf     resb 64
    lex_hexbuf     resb 19         ; "0x" + 16 hex + NUL

section .text

; ---------- lexer_init(RSI=path, RDX=src, RCX=len) ----------
lexer_init:
    push rbx
    mov [lex_path], rsi
    mov [lex_src], rdx
    mov [lex_len], rcx
    mov qword [lex_tokcount], 0
    mov qword [lex_line], 1
    mov qword [lex_line_start], 0
    mov qword [lex_pool_used], 0
    sub rsp, 0x20
    xor ecx, ecx
    mov rdx, LEX_POOL_SIZE
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_READWRITE
    call VirtualAlloc
    add rsp, 0x20
    test rax, rax
    jz .oom
    mov [lex_pool], rax
    pop rbx
    ret
.oom:
    lea rsi, [lex_err_mem]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x20
    call ExitProcess

; ---------- lex_error(RSI=msg): fatal with location, never returns ----------
; R12 must hold current offset.
lex_error:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rsi                      ; msg
    mov r15, [lex_src]
    add r15, r12                      ; offending char ptr (for column only)
    lea rsi, [lex_err_pre]
    call print_cstr
    mov rsi, rbx
    call print_cstr
    lea rsi, [nl_str]
    call print_cstr
    lea rsi, [lex_file_pre]
    call print_cstr
    mov rsi, [lex_path]
    call print_cstr
    lea rsi, [nl_str]
    call print_cstr
    lea rsi, [lex_line_pre]
    call print_cstr
    mov rax, [lex_line]
    call print_u64
    lea rsi, [nl_str]
    call print_cstr
    lea rsi, [lex_col_pre]
    call print_cstr
    mov rax, r12
    sub rax, [lex_line_start]
    inc rax
    call print_u64
    lea rsi, [nl_str]
    call print_cstr
    ; source line text
    mov rsi, [lex_src]
    add rsi, [lex_line_start]
    mov rdx, rsi
.find_eol:
    cmp rdx, [lex_src]
    jb .print_line
    mov rcx, rdx
    sub rcx, [lex_src]
    cmp rcx, [lex_len]
    jae .print_line
    mov al, [rdx]
    cmp al, 10
    je .print_line
    cmp al, 0
    je .print_line
    inc rdx
    jmp .find_eol
.print_line:
    mov rcx, rdx
    sub rcx, rsi
    cmp rcx, 200
    jbe .ok_len
    mov rcx, 200
.ok_len:
    mov rdx, rcx
    call print_bytes
    lea rsi, [nl_str]
    call print_cstr
    ; caret: (col-1) spaces + ^
    mov rcx, r12
    sub rcx, [lex_line_start]
    test rcx, rcx
    jz .caret
.spaces:
    push rcx
    lea rsi, [tn_sp]
    call print_cstr
    pop rcx
    dec rcx
    jnz .spaces
.caret:
    lea rsi, [tn_gt]
    call print_cstr
    lea rsi, [nl_str]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x20
    call ExitProcess

; ---------- lex_emit(RAX=kind, RDX=payload) ----------
lex_emit:
    push rbx
    mov rbx, [lex_tokcount]
    cmp rbx, SC_MAX_TOKENS
    jae .overflow
    imul rcx, rbx, LEX_TOK_SIZE
    lea rcx, [lex_tokens + rcx]
    mov [rcx], rax
    mov [rcx + 8], rdx
    mov rbx, [lex_line]
    mov [rcx + 16], rbx
    mov rax, [lex_tokcount]
    inc rax
    mov [lex_tokcount], rax
    pop rbx
    ret
.overflow:
    lea rsi, [lex_err_tokens]
    call print_cstr
    lea rsi, [nl_str]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x20
    call ExitProcess

; ---------- lex_pool_alloc(RCX=size) -> RAX ptr (8-aligned) ----------
lex_pool_alloc:
    mov rax, [lex_pool_used]
    add rax, 7
    and rax, -8
    mov rdx, rax
    add rdx, rcx
    cmp rdx, LEX_POOL_SIZE
    ja .oom
    mov [lex_pool_used], rdx
    add rax, [lex_pool]
    ret
.oom:
    lea rsi, [lex_err_pool]
    call lex_error

; ---------- lexer_run() -> RAX token count ----------
lexer_run:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r13, [lex_src]
    mov r14, [lex_len]
    xor r12d, r12d                    ; offset
    mov qword [lex_line], 1
    mov qword [lex_line_start], 0
.next:
    cmp r12, r14
    jae .done
    movzx eax, byte [r13 + r12]
    ; whitespace
    cmp al, ' '
    je .adv
    cmp al, 9
    je .adv
    cmp al, 13
    je .adv
    cmp al, 10
    je .newline
    cmp al, ';'
    je .semi
    ; comments: // and #
    cmp al, '#'
    je .comment
    cmp al, '/'
    je .maybe_comment
    ; number
    cmp al, '0'
    jb .not_num
    cmp al, '9'
    jbe .number
.not_num:
    ; string
    cmp al, '"'
    je .string
    ; ident / keyword
    cmp al, '_'
    je .ident
    cmp al, 'A'
    jb .symbol
    cmp al, 'Z'
    jbe .ident
    cmp al, 'a'
    jb .symbol
    cmp al, 'z'
    jbe .ident
    jmp .symbol
.adv:
    inc r12
    jmp .next
.newline:
    inc r12
    mov rax, [lex_line]
    inc rax
    mov [lex_line], rax
    mov [lex_line_start], r12
    jmp .next
.semi:
    mov rax, TOK_SEMI
    xor edx, edx
    call lex_emit
    inc r12
    jmp .next
.comment:
    inc r12
.skip_comment:
    cmp r12, r14
    jae .done
    movzx eax, byte [r13 + r12]
    cmp al, 10
    je .next
    inc r12
    jmp .skip_comment
.maybe_comment:
    mov rbx, r12
    inc rbx
    cmp rbx, r14
    jae .op_slash
    cmp byte [r13 + rbx], '/'
    je .comment_slash
    cmp byte [r13 + rbx], '='
    je .op_slasheq
    jmp .op_slash
.comment_slash:
    mov r12, rbx
    inc r12
    jmp .skip_comment
.op_slasheq:
    mov rax, TOK_SLASHEQ
    xor edx, edx
    call lex_emit
    add r12, 2
    jmp .next
.op_slash:
    mov rax, TOK_SLASH
    xor edx, edx
    call lex_emit
    inc r12
    jmp .next
.number:
    call lex_number
    jmp .next
.string:
    call lex_string
    jmp .next
.ident:
    call lex_ident
    jmp .next
.symbol:
    call lex_symbol
    jmp .next
.done:
    mov rax, TOK_EOF
    xor edx, edx
    call lex_emit
    mov rax, [lex_tokcount]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------- lex_number: R12/R13/R14 live, advances R12 ----------
lex_number:
    push rbx
    xor ebx, ebx                      ; int part
.digits:
    cmp r12, r14
    jae .check_frac
    movzx eax, byte [r13 + r12]
    cmp al, '0'
    jb .check_frac
    cmp al, '9'
    ja .check_frac
    imul rbx, rbx, 10
    sub eax, '0'
    add rbx, rax
    inc r12
    jmp .digits
.check_frac:
    mov rax, r12
    inc rax
    cmp rax, r14
    jae .emit_int
    cmp byte [r13 + r12], '.'
    jne .emit_int
    movzx eax, byte [r13 + rax]
    cmp al, '0'
    jb .emit_int
    cmp al, '9'
    ja .emit_int
    ; float: consume '.' + frac digits
    inc r12
    xor r8d, r8d                      ; frac value
    xor r9d, r9d                      ; frac digit count
.frac:
    cmp r12, r14
    jae .build_float
    movzx eax, byte [r13 + r12]
    cmp al, '0'
    jb .build_float
    cmp al, '9'
    ja .build_float
    imul r8, r8, 10
    sub eax, '0'
    add r8, rax
    inc r9
    inc r12
    jmp .frac
.build_float:
    cvtsi2sd xmm0, rbx
    cvtsi2sd xmm1, r8
    mov eax, 1
    mov ecx, r9d
    test ecx, ecx
    jz .pow_done
.pow:
    imul rax, rax, 10
    dec ecx
    jnz .pow
.pow_done:
    cvtsi2sd xmm2, rax
    divsd xmm1, xmm2
    addsd xmm0, xmm1
    movq rdx, xmm0
    mov rax, TOK_FLOAT
    call lex_emit
    pop rbx
    ret
.emit_int:
    mov rdx, rbx
    mov rax, TOK_INT
    call lex_emit
    pop rbx
    ret

; ---------- lex_string ----------
; In/out: R12 cursor, R13 src base, R14 len. Preserves R13/R14, advances R12.
lex_string:
    push rbx
    push r13
    push r14
    push r15
    sub rsp, 8                            ; 4 pushes + 8 => 40 bytes => align for calls
    mov r15, r12
    inc r15                           ; skip opening quote
    ; first pass: compute decoded length + validate
    xor ebx, ebx                      ; decoded len
    mov r12, r15
.scan:
    cmp r12, r14
    jae .unterminated
    movzx eax, byte [r13 + r12]
    cmp al, '"'
    je .alloc
    cmp al, 10
    je .unterminated
    cmp al, '\'
    je .esc_len
    inc rbx
    inc r12
    jmp .scan
.esc_len:
    inc r12
    cmp r12, r14
    jae .unterminated
    movzx eax, byte [r13 + r12]
    cmp al, 'n'
    je .esc_ok
    cmp al, 't'
    je .esc_ok
    cmp al, 'r'
    je .esc_ok
    cmp al, '\'
    je .esc_ok
    cmp al, '"'
    je .esc_ok
    jmp .badesc
.esc_ok:
    inc rbx
    inc r12
    jmp .scan
.alloc:
    mov rcx, rbx
    inc rcx
    call lex_pool_alloc               ; RAX = dest
    push rax                          ; save base (lex_pool_alloc uses RAX, clobbered by copy loop)
    mov rdx, rax
    mov r12, r15
.copy:
    cmp r12, r14
    jae .unterminated
    movzx eax, byte [r13 + r12]
    cmp al, '"'
    je .finish
    cmp al, '\'
    je .esc_copy
    mov [rdx], al
    inc rdx
    inc r12
    jmp .copy
.esc_copy:
    inc r12
    movzx eax, byte [r13 + r12]
    cmp al, 'n'
    je .c_n
    cmp al, 't'
    je .c_t
    cmp al, 'r'
    je .c_r
    cmp al, '\'
    je .c_b
    cmp al, '"'
    je .c_q
    jmp .badesc
.c_n:
    mov byte [rdx], 10
    inc rdx
    inc r12
    jmp .copy
.c_t:
    mov byte [rdx], 9
    inc rdx
    inc r12
    jmp .copy
.c_r:
    mov byte [rdx], 13
    inc rdx
    inc r12
    jmp .copy
.c_b:
    mov byte [rdx], '\'
    inc rdx
    inc r12
    jmp .copy
.c_q:
    mov byte [rdx], '"'
    inc rdx
    inc r12
    jmp .copy
.finish:
    mov byte [rdx], 0
    inc r12                           ; skip closing quote
    pop rdx                           ; restore base
    mov rax, TOK_STRING
    push rax
    push rdx
    call lex_emit
    pop rdx
    pop rax
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop rbx
    ret
.unterminated:
    lea rsi, [lex_err_unterm]
    call lex_error
.badesc:
    lea rsi, [lex_err_badesc]
    call lex_error

; ---------- lex_ident ----------
lex_ident:
    push rbx
    mov rbx, r12
.scan:
    cmp r12, r14
    jae .copy
    movzx eax, byte [r13 + r12]
    cmp al, '_'
    je .keep
    cmp al, '0'
    jb .copy
    cmp al, '9'
    jbe .keep
    cmp al, 'A'
    jb .copy
    cmp al, 'Z'
    jbe .keep
    cmp al, 'a'
    jb .copy
    cmp al, 'z'
    jbe .keep
    jmp .copy
.keep:
    inc r12
    jmp .scan
.copy:
    mov rax, r12
    sub rax, rbx                      ; len
    mov rcx, rax
    inc rcx
    push rax
    push rbx
    call lex_pool_alloc               ; RAX = dest
    pop rbx
    pop rcx                           ; len
    mov rdx, rax
    push rdx
    xor r8d, r8d
    lea r9, [r13 + rbx]
.cp:
    cmp r8, rcx
    jae .cp_done
    mov al, [r9 + r8]
    mov [rdx + r8], al
    inc r8
    jmp .cp
.cp_done:
    mov byte [rdx + rcx], 0
    pop rdx                           ; payload ptr
    mov rsi, rdx
    ; keyword check
    push rdx
    push r12
    mov rdi, kw_true
    call streq
    test eax, eax
    jnz .kw_true
    mov rsi, [rsp + 8]
    mov rdi, kw_false
    call streq
    test eax, eax
    jnz .kw_false
    mov rsi, [rsp + 8]
    mov rdi, kw_null
    call streq
    test eax, eax
    jnz .kw_null
    mov rsi, [rsp + 8]
    mov rdi, kw_fn
    call streq
    test eax, eax
    jnz .kw_fn
    mov rsi, [rsp + 8]
    mov rdi, kw_if
    call streq
    test eax, eax
    jnz .kw_if
    mov rsi, [rsp + 8]
    mov rdi, kw_else
    call streq
    test eax, eax
    jnz .kw_else
    mov rsi, [rsp + 8]
    mov rdi, kw_while
    call streq
    test eax, eax
    jnz .kw_while
    mov rsi, [rsp + 8]
    mov rdi, kw_return
    call streq
    test eax, eax
    jnz .kw_return
    mov rsi, [rsp + 8]
    mov rdi, kw_import
    call streq
    test eax, eax
    jnz .kw_import
    mov rsi, [rsp + 8]
    mov rdi, kw_break
    call streq
    test eax, eax
    jnz .kw_break
    mov rsi, [rsp + 8]
    mov rdi, kw_continue
    call streq
    test eax, eax
    jnz .kw_continue
    mov rsi, [rsp + 8]
    mov rdi, kw_for
    call streq
    test eax, eax
    jnz .kw_for
    mov rsi, [rsp + 8]
    mov rdi, kw_in
    call streq
    test eax, eax
    jnz .kw_in
    ; identifier
    pop r12
    pop rdx
    mov rax, TOK_IDENT
    call lex_emit
    pop rbx
    ret
.kw_true:
    pop r12
    pop rdx
    mov rax, TOK_TRUE
    xor edx, edx
    call lex_emit
    pop rbx
    ret
.kw_false:
    pop r12
    pop rdx
    mov rax, TOK_FALSE
    xor edx, edx
    call lex_emit
    pop rbx
    ret
.kw_null:
    pop r12
    pop rdx
    mov rax, TOK_NULL
    xor edx, edx
    call lex_emit
    pop rbx
    ret
.kw_fn:
    pop r12
    pop rdx
    mov rax, TOK_FN
    xor edx, edx
    call lex_emit
    pop rbx
    ret
.kw_if:
    pop r12
    pop rdx
    mov rax, TOK_IF
    xor edx, edx
    call lex_emit
    pop rbx
    ret
.kw_else:
    pop r12
    pop rdx
    mov rax, TOK_ELSE
    xor edx, edx
    call lex_emit
    pop rbx
    ret
.kw_while:
    pop r12
    pop rdx
    mov rax, TOK_WHILE
    xor edx, edx
    call lex_emit
    pop rbx
    ret
.kw_return:
    pop r12
    pop rdx
    mov rax, TOK_RETURN
    xor edx, edx
    call lex_emit
    pop rbx
    ret
.kw_import:
    pop r12
    pop rdx
    mov rax, TOK_IMPORT
    xor edx, edx
    call lex_emit
    pop rbx
    ret
.kw_break:
    pop r12
    pop rdx
    mov rax, TOK_BREAK
    xor edx, edx
    call lex_emit
    pop rbx
    ret
.kw_continue:
    pop r12
    pop rdx
    mov rax, TOK_CONTINUE
    xor edx, edx
    call lex_emit
    pop rbx
    ret
.kw_for:
    pop r12
    pop rdx
    mov rax, TOK_FOR
    xor edx, edx
    call lex_emit
    pop rbx
    ret
.kw_in:
    pop r12
    pop rdx
    mov rax, TOK_IN
    xor edx, edx
    call lex_emit
    pop rbx
    ret

; ---------- lex_symbol ----------
lex_symbol:
    push rbx
    movzx eax, byte [r13 + r12]
    mov bl, al
    ; peek next
    mov ecx, r12d
    inc ecx
    cmp ecx, r14d
    jae .single
    movzx edx, byte [r13 + rcx]
    cmp bl, '='
    je .eq
    cmp bl, '!'
    je .bang
    cmp bl, '>'
    je .gt
    cmp bl, '<'
    je .lt
    cmp bl, '&'
    je .amp
    cmp bl, '|'
    je .pipe
    cmp bl, '+'
    je .plus
    cmp bl, '-'
    je .minus
    cmp bl, '*'
    je .star
    jmp .single
.plus:
    cmp dl, '='
    je .emit_pluseq
    jmp .s_plus
.emit_pluseq:
    mov rax, TOK_PLUSEQ
    xor edx, edx
    call lex_emit
    add r12, 2
    pop rbx
    ret
.minus:
    cmp dl, '='
    je .emit_minuseq
    jmp .s_minus
.emit_minuseq:
    mov rax, TOK_MINUSEQ
    xor edx, edx
    call lex_emit
    add r12, 2
    pop rbx
    ret
.star:
    cmp dl, '='
    je .emit_stareq
    jmp .s_star
.emit_stareq:
    mov rax, TOK_STAREQ
    xor edx, edx
    call lex_emit
    add r12, 2
    pop rbx
    ret
.eq:
    cmp dl, '='
    je .emit_eqeq
    mov rax, TOK_ASSIGN
    xor edx, edx
    call lex_emit
    inc r12
    pop rbx
    ret
.emit_eqeq:
    mov rax, TOK_EQEQ
    xor edx, edx
    call lex_emit
    add r12, 2
    pop rbx
    ret
.bang:
    cmp dl, '='
    je .emit_neq
    mov rax, TOK_BANG
    xor edx, edx
    call lex_emit
    inc r12
    pop rbx
    ret
.emit_neq:
    mov rax, TOK_NEQ
    xor edx, edx
    call lex_emit
    add r12, 2
    pop rbx
    ret
.gt:
    cmp dl, '='
    je .emit_gte
    mov rax, TOK_GT
    xor edx, edx
    call lex_emit
    inc r12
    pop rbx
    ret
.emit_gte:
    mov rax, TOK_GTE
    xor edx, edx
    call lex_emit
    add r12, 2
    pop rbx
    ret
.lt:
    cmp dl, '='
    je .emit_lte
    mov rax, TOK_LT
    xor edx, edx
    call lex_emit
    inc r12
    pop rbx
    ret
.emit_lte:
    mov rax, TOK_LTE
    xor edx, edx
    call lex_emit
    add r12, 2
    pop rbx
    ret
.amp:
    cmp dl, '&'
    je .emit_and
    jmp .bad_char
.emit_and:
    mov rax, TOK_ANDAND
    xor edx, edx
    call lex_emit
    add r12, 2
    pop rbx
    ret
.pipe:
    cmp dl, '|'
    je .emit_or
    jmp .bad_char
.emit_or:
    mov rax, TOK_OROR
    xor edx, edx
    call lex_emit
    add r12, 2
    pop rbx
    ret
.single:
    cmp bl, '+'
    je .s_plus
    cmp bl, '-'
    je .s_minus
    cmp bl, '*'
    je .s_star
    cmp bl, '%'
    je .s_pct
    cmp bl, '('
    je .s_lp
    cmp bl, ')'
    je .s_rp
    cmp bl, '{'
    je .s_lb
    cmp bl, '}'
    je .s_rb
    cmp bl, '['
    je .s_lbr
    cmp bl, ']'
    je .s_rbr
    cmp bl, ','
    je .s_comma
    cmp bl, ':'
    je .s_colon
    cmp bl, '.'
    je .s_dot
    jmp .bad_char
.s_plus:
    mov rax, TOK_PLUS
    xor edx, edx
    call lex_emit
    inc r12
    pop rbx
    ret
.s_minus:
    mov rax, TOK_MINUS
    xor edx, edx
    call lex_emit
    inc r12
    pop rbx
    ret
.s_star:
    mov rax, TOK_STAR
    xor edx, edx
    call lex_emit
    inc r12
    pop rbx
    ret
.s_pct:
    mov rax, TOK_PERCENT
    xor edx, edx
    call lex_emit
    inc r12
    pop rbx
    ret
.s_lp:
    mov rax, TOK_LPAREN
    xor edx, edx
    call lex_emit
    inc r12
    pop rbx
    ret
.s_rp:
    mov rax, TOK_RPAREN
    xor edx, edx
    call lex_emit
    inc r12
    pop rbx
    ret
.s_lb:
    mov rax, TOK_LBRACE
    xor edx, edx
    call lex_emit
    inc r12
    pop rbx
    ret
.s_rb:
    mov rax, TOK_RBRACE
    xor edx, edx
    call lex_emit
    inc r12
    pop rbx
    ret
.s_lbr:
    mov rax, TOK_LBRACKET
    xor edx, edx
    call lex_emit
    inc r12
    pop rbx
    ret
.s_rbr:
    mov rax, TOK_RBRACKET
    xor edx, edx
    call lex_emit
    inc r12
    pop rbx
    ret
.s_comma:
    mov rax, TOK_COMMA
    xor edx, edx
    call lex_emit
    inc r12
    pop rbx
    ret
.s_colon:
    mov rax, TOK_COLON
    xor edx, edx
    call lex_emit
    inc r12
    pop rbx
    ret
.s_dot:
    mov rax, TOK_DOT
    xor edx, edx
    call lex_emit
    inc r12
    pop rbx
    ret
.bad_char:
    lea rsi, [lex_errbuf]
    lea rdi, [lex_err_unexp]
    push rsi
    call strcpy_helper
    pop rsi
    movzx eax, bl
    ; append char + "'" + NUL
.append:
    cmp byte [rsi], 0
    je .found_end
    inc rsi
    jmp .append
.found_end:
    mov [rsi], al
    mov byte [rsi + 1], "'"
    mov byte [rsi + 2], 0
    lea rsi, [lex_errbuf]
    call lex_error

; ---------- strcpy_helper(RSI=dst, RDI=src) ----------
strcpy_helper:
.copy:
    mov al, [rdi]
    mov [rsi], al
    test al, al
    jz .done
    inc rsi
    inc rdi
    jmp .copy
.done:
    ret

; ---------- token_kind_name(RAX=kind) -> RSI name ----------
token_kind_name:
    cmp rax, TOK_EOF
    je .eof
    cmp rax, TOK_INT
    je .int
    cmp rax, TOK_FLOAT
    je .float
    cmp rax, TOK_STRING
    je .string
    cmp rax, TOK_IDENT
    je .ident
    cmp rax, TOK_TRUE
    je .true
    cmp rax, TOK_FALSE
    je .false
    cmp rax, TOK_NULL
    je .null
    cmp rax, TOK_FN
    je .fn
    cmp rax, TOK_IF
    je .if
    cmp rax, TOK_ELSE
    je .else
    cmp rax, TOK_WHILE
    je .while
    cmp rax, TOK_RETURN
    je .return
    cmp rax, TOK_IMPORT
    je .import
    cmp rax, TOK_BREAK
    je .break
    cmp rax, TOK_CONTINUE
    je .continue
    cmp rax, TOK_FOR
    je .for
    cmp rax, TOK_IN
    je .in
    cmp rax, TOK_PLUSEQ
    je .pluseq
    cmp rax, TOK_MINUSEQ
    je .minuseq
    cmp rax, TOK_STAREQ
    je .stareq
    cmp rax, TOK_SLASHEQ
    je .slasheq
    cmp rax, TOK_PLUS
    je .plus
    cmp rax, TOK_MINUS
    je .minus
    cmp rax, TOK_STAR
    je .star
    cmp rax, TOK_SLASH
    je .slash
    cmp rax, TOK_PERCENT
    je .pct
    cmp rax, TOK_EQEQ
    je .eqeq
    cmp rax, TOK_NEQ
    je .neq
    cmp rax, TOK_GT
    je .gt
    cmp rax, TOK_LT
    je .lt
    cmp rax, TOK_GTE
    je .gte
    cmp rax, TOK_LTE
    je .lte
    cmp rax, TOK_ANDAND
    je .and
    cmp rax, TOK_OROR
    je .or
    cmp rax, TOK_BANG
    je .bang
    cmp rax, TOK_ASSIGN
    je .assign
    cmp rax, TOK_LPAREN
    je .lp
    cmp rax, TOK_RPAREN
    je .rp
    cmp rax, TOK_LBRACE
    je .lb
    cmp rax, TOK_RBRACE
    je .rb
    cmp rax, TOK_LBRACKET
    je .lbr
    cmp rax, TOK_RBRACKET
    je .rbr
    cmp rax, TOK_COMMA
    je .comma
    cmp rax, TOK_COLON
    je .colon
    cmp rax, TOK_DOT
    je .dot
    cmp rax, TOK_SEMI
    je .semi
    lea rsi, [tn_q]
    ret
.eof:     lea rsi, [tn_eof]
    ret
.int:     lea rsi, [tn_int]
    ret
.float:   lea rsi, [tn_float]
    ret
.string:  lea rsi, [tn_string]
    ret
.ident:   lea rsi, [tn_ident]
    ret
.true:    lea rsi, [tn_true]
    ret
.false:   lea rsi, [tn_false]
    ret
.null:    lea rsi, [tn_null]
    ret
.fn:      lea rsi, [tn_fn]
    ret
.if:      lea rsi, [tn_if]
    ret
.else:    lea rsi, [tn_else]
    ret
.while:   lea rsi, [tn_while]
    ret
.return:  lea rsi, [tn_return]
    ret
.import:  lea rsi, [tn_import]
    ret
.break:   lea rsi, [tn_break]
    ret
.continue: lea rsi, [tn_continue]
    ret
.for:     lea rsi, [tn_for]
    ret
.in:      lea rsi, [tn_in]
    ret
.pluseq:  lea rsi, [tn_pluseq]
    ret
.minuseq: lea rsi, [tn_minuseq]
    ret
.stareq:  lea rsi, [tn_stareq]
    ret
.slasheq: lea rsi, [tn_slasheq]
    ret
.plus:    lea rsi, [tn_plus]
    ret
.minus:   lea rsi, [tn_minus]
    ret
.star:    lea rsi, [tn_star]
    ret
.slash:   lea rsi, [tn_slash]
    ret
.pct:     lea rsi, [tn_pct]
    ret
.eqeq:    lea rsi, [tn_eqeq]
    ret
.neq:     lea rsi, [tn_neq]
    ret
.gt:      lea rsi, [tn_gt]
    ret
.lt:      lea rsi, [tn_lt]
    ret
.gte:     lea rsi, [tn_gte]
    ret
.lte:     lea rsi, [tn_lte]
    ret
.and:     lea rsi, [tn_and]
    ret
.or:      lea rsi, [tn_or]
    ret
.bang:    lea rsi, [tn_bang]
    ret
.assign:  lea rsi, [tn_assign]
    ret
.lp:      lea rsi, [tn_lp]
    ret
.rp:      lea rsi, [tn_rp]
    ret
.lb:      lea rsi, [tn_lb]
    ret
.rb:      lea rsi, [tn_rb]
    ret
.lbr:     lea rsi, [tn_lbr]
    ret
.rbr:     lea rsi, [tn_rbr]
    ret
.comma:   lea rsi, [tn_comma]
    ret
.colon:   lea rsi, [tn_colon]
    ret
.dot:     lea rsi, [tn_dot]
    ret
.semi:    lea rsi, [tn_semi]
    ret

; ---------- print_hex_u64(RAX): prints 0x + 16 hex digits ----------
print_hex_u64:
    push rbx
    push rax
    lea rdi, [lex_hexbuf]
    mov byte [rdi], '0'
    mov byte [rdi + 1], 'x'
    mov rbx, rax
    mov rcx, 16
    lea rsi, [hex_digits]
.hex_loop:
    rol rbx, 4
    mov rax, rbx
    and rax, 0xF
    mov al, [rsi + rax]
    mov [rdi + 2], al
    inc rdi
    dec rcx
    jnz .hex_loop
    mov byte [rdi + 2], 0
    pop rax
    lea rsi, [lex_hexbuf]
    call print_cstr
    pop rbx
    ret

; ---------- lexer_dump(): one line per token ----------
; k=4 pushes -> sub 0x28 keeps calls ABI-aligned.
lexer_dump:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 0x28
    mov r13, [lex_tokcount]
    xor r12d, r12d
.loop:
    cmp r12, r13
    jae .done
    imul rax, r12, LEX_TOK_SIZE
    lea rbx, [lex_tokens + rax]
    mov rax, [rbx]
    push rax
    push rbx
    call token_kind_name        ; RSI = name
    call print_cstr
    pop rbx
    pop rax
    cmp rax, TOK_INT
    je .p_int
    cmp rax, TOK_FLOAT
    je .p_float
    cmp rax, TOK_STRING
    je .p_str
    cmp rax, TOK_IDENT
    je .p_str
    jmp .p_line
.p_int:
    lea rsi, [tn_sp]
    call print_cstr
    mov rax, [rbx + 8]
    call print_u64
    jmp .p_line
.p_float:
    lea rsi, [tn_sp]
    call print_cstr
    mov rax, [rbx + 8]
    call print_hex_u64
    jmp .p_line
.p_str:
    lea rsi, [tn_sp]
    call print_cstr
    lea rsi, [tn_q]
    call print_cstr
    mov rsi, [rbx + 8]
    call print_cstr
    lea rsi, [tn_q]
    call print_cstr
    jmp .p_line
.p_line:
    lea rsi, [tn_lparen2]
    call print_cstr
    mov rax, [rbx + 16]
    call print_u64
    lea rsi, [tn_rparen]
    call print_cstr
    inc r12
    jmp .loop
.done:
    add rsp, 0x28
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
