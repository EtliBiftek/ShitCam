; ShitCam - shared constants, value tags, AST node kinds, token kinds
; Single source of truth for magic numbers. Included by src/*.asm
; Windows x64, NASM syntax.

; ---- Version ----
%define SHITCAM_VER_MAJOR 0
%define SHITCAM_VER_MINOR 1
%define SHITCAM_VER_PATCH 0

; ---- Limits ----
%define SC_MAX_ARGS        64
%define SC_MAX_LINE        4096
%define SC_MAX_FILE        16777216   ; 16 MB max source file
%define SC_MAX_TOKENS      65536
%define SC_MAX_AST_NODES   65536
%define SC_MAX_VARS        4096
%define SC_MAX_SCOPE_DEPTH 256
%define SC_MAX_IMPORTS     64
%define SC_MAX_PATH        1024
%define SC_REPL_TRANS_MAX 1048576
%define SC_REPL_TMP       "shitcam_repl_tmp.sc", 0
%define INFINITE          0xFFFFFFFF

; ---- Value type tags (runtime.asm / interp.asm) ----
; Value layout (16 bytes): [u64 type][u64 payload]
; int/float payload inline; string/array/object/fn payload = heap pointer.
%define SC_T_NULL    0
%define SC_T_BOOL    1
%define SC_T_INT     2
%define SC_T_FLOAT   3
%define SC_T_STRING  4
%define SC_T_ARRAY   5
%define SC_T_OBJECT  6
%define SC_T_FUNC    7

; ---- Heap object header (runtime.asm) ----
; [u64 type][u64 len][u64 cap_or_extra][data...]
%define SC_OBJ_HDR_SIZE 24

; ---- Token kinds (lexer.asm) ----
%define TOK_EOF        0
%define TOK_INT        1
%define TOK_FLOAT      2
%define TOK_STRING     3
%define TOK_IDENT      4
%define TOK_TRUE       5
%define TOK_FALSE      6
%define TOK_NULL       7
%define TOK_FN         8
%define TOK_IF         9
%define TOK_ELSE       10
%define TOK_WHILE      11
%define TOK_RETURN     12
%define TOK_IMPORT     13
%define TOK_BREAK      14
%define TOK_CONTINUE   15
%define TOK_FOR        16
%define TOK_IN         17
%define TOK_PLUS       20
%define TOK_MINUS      21
%define TOK_STAR       22
%define TOK_SLASH      23
%define TOK_PERCENT    24
%define TOK_EQEQ       25
%define TOK_NEQ        26
%define TOK_GT         27
%define TOK_LT         28
%define TOK_GTE        29
%define TOK_LTE        30
%define TOK_ANDAND     31
%define TOK_OROR       32
%define TOK_BANG       33
%define TOK_ASSIGN     34
%define TOK_LPAREN     35
%define TOK_RPAREN     36
%define TOK_LBRACE     37
%define TOK_RBRACE     38
%define TOK_LBRACKET   39
%define TOK_RBRACKET   40
%define TOK_COMMA      41
%define TOK_COLON      42
%define TOK_DOT        43
%define TOK_SEMI       44
%define TOK_PLUSEQ     45
%define TOK_MINUSEQ    46
%define TOK_STAREQ     47
%define TOK_SLASHEQ    48
; Token record (16 bytes): [u64 kind][u64 payload]
; payload: int value / float bits / string heap ptr / ident string ptr / 0

; ---- AST node kinds (ast.asm / parser.asm) ----
%define AST_PROGRAM    1
%define AST_BLOCK      2
%define AST_ASSIGN     3
%define AST_VAR        4
%define AST_INT        5
%define AST_FLOAT      6
%define AST_STRING     7
%define AST_BOOL       8
%define AST_NULL       9
%define AST_BINARY     10
%define AST_UNARY      11
%define AST_IF         12
%define AST_WHILE      13
%define AST_FNDEF      14
%define AST_CALL       15
%define AST_RETURN     16
%define AST_ARRAY      17
%define AST_OBJECT     18
%define AST_INDEX      19
%define AST_MEMBER     20
%define AST_IMPORT     21
%define AST_EXPRSTMT   22
%define AST_BREAK      23
%define AST_CONTINUE   24
%define AST_FOR        25
; AST node record (48 bytes):
; [u64 kind][u64 op_or_extra][u64 left/child0][u64 mid/child1][u64 right/child2][u64 line]
; Positions: line kept per node; column in `extra` high 32 bits where needed.

; ---- Windows constants ----
%define STD_OUTPUT_HANDLE -11
%define STD_INPUT_HANDLE  -10
%define GENERIC_READ      0x80000000
%define GENERIC_WRITE     0x40000000
%define FILE_SHARE_READ   1
%define OPEN_EXISTING     3
%define CREATE_ALWAYS     2
%define FILE_ATTRIBUTE_NORMAL 0x80
%define INVALID_HANDLE_VALUE -1
%define MEM_COMMIT        0x1000
%define MEM_RESERVE       0x2000
%define PAGE_READWRITE    0x04
