; ShitCam parser - recursive descent, builds 48-byte AST nodes.
; Requires lexer.asm globals (lex_tokens, lex_tokcount, lex_path).
; Windows x64 ABI, preserve RBX,R12-R15.

%define AST_NODE_SIZE 48
%define AST_POOL_SIZE 33554432
%define AST_NODES_SIZE (SC_MAX_AST_NODES * AST_NODE_SIZE)

section .data
    p_err_expected    db "expected '", 0
    p_err_expected2   db "'", 0
    p_err_unexpected  db "unexpected token '", 0
    p_err_unexpected2 db "'", 0
    p_err_eof         db "unexpected end of file", 0
    p_err_many_nodes  db "too many AST nodes", 0
    p_err_pool        db "out of AST memory", 0
    p_err_mem         db "Error: out of memory", 13, 10, 0
    p_str_program     db "Program", 0
    p_str_block       db "Block", 0
    p_str_assign      db "Assign", 0
    p_str_var         db "Var", 0
    p_str_int         db "Int", 0
    p_str_float       db "Float", 0
    p_str_string      db "String", 0
    p_str_bool        db "Bool", 0
    p_str_null        db "Null", 0
    p_str_binary      db "Binary", 0
    p_str_unary       db "Unary", 0
    p_str_if          db "If", 0
    p_str_while       db "While", 0
    p_str_fndef       db "FnDef", 0
    p_str_call        db "Call", 0
    p_str_return      db "Return", 0
    p_str_array       db "Array", 0
    p_str_object      db "Object", 0
    p_str_index       db "Index", 0
    p_str_member      db "Member", 0
    p_str_import      db "Import", 0
    p_str_exprstmt    db "ExprStmt", 0
    p_str_break       db "Break", 0
    p_str_continue    db "Continue", 0
    p_str_for         db "For", 0
    p_indent_str      db "  ", 0
    p_nl              db 13, 10, 0
    p_colon_sp        db ": ", 0
    p_lparen          db " (", 0
    p_rparen          db ")", 0

section .bss
    p_pos          resq 1
    p_nodes        resq 1
    p_nodecount    resq 1
    p_data         resq 1
    p_data_used    resq 1
    parser_root    resq 1
    parser_path    resq 1
    p_tmp          resq 1
    p_call_callee  resq 1
    p_call_args    resq 1
    p_call_count   resq 1

section .text

; ---------- parser_init() ----------
parser_init:
    push rbx
    mov rax, [lex_path]
    mov [parser_path], rax
    mov qword [p_pos], 0
    mov qword [p_nodecount], 0
    mov qword [p_data_used], 0
    sub rsp, 0x20
    xor ecx, ecx
    mov rdx, AST_NODES_SIZE
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_READWRITE
    call VirtualAlloc
    add rsp, 0x20
    test rax, rax
    jz .oom
    mov [p_nodes], rax
    sub rsp, 0x20
    xor ecx, ecx
    mov rdx, AST_POOL_SIZE
    mov r8d, MEM_COMMIT | MEM_RESERVE
    mov r9d, PAGE_READWRITE
    call VirtualAlloc
    add rsp, 0x20
    test rax, rax
    jz .oom
    mov [p_data], rax
    pop rbx
    ret
.oom:
    lea rsi, [p_err_mem]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x20
    call ExitProcess

; ---------- p_alloc_data(RCX=size) -> RAX ptr (8-aligned) ----------
p_alloc_data:
    mov rax, [p_data_used]
    add rax, 7
    and rax, -8
    mov rdx, rax
    add rdx, rcx
    cmp rdx, AST_POOL_SIZE
    ja .oom
    mov [p_data_used], rdx
    add rax, [p_data]
    ret
.oom:
    lea rsi, [p_err_pool]
    call p_error

; ---------- p_alloc_node() -> RAX node ptr ----------
p_alloc_node:
    mov rax, [p_nodecount]
    cmp rax, SC_MAX_AST_NODES
    jae .oom
    inc qword [p_nodecount]
    imul rax, rax, AST_NODE_SIZE
    add rax, [p_nodes]
    ; zero 48 bytes
    mov qword [rax], 0
    mov qword [rax+8], 0
    mov qword [rax+16], 0
    mov qword [rax+24], 0
    mov qword [rax+32], 0
    mov qword [rax+40], 0
    ret
.oom:
    lea rsi, [p_err_many_nodes]
    call p_error

; ---------- p_cur: returns RAX=kind, RDX=payload, RCX=line ----------
p_cur:
    mov rax, [p_pos]
    imul rax, rax, 24
    lea rax, [lex_tokens + rax]
    mov rdx, [rax+8]
    mov rcx, [rax+16]
    mov rax, [rax]
    ret

; ---------- p_peek(RCX=offset) -> RAX=kind ----------
p_peek:
    push rdx
    push rcx
    mov rax, [p_pos]
    add rax, rcx
    imul rax, rax, 24
    lea rax, [lex_tokens + rax]
    mov rax, [rax]
    pop rcx
    pop rdx
    ret

; ---------- p_advance ----------
p_advance:
    inc qword [p_pos]
    ret

; ---------- p_error(RSI=msg) fatal ----------
p_error:
    push rbx
    push r12
    push r13
    sub rsp, 0x20
    mov rbx, rsi
    call p_cur                ; RAX kind, RCX line
    mov r12, rax
    mov r13, rcx
    lea rsi, [lex_err_pre]
    call print_cstr
    mov rsi, rbx
    call print_cstr
    lea rsi, [nl_str]
    call print_cstr
    lea rsi, [lex_file_pre]
    call print_cstr
    mov rsi, [parser_path]
    call print_cstr
    lea rsi, [nl_str]
    call print_cstr
    lea rsi, [lex_line_pre]
    call print_cstr
    mov rax, r13
    call print_u64
    lea rsi, [nl_str]
    call print_cstr
    lea rsi, [tn_sp]
    call print_cstr
    mov rax, r12
    call token_kind_name
    call print_cstr
    mov rax, r12
    cmp rax, TOK_STRING
    je .with_str
    cmp rax, TOK_IDENT
    je .with_str
    jmp .nl
.with_str:
    lea rsi, [tn_sp]
    call print_cstr
    lea rsi, [tn_q]
    call print_cstr
    call p_cur
    mov rsi, rdx
    call print_cstr
    lea rsi, [tn_q]
    call print_cstr
.nl:
    lea rsi, [nl_str]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x20
    call ExitProcess

; ---------- p_expect(RAX=kind) ----------
p_expect:
    push rax
    call p_cur
    pop rcx
    cmp rax, rcx
    je .ok
    ; build "expected 'KIND'" msg? For now generic
    push rcx
    mov rax, rcx
    call token_kind_name
    mov rbx, rsi
    lea rsi, [p_err_expected]
    call print_cstr
    mov rsi, rbx
    call print_cstr
    lea rsi, [p_err_expected2]
    call print_cstr
    lea rsi, [nl_str]
    call print_cstr
    pop rcx
    lea rsi, [p_err_unexpected]
    call p_error
.ok:
    call p_advance
    ret

; ---------- node helpers ----------
; create node RAX=kind, RDX=op, RCX=left, R8=mid, R9=right, stack line
; Use wrapper p_new_node

; ---------- p_new_node(RAX=kind,RDX=op,RCX=left,R8=mid,R9=right,R10=line) -> RAX node ---
p_new_node:
    push rbx
    push r12
    mov r12, rax
    mov rbx, rdx
    push rcx
    push r8
    push r9
    push r10
    sub rsp, 0x08
    call p_alloc_node
    add rsp, 0x08
    pop r10
    pop r9
    pop r8
    pop rcx
    mov [rax], r12
    mov [rax+8], rbx
    mov [rax+16], rcx
    mov [rax+24], r8
    mov [rax+32], r9
    mov [rax+40], r10
    pop r12
    pop rbx
    ret

; ---------- Forward decls ----------
; parseProgram, parseStatement, parseBlockStmts, parseExpression etc.

; ---------- parseArray -> RAX node ----------
parseArray:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 0x28
    call p_cur
    mov r12, rcx           ; line
    mov rax, TOK_LBRACKET
    call p_expect
    ; count elements
    call p_cur
    cmp rax, TOK_RBRACKET
    je .empty
    ; collect elements into temporary array on ast_data
    ; first count
    xor r13d, r13d
    ; we need to parse elements to count: instead parse into stack-allocated list via heap array
    ; Approach: allocate max 256 temp slots on stack? Use ast_data to store pointers
    ; For simplicity, allocate 2048*8 = 16384 for elements directly, then fill.
    mov rcx, 2048*8
    call p_alloc_data
    mov r14, rax           ; elements base
    xor r13d, r13d
.loop:
    call parseExpression
    mov [r14 + r13*8], rax
    inc r13
    call p_cur
    cmp rax, TOK_COMMA
    jne .end
    call p_advance
    jmp .loop
.end:
    mov rax, TOK_RBRACKET
    call p_expect
    ; create node
    mov rax, AST_ARRAY
    mov rdx, r13            ; count in op
    mov rcx, r14
    xor r8d, r8d
    xor r9d, r9d
    mov r10, r12
    call p_new_node
    add rsp, 0x28
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.empty:
    mov rax, TOK_RBRACKET
    call p_expect
    mov rax, AST_ARRAY
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    mov r10, r12
    call p_new_node
    add rsp, 0x28
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------- parseObject -> RAX node ----------
parseObject:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 0x28
    call p_cur
    mov r12, rcx
    mov rax, TOK_LBRACE
    call p_expect
    call p_cur
    cmp rax, TOK_RBRACE
    je .empty
    mov rcx, 2048*8
    call p_alloc_data
    mov r13, rax   ; keys base
    mov rcx, 2048*8
    call p_alloc_data
    mov r14, rax   ; vals base
    xor r15d, r15d
.loop:
    call p_cur
    cmp rax, TOK_IDENT
    je .key_ident
    cmp rax, TOK_STRING
    je .key_string
    lea rsi, [p_err_expected]
    call p_error
.key_ident:
.key_string:
    mov rdx, rdx   ; payload is string ptr
    push rdx
    push r13
    push r14
    push r15
    mov rbx, rdx
    call p_advance
    mov rax, TOK_COLON
    call p_expect
    call parseExpression
    mov rcx, rax
    pop r15
    pop r14
    pop r13
    pop rdx
    mov [r13 + r15*8], rdx
    mov [r14 + r15*8], rcx
    mov rdx, rbx  ; not needed
    inc r15
    call p_cur
    cmp rax, TOK_COMMA
    jne .check_end
    call p_advance
    jmp .loop
.check_end:
    cmp rax, TOK_RBRACE
    je .done
    jmp .loop
.done:
    mov rax, TOK_RBRACE
    call p_expect
    mov rax, AST_OBJECT
    mov rdx, r15
    mov rcx, r13
    mov r8, r14
    xor r9d, r9d
    mov r10, r12
    call p_new_node
    add rsp, 0x28
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.empty:
    mov rax, TOK_RBRACE
    call p_expect
    mov rax, AST_OBJECT
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    mov r10, r12
    call p_new_node
    add rsp, 0x28
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------- parsePrimary -> RAX node ----------
parsePrimary:
    push rbx
    push r12
    push r13
    call p_cur
    mov r12, rax
    mov r13, rdx
    mov rbx, rcx ; line
    cmp r12, TOK_INT
    je .int
    cmp r12, TOK_FLOAT
    je .float
    cmp r12, TOK_STRING
    je .string
    cmp r12, TOK_TRUE
    je .true
    cmp r12, TOK_FALSE
    je .false
    cmp r12, TOK_NULL
    je .null
    cmp r12, TOK_IDENT
    je .ident
    cmp r12, TOK_LPAREN
    je .paren
    cmp r12, TOK_LBRACKET
    je .array
    cmp r12, TOK_LBRACE
    je .object
    lea rsi, [p_err_unexpected]
    call p_error
.int:
    call p_advance
    mov rax, AST_INT
    xor edx, edx
    mov rcx, r13
    xor r8d, r8d
    xor r9d, r9d
    mov r10, rbx
    call p_new_node
    pop r13
    pop r12
    pop rbx
    ret
.float:
    call p_advance
    mov rax, AST_FLOAT
    xor edx, edx
    mov rcx, r13
    xor r8d, r8d
    xor r9d, r9d
    mov r10, rbx
    call p_new_node
    pop r13
    pop r12
    pop rbx
    ret
.string:
    call p_advance
    mov rax, AST_STRING
    xor edx, edx
    mov rcx, r13
    xor r8d, r8d
    xor r9d, r9d
    mov r10, rbx
    call p_new_node
    pop r13
    pop r12
    pop rbx
    ret
.true:
    call p_advance
    mov rax, AST_BOOL
    mov rdx, 1
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    mov r10, rbx
    call p_new_node
    pop r13
    pop r12
    pop rbx
    ret
.false:
    call p_advance
    mov rax, AST_BOOL
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    mov r10, rbx
    call p_new_node
    pop r13
    pop r12
    pop rbx
    ret
.null:
    call p_advance
    mov rax, AST_NULL
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    mov r10, rbx
    call p_new_node
    pop r13
    pop r12
    pop rbx
    ret
.ident:
    call p_advance
    mov rax, AST_VAR
    xor edx, edx
    mov rcx, r13
    xor r8d, r8d
    xor r9d, r9d
    mov r10, rbx
    call p_new_node
    pop r13
    pop r12
    pop rbx
    ret
.paren:
    call p_advance
    call parseExpression
    push rax
    mov rax, TOK_RPAREN
    call p_expect
    pop rax
    pop r13
    pop r12
    pop rbx
    ret
.array:
    call parseArray
    pop r13
    pop r12
    pop rbx
    ret
.object:
    call parseObject
    pop r13
    pop r12
    pop rbx
    ret

; ---------- parsePostfix: primary ( '(' args ')' | '.' IDENT | '[' expr ']' )* ----------
parsePostfix:
    push rbx
    push r12
    push r13
    call parsePrimary
    mov r12, rax ; current node
.loop:
    call p_cur
    cmp rax, TOK_LPAREN
    je .call
    cmp rax, TOK_DOT
    je .member
    cmp rax, TOK_LBRACKET
    je .index
    mov rax, r12
    pop r13
    pop r12
    pop rbx
    ret
.call:
    call p_advance
    mov r13, r12 ; callee (r13 is saved across nested parse calls)
    ; parse args
    call p_cur
    cmp rax, TOK_RPAREN
    je .call_empty
    mov rcx, 2048*8
    call p_alloc_data
    mov rbx, rax ; args base (rbx saved across nested calls)
    xor r10d, r10d ; count (r10 volatile -> protected below)
.call_loop:
    push rbx
    push r13
    push r10
    sub rsp, 8
    call parseExpression
    add rsp, 8
    pop r10
    pop r13
    pop rbx
    mov [rbx + r10*8], rax
    inc r10
    call p_cur
    cmp rax, TOK_COMMA
    jne .call_end
    call p_advance
    jmp .call_loop
.call_end:
    mov rax, TOK_RPAREN
    call p_expect
    ; create call node: left=callee, mid=args base, op=count
    mov rax, AST_CALL
    mov rdx, r10        ; count
    mov rcx, r13        ; callee
    mov r8, rbx         ; args base
    xor r9d, r9d
    mov r10, [r13+40]   ; line (count already consumed into rdx)
    call p_new_node
    mov r12, rax
    jmp .loop
.call_empty:
    mov rax, TOK_RPAREN
    call p_expect
    mov rax, AST_CALL
    xor edx, edx
    mov rcx, r13
    xor r8d, r8d
    xor r9d, r9d
    mov r10, [r13+40]
    call p_new_node
    mov r12, rax
    jmp .loop
.member:
    call p_advance
    call p_cur
    cmp rax, TOK_IDENT
    jne .mem_err
    mov [p_call_callee], r12 ; object
    mov [p_call_args], rdx ; member name ptr
    mov [p_call_count], rcx ; line
    call p_advance
    mov rax, AST_MEMBER
    xor edx, edx
    mov rcx, [p_call_callee]
    mov r8, [p_call_args]
    xor r9d, r9d
    mov r10, [p_call_count]
    call p_new_node
    mov r12, rax
    jmp .loop
.mem_err:
    lea rsi, [p_err_expected]
    call p_error
.index:
    call p_advance
    push r12          ; array node (protect across recursion)
    sub rsp, 8
    call parseExpression
    add rsp, 8
    pop r13           ; array node
    mov rbx, rax      ; index node
    mov rax, TOK_RBRACKET
    call p_expect
    mov rax, AST_INDEX
    xor edx, edx
    mov rcx, r13
    mov r8, rbx
    xor r9d, r9d
    mov r10, [r13+40]
    call p_new_node
    mov r12, rax
    jmp .loop

; ---------- parseUnary ----------
parseUnary:
    push rbx
    push r12
    sub rsp, 0x08
    call p_cur
    cmp rax, TOK_BANG
    je .bang
    cmp rax, TOK_MINUS
    je .minus
    call parsePostfix
    add rsp, 0x08
    pop r12
    pop rbx
    ret
.bang:
    mov r12, rcx
    call p_advance
    call parseUnary
    mov rcx, rax
    mov rax, AST_UNARY
    mov rdx, TOK_BANG
    mov r8, rcx
    xor r9d, r9d
    mov r10, r12
    call p_new_node
    add rsp, 0x08
    pop r12
    pop rbx
    ret
.minus:
    mov r12, rcx
    call p_advance
    call parseUnary
    mov rcx, rax
    mov rax, AST_UNARY
    mov rdx, TOK_MINUS
    mov r8, rcx
    xor r9d, r9d
    mov r10, r12
    call p_new_node
    add rsp, 0x08
    pop r12
    pop rbx
    ret

; ---------- parseFactor: unary ( ('*'|'/'|'%') unary )* ----------
parseFactor:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 0x08
    call parseUnary
    mov r12, rax
.loop:
    call p_cur
    cmp rax, TOK_STAR
    je .op
    cmp rax, TOK_SLASH
    je .op
    cmp rax, TOK_PERCENT
    je .op
    mov rax, r12
    add rsp, 0x08
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.op:
    mov r13, rax ; op
    mov r14, rcx ; line
    call p_advance
    call parseUnary
    mov rbx, rax ; right
    mov rax, AST_BINARY
    mov rdx, r13
    mov rcx, r12
    mov r8, rbx
    xor r9d, r9d
    mov r10, r14
    call p_new_node
    mov r12, rax
    jmp .loop

; ---------- parseTerm: factor ( ('+'|'-') factor )* ----------
parseTerm:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 0x08
    call parseFactor
    mov r12, rax
.loop:
    call p_cur
    cmp rax, TOK_PLUS
    je .op
    cmp rax, TOK_MINUS
    je .op
    mov rax, r12
    add rsp, 0x08
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.op:
    mov r13, rax
    mov r14, rcx
    call p_advance
    call parseFactor
    mov rbx, rax
    mov rax, AST_BINARY
    mov rdx, r13
    mov rcx, r12
    mov r8, rbx
    xor r9d, r9d
    mov r10, r14
    call p_new_node
    mov r12, rax
    jmp .loop

; ---------- parseComparison: term ( ('>'|'<'|'>='|'<=') term )* ----------
parseComparison:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 0x08
    call parseTerm
    mov r12, rax
.loop:
    call p_cur
    cmp rax, TOK_GT
    je .op
    cmp rax, TOK_LT
    je .op
    cmp rax, TOK_GTE
    je .op
    cmp rax, TOK_LTE
    je .op
    mov rax, r12
    add rsp, 0x08
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.op:
    mov r13, rax
    mov r14, rcx
    call p_advance
    call parseTerm
    mov rbx, rax
    mov rax, AST_BINARY
    mov rdx, r13
    mov rcx, r12
    mov r8, rbx
    xor r9d, r9d
    mov r10, r14
    call p_new_node
    mov r12, rax
    jmp .loop

; ---------- parseEquality: comparison ( ('=='|'!=') comparison )* ----------
parseEquality:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 0x08
    call parseComparison
    mov r12, rax
.loop:
    call p_cur
    cmp rax, TOK_EQEQ
    je .op
    cmp rax, TOK_NEQ
    je .op
    mov rax, r12
    add rsp, 0x08
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.op:
    mov r13, rax
    mov r14, rcx
    call p_advance
    call parseComparison
    mov rbx, rax
    mov rax, AST_BINARY
    mov rdx, r13
    mov rcx, r12
    mov r8, rbx
    xor r9d, r9d
    mov r10, r14
    call p_new_node
    mov r12, rax
    jmp .loop

; ---------- parseAnd: equality ( '&&' equality )* ----------
parseAnd:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 0x08
    call parseEquality
    mov r12, rax
.loop:
    call p_cur
    cmp rax, TOK_ANDAND
    jne .done
    mov r13, rax
    mov r14, rcx
    call p_advance
    call parseEquality
    mov rbx, rax
    mov rax, AST_BINARY
    mov rdx, r13
    mov rcx, r12
    mov r8, rbx
    xor r9d, r9d
    mov r10, r14
    call p_new_node
    mov r12, rax
    jmp .loop
.done:
    mov rax, r12
    add rsp, 0x08
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------- parseOr: and ( '||' and )* ----------
parseOr:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 0x08
    call parseAnd
    mov r12, rax
.loop:
    call p_cur
    cmp rax, TOK_OROR
    jne .done
    mov r13, rax
    mov r14, rcx
    call p_advance
    call parseAnd
    mov rbx, rax
    mov rax, AST_BINARY
    mov rdx, r13
    mov rcx, r12
    mov r8, rbx
    xor r9d, r9d
    mov r10, r14
    call p_new_node
    mov r12, rax
    jmp .loop
.done:
    mov rax, r12
    add rsp, 0x08
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------- parseExpression (tail-calls parseOr: no frame shift) ----------
parseExpression:
    jmp parseOr

; ---------- parseIf ----------
parseIf:
    push rbx
    push r12
    push r13
    push r14
    call p_cur
    mov r12, rcx ; line
    mov rax, TOK_IF
    call p_expect
    call parseExpression
    mov r13, rax ; cond
    mov rax, TOK_LBRACE
    call p_expect
    call parseBlockStmts
    mov r14, rax ; then block
    push r14
    push r13
    call p_cur
    cmp rax, TOK_ELSE
    jne .no_else
    call p_advance
    call p_cur
    cmp rax, TOK_IF
    je .else_if
    mov rax, TOK_LBRACE
    call p_expect
    call parseBlockStmts
    mov rbx, rax ; else block
    jmp .if_finish
.else_if:
    call parseIf
    mov rbx, rax ; chained AST_IF
.if_finish:
    pop r13
    pop r14
    mov rax, AST_IF
    xor edx, edx
    mov rcx, r13
    mov r8, r14
    mov r9, rbx
    mov r10, r12
    call p_new_node
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.no_else:
    pop r13
    pop r14
    mov rax, AST_IF
    xor edx, edx
    mov rcx, r13
    mov r8, r14
    xor r9d, r9d
    mov r10, r12
    call p_new_node
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------- parseWhile ----------
parseWhile:
    push rbx
    push r12
    call p_cur
    mov r12, rcx
    mov rax, TOK_WHILE
    call p_expect
    call parseExpression
    mov rbx, rax
    mov rax, TOK_LBRACE
    call p_expect
    call parseBlockStmts
    mov rcx, rbx
    mov r8, rax
    xor r9d, r9d
    mov rax, AST_WHILE
    xor edx, edx
    mov r10, r12
    call p_new_node
    pop r12
    pop rbx
    ret

; ---------- parseReturn ----------
parseReturn:
    push rbx
    call p_cur
    mov rbx, rcx
    mov rax, TOK_RETURN
    call p_expect
    call p_cur
    cmp rax, TOK_SEMI
    je .no_expr
    cmp rax, TOK_RBRACE
    je .no_expr
    cmp rax, TOK_EOF
    je .no_expr
    call parseExpression
    mov rcx, rax
    mov rax, AST_RETURN
    xor edx, edx
    mov r10, rbx
    call p_new_node
    pop rbx
    ret
.no_expr:
    mov rax, AST_RETURN
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    mov r10, rbx
    call p_new_node
    pop rbx
    ret

; ---------- parseImport ----------
parseImport:
    push rbx
    push r12
    call p_cur
    mov r12, rcx
    mov rax, TOK_IMPORT
    call p_expect
    call p_cur
    cmp rax, TOK_STRING
    je .str
    cmp rax, TOK_IDENT
    je .ident
    lea rsi, [p_err_expected]
    call p_error
.str:
    mov rbx, rdx
    call p_advance
    mov rax, AST_IMPORT
    xor edx, edx
    mov rcx, rbx
    xor r8d, r8d
    xor r9d, r9d
    mov r10, r12
    call p_new_node
    pop r12
    pop rbx
    ret
.ident:
    mov rbx, rdx
    call p_advance
    mov rax, AST_IMPORT
    xor edx, edx
    mov rcx, rbx
    xor r8d, r8d
    xor r9d, r9d
    mov r10, r12
    call p_new_node
    pop r12
    pop rbx
    ret

; ---------- parseFnDef ----------
parseFnDef:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 0x20
    call p_cur
    mov r12, rcx ; line
    mov rax, TOK_FN
    call p_expect
    call p_cur
    cmp rax, TOK_IDENT
    jne .err_name
    mov r13, rdx ; name ptr
    call p_advance
    mov rax, TOK_LPAREN
    call p_expect
    ; params
    xor r14d, r14d
    mov rcx, 2048*8
    call p_alloc_data
    mov r15, rax ; params base
    call p_cur
    cmp rax, TOK_RPAREN
    je .no_params
.param_loop:
    call p_cur
    cmp rax, TOK_IDENT
    jne .err_param
    mov [r15 + r14*8], rdx
    inc r14
    call p_advance
    call p_cur
    cmp rax, TOK_COMMA
    jne .param_end
    call p_advance
    jmp .param_loop
.param_end:
.no_params:
    mov rax, TOK_RPAREN
    call p_expect
    mov rax, TOK_LBRACE
    call p_expect
    call parseBlockStmts
    mov rbx, rax ; body
    mov rax, AST_FNDEF
    mov rdx, r14 ; param count
    mov rcx, r13
    mov r8, r15
    mov r9, rbx
    mov r10, r12
    call p_new_node
    add rsp, 0x20
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.err_name:
    lea rsi, [p_err_expected]
    call p_error
.err_param:
    lea rsi, [p_err_expected]
    call p_error

; ---------- parseBlockStmts: assumes '{' already consumed, until '}' ----------
parseBlockStmts:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 0x20
    mov r12, 0
    mov rcx, 2048*8
    call p_alloc_data
    mov r13, rax ; stmts base
    xor r14d, r14d
.loop:
    call p_cur
    cmp rax, TOK_RBRACE
    je .done
    cmp rax, TOK_EOF
    je .done
    cmp rax, TOK_SEMI
    je .semi
    call parseStatement
    mov [r13 + r14*8], rax
    inc r14
    cmp r14, 2048
    jae .oom
    jmp .loop
.semi:
    call p_advance
    jmp .loop
.done:
    mov rax, TOK_RBRACE
    call p_expect
    mov rax, AST_BLOCK
    mov rdx, r14 ; count
    mov rcx, r13
    xor r8d, r8d
    xor r9d, r9d
    mov r10, 0 ; line 0 for synthetic? Use 0
    call p_new_node
    add rsp, 0x20
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.oom:
    lea rsi, [p_err_many_nodes]
    call p_error

; ---------- parseFor ----------
parseFor:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 0x08
    call p_cur
    mov r12, rcx
    mov rax, TOK_FOR
    call p_expect
    call p_cur
    cmp rax, TOK_IDENT
    jne .err_for_ident
    mov r13, rdx
    call p_advance
    mov rax, TOK_IN
    call p_expect
    call parseExpression
    mov r14, rax
    mov rax, TOK_LBRACE
    call p_expect
    call parseBlockStmts
    mov rbx, rax
    mov rax, AST_FOR
    xor edx, edx
    mov rcx, r13
    mov r8, r14
    mov r9, rbx
    mov r10, r12
    call p_new_node
    add rsp, 0x08
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.err_for_ident:
    lea rsi, [p_err_expected]
    call print_cstr
    lea rsi, [p_str_var]
    call print_cstr
    lea rsi, [p_err_expected2]
    call print_cstr
    lea rsi, [p_nl]
    call print_cstr
    mov ecx, 1
    sub rsp, 0x20
    call ExitProcess

; ---------- parseStatement ----------
parseStatement:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 0x08
    call p_cur
    cmp rax, TOK_FN
    je .fn
    cmp rax, TOK_IF
    je .if
    cmp rax, TOK_WHILE
    je .while
    cmp rax, TOK_RETURN
    je .ret
    cmp rax, TOK_IMPORT
    je .imp
    cmp rax, TOK_BREAK
    je .break
    cmp rax, TOK_CONTINUE
    je .continue
    cmp rax, TOK_FOR
    je .for
    cmp rax, TOK_LBRACE
    je .block
    ; assignment? IDENT '=' or '+=' or '-=' or '*=' or '/='
    cmp rax, TOK_IDENT
    jne .expr
    mov rbx, rdx ; name
    mov r12, rcx ; line
    mov rcx, 1
    call p_peek
    cmp rax, TOK_ASSIGN
    je .do_assign_plain
    cmp rax, TOK_PLUSEQ
    je .do_assign_compound
    cmp rax, TOK_MINUSEQ
    je .do_assign_compound
    cmp rax, TOK_STAREQ
    je .do_assign_compound
    cmp rax, TOK_SLASHEQ
    je .do_assign_compound
    jmp .expr

.do_assign_compound:
    mov r13, rax ; r13 = compound token (TOK_PLUSEQ, ...)
    call p_advance ; consume ident
    call p_advance ; consume compound op
    call parseExpression
    mov [p_tmp], rax ; expr E
    ; Create var node 1 (target):
    mov rax, AST_VAR
    xor edx, edx
    mov rcx, rbx
    xor r8d, r8d
    xor r9d, r9d
    mov r10, r12
    call p_new_node
    mov r14, rax ; r14 = target var node
    ; Create var node 2 (LHS of binary op):
    mov rax, AST_VAR
    xor edx, edx
    mov rcx, rbx
    xor r8d, r8d
    xor r9d, r9d
    mov r10, r12
    call p_new_node
    ; Map compound token to binary op token
    mov rdx, TOK_PLUS
    cmp r13, TOK_PLUSEQ
    je .got_binop
    mov rdx, TOK_MINUS
    cmp r13, TOK_MINUSEQ
    je .got_binop
    mov rdx, TOK_STAR
    cmp r13, TOK_STAREQ
    je .got_binop
    mov rdx, TOK_SLASH
.got_binop:
    ; Create binary node: AST_BINARY(op=rdx, left=var_node2, right=E, line=r12)
    mov rcx, rax ; var node 2
    mov r8, [p_tmp] ; expr E
    xor r9d, r9d
    mov r10, r12
    mov rax, AST_BINARY
    call p_new_node
    ; Now create AST_ASSIGN(target=r14, value=rax, line=r12)
    mov r8, rax ; binary node
    mov rcx, r14 ; target var node
    xor edx, edx
    xor r9d, r9d
    mov r10, r12
    mov rax, AST_ASSIGN
    call p_new_node
    mov [p_tmp], rax
    ; optional semi
    call p_cur
    cmp rax, TOK_SEMI
    jne .semi_done_comp
    call p_advance
.semi_done_comp:
    mov rax, [p_tmp]
    jmp .exit

.do_assign_plain:
    call p_advance ; ident
    call p_advance ; =
    call parseExpression
    mov [p_tmp], rax ; save expr
    mov rax, AST_VAR
    xor edx, edx
    mov rcx, rbx
    xor r8d, r8d
    xor r9d, r9d
    mov r10, r12
    call p_new_node
    mov rbx, rax ; var node
    mov rcx, [p_tmp] ; expr
    mov rax, AST_ASSIGN
    xor edx, edx
    mov r8, rcx
    xor r9d, r9d
    mov r10, r12
    mov rcx, rbx
    call p_new_node
    mov [p_tmp], rax
    call p_cur
    cmp rax, TOK_SEMI
    jne .semi_done_plain
    call p_advance
.semi_done_plain:
    mov rax, [p_tmp]
    jmp .exit

.for:
    call parseFor
    jmp .exit
.fn:
    call parseFnDef
    jmp .exit
.if:
    call parseIf
    jmp .exit
.while:
    call parseWhile
    jmp .exit
.ret:
    call parseReturn
    mov [p_tmp], rax
    ; optional ;
    call p_cur
    cmp rax, TOK_SEMI
    jne .ret_done
    call p_advance
.ret_done:
    mov rax, [p_tmp]
    jmp .exit
.imp:
    call parseImport
    mov [p_tmp], rax
    call p_cur
    cmp rax, TOK_SEMI
    jne .imp_done
    call p_advance
.imp_done:
    mov rax, [p_tmp]
    jmp .exit
.break:
    call p_cur
    mov r12, rcx
    call p_advance
    call p_cur
    cmp rax, TOK_SEMI
    jne .break_node
    call p_advance
.break_node:
    mov rax, AST_BREAK
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    mov r10, r12
    call p_new_node
    jmp .exit
.continue:
    call p_cur
    mov r12, rcx
    call p_advance
    call p_cur
    cmp rax, TOK_SEMI
    jne .continue_node
    call p_advance
.continue_node:
    mov rax, AST_CONTINUE
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    xor r9d, r9d
    mov r10, r12
    call p_new_node
    jmp .exit
.block:
    ; '{' already not consumed? parseBlockStmts expects after '{'
    call p_advance
    ; we consumed '{', need to parse until '}' but parseBlockStmts expects to consume '}' itself
    ; We already advanced past '{', so call inner helper that parses stmts without expecting '{'
    ; Instead we can call parseBlockStmts that expects '{' + '}'? Our parseBlockStmts currently expects only '}'.
    ; We advanced, so just parse stmts until '}'
    push rax
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 0x08
    mov rcx, 2048*8
    call p_alloc_data
    mov r13, rax
    xor r14d, r14d
.bl_loop:
    call p_cur
    cmp rax, TOK_RBRACE
    je .bl_done
    cmp rax, TOK_EOF
    je .bl_done
    cmp rax, TOK_SEMI
    je .bl_semi
    call parseStatement
    mov [r13 + r14*8], rax
    inc r14
    jmp .bl_loop
.bl_semi:
    call p_advance
    jmp .bl_loop
.bl_done:
    mov rax, TOK_RBRACE
    call p_expect
    mov rax, AST_BLOCK
    mov rdx, r14
    mov rcx, r13
    xor r8d, r8d
    xor r9d, r9d
    xor r10d, r10d
    call p_new_node
    mov rbx, rax
    add rsp, 0x08
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rax ; saved outer? Actually we pushed rax at .block start as temp, need to pop? We pushed rax as dummy to save outer rax? Let's save correctly.
    ; The outer parseStatement pushes are still on stack, so just set rax=rbx and jmp to exit
    mov rax, rbx
    jmp .exit
.expr:
    call parseExpression
    mov r12, rax
    mov rbx, [r12+40]
    call p_cur
    cmp rax, TOK_SEMI
    jne .no_semi
    call p_advance
.no_semi:
    mov rax, AST_EXPRSTMT
    xor edx, edx
    mov rcx, r12
    xor r8d, r8d
    xor r9d, r9d
    mov r10, rbx
    call p_new_node
.exit:
    add rsp, 0x08
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------- parseProgram -> RAX root ----------
parseProgram:
    push rbx
    push r12
    push r13
    sub rsp, 0x20
    mov rcx, 2048*8
    call p_alloc_data
    mov r12, rax ; stmts base
    xor r13d, r13d
.loop:
    call p_cur
    cmp rax, TOK_EOF
    je .done
    cmp rax, TOK_SEMI
    je .semi
    call parseStatement
    mov [r12 + r13*8], rax
    inc r13
    jmp .loop
.semi:
    call p_advance
    jmp .loop
.done:
    mov rax, AST_PROGRAM
    mov rdx, r13
    mov rcx, r12
    xor r8d, r8d
    xor r9d, r9d
    xor r10d, r10d
    call p_new_node
    mov [parser_root], rax
    add rsp, 0x20
    pop r13
    pop r12
    pop rbx
    ret

; ---------- parser_run() -> RAX root ----------
parser_run:
    push rbx
    call parser_init
    call parseProgram
    mov rax, [parser_root]
    pop rbx
    ret

; ---------- AST dump helpers ----------
p_print_indent:
    push rbx
    mov rbx, rcx
.loop:
    test rbx, rbx
    jz .done
    push rbx
    lea rsi, [p_indent_str]
    call print_cstr
    pop rbx
    dec rbx
    jmp .loop
.done:
    pop rbx
    ret

; ---------- p_dump_node(RAX=node, RCX=indent) ----------
p_dump_node:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 0x28
    mov r12, rax
    mov r13, rcx
    mov rcx, r13
    call p_print_indent
    mov rax, [r12]
    cmp rax, AST_PROGRAM
    je .program
    cmp rax, AST_BLOCK
    je .block
    cmp rax, AST_ASSIGN
    je .assign
    cmp rax, AST_VAR
    je .var
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
    cmp rax, AST_BINARY
    je .binary
    cmp rax, AST_UNARY
    je .unary
    cmp rax, AST_IF
    je .if
    cmp rax, AST_WHILE
    je .while
    cmp rax, AST_FNDEF
    je .fndef
    cmp rax, AST_CALL
    je .call
    cmp rax, AST_RETURN
    je .return
    cmp rax, AST_ARRAY
    je .array
    cmp rax, AST_OBJECT
    je .object
    cmp rax, AST_INDEX
    je .index
    cmp rax, AST_MEMBER
    je .member
    cmp rax, AST_IMPORT
    je .import
    cmp rax, AST_EXPRSTMT
    je .exprstmt
    cmp rax, AST_BREAK
    je .dump_break
    cmp rax, AST_CONTINUE
    je .dump_continue
    cmp rax, AST_FOR
    je .dump_for
    lea rsi, [p_str_program]
    jmp .name_done
.program: lea rsi, [p_str_program]
    jmp .name_done
.block:   lea rsi, [p_str_block]
    jmp .name_done
.assign:  lea rsi, [p_str_assign]
    jmp .name_done
.var:     lea rsi, [p_str_var]
    jmp .name_done
.int:     lea rsi, [p_str_int]
    jmp .name_done
.float:   lea rsi, [p_str_float]
    jmp .name_done
.string:  lea rsi, [p_str_string]
    jmp .name_done
.bool:    lea rsi, [p_str_bool]
    jmp .name_done
.null:    lea rsi, [p_str_null]
    jmp .name_done
.binary:  lea rsi, [p_str_binary]
    jmp .name_done
.unary:   lea rsi, [p_str_unary]
    jmp .name_done
.if:      lea rsi, [p_str_if]
    jmp .name_done
.while:   lea rsi, [p_str_while]
    jmp .name_done
.fndef:   lea rsi, [p_str_fndef]
    jmp .name_done
.call:    lea rsi, [p_str_call]
    jmp .name_done
.return:  lea rsi, [p_str_return]
    jmp .name_done
.array:   lea rsi, [p_str_array]
    jmp .name_done
.object:  lea rsi, [p_str_object]
    jmp .name_done
.index:   lea rsi, [p_str_index]
    jmp .name_done
.member:  lea rsi, [p_str_member]
    jmp .name_done
.import:  lea rsi, [p_str_import]
    jmp .name_done
.exprstmt:lea rsi, [p_str_exprstmt]
    jmp .name_done
.dump_break:
    lea rsi, [p_str_break]
    jmp .name_done
.dump_continue:
    lea rsi, [p_str_continue]
    jmp .name_done
.dump_for:
    lea rsi, [p_str_for]
.name_done:
    call print_cstr
    ; extra info
    mov rax, [r12]
    cmp rax, AST_VAR
    je .var_extra
    cmp rax, AST_INT
    je .int_extra
    cmp rax, AST_FLOAT
    je .float_extra
    cmp rax, AST_STRING
    je .str_extra
    cmp rax, AST_BOOL
    je .bool_extra
    cmp rax, AST_BINARY
    je .bin_extra
    cmp rax, AST_UNARY
    je .un_extra
    cmp rax, AST_FNDEF
    je .fn_extra
    cmp rax, AST_CALL
    je .call_extra
    cmp rax, AST_ARRAY
    je .arr_extra
    cmp rax, AST_OBJECT
    je .obj_extra
    cmp rax, AST_MEMBER
    je .mem_extra
    cmp rax, AST_IMPORT
    je .imp_extra
    jmp .children
.var_extra:
    lea rsi, [p_colon_sp]
    call print_cstr
    mov rsi, [r12+16]
    call print_cstr
    jmp .children
.int_extra:
    lea rsi, [p_colon_sp]
    call print_cstr
    mov rax, [r12+16]
    call print_u64
    jmp .children
.float_extra:
    lea rsi, [p_colon_sp]
    call print_cstr
    mov rax, [r12+16]
    call print_hex_u64
    jmp .children
.str_extra:
    lea rsi, [p_colon_sp]
    call print_cstr
    lea rsi, [tn_q]
    call print_cstr
    mov rsi, [r12+16]
    call print_cstr
    lea rsi, [tn_q]
    call print_cstr
    jmp .children
.bool_extra:
    lea rsi, [p_colon_sp]
    call print_cstr
    mov rax, [r12+8]
    test rax, rax
    jz .bool_f
    lea rsi, [tn_true]
    call print_cstr
    jmp .children
.bool_f:
    lea rsi, [tn_false]
    call print_cstr
    jmp .children
.bin_extra:
    lea rsi, [p_colon_sp]
    call print_cstr
    mov rax, [r12+8]
    call token_kind_name
    call print_cstr
    jmp .children
.un_extra:
    lea rsi, [p_colon_sp]
    call print_cstr
    mov rax, [r12+8]
    call token_kind_name
    call print_cstr
    jmp .children
.fn_extra:
    lea rsi, [p_colon_sp]
    call print_cstr
    mov rsi, [r12+16]
    call print_cstr
    lea rsi, [p_lparen]
    call print_cstr
    mov rax, [r12+8]
    call print_u64
    lea rsi, [p_rparen]
    call print_cstr
    jmp .children
.call_extra:
    lea rsi, [p_colon_sp]
    call print_cstr
    mov rax, [r12+8]
    call print_u64
    lea rsi, [p_lparen]
    call print_cstr
    lea rsi, [p_rparen]
    call print_cstr
    jmp .children
.arr_extra:
    lea rsi, [p_colon_sp]
    call print_cstr
    mov rax, [r12+8]
    call print_u64
    jmp .children
.obj_extra:
    lea rsi, [p_colon_sp]
    call print_cstr
    mov rax, [r12+8]
    call print_u64
    jmp .children
.mem_extra:
    lea rsi, [p_colon_sp]
    call print_cstr
    mov rsi, [r12+24]
    call print_cstr
    jmp .children
.imp_extra:
    lea rsi, [p_colon_sp]
    call print_cstr
    mov rsi, [r12+16]
    call print_cstr
    jmp .children
.children:
    lea rsi, [p_nl]
    call print_cstr
    ; children dumping omitted for Phase1 minimal; just return
    add rsp, 0x28
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------- parser_dump ----------
parser_dump:
    push rbx
    mov rax, [parser_root]
    test rax, rax
    jz .none
    xor ecx, ecx
    call p_dump_node
    lea rsi, [p_nl]
    call print_cstr
    pop rbx
    ret
.none:
    lea rsi, [p_err_eof]
    call print_cstr
    pop rbx
    ret
