# ShitCam Language Reference (v1)

## Program structure

A program is a sequence of statements. Newlines and `;` separate statements.
A file should use the `.sc` extension and is run with `shitcam file.sc`.

## Comments

```
// line comment
# line comment
```

## Values and dynamic typing

No type declarations. A variable takes the type of its value and may be
rebound to another type at any time:

```
x = 10        # int (64-bit signed)
x = "hello"   # now string
pi = 3.14     # float (64-bit IEEE-754)
active = true # bool: true | false
nothing = null
```

Types: `null`, `bool`, `int`, `float`, `string`, `array`, `object`, `function`.

## Variables

```
name = "Ruby"
count = count + 1
```

Assignment rebinds the nearest existing binding (innermost scope first),
otherwise defines the variable in the current scope. Function parameters
always create fresh shadowing slots, so recursion works:

```
fn fib(n) {
if n <= 1 {
return n
}
return fib(n - 1) + fib(n - 2)
}
```

Note (v1): plain assignments inside a function body currently rebind
globals — use uniquely named locals (or parameters) when a function calls
other functions that use the same variable names.

## Functions

```
fn add(a, b) {
return a + b
}
result = add(10, 20)
```

- Declared with `fn name(params) { body }`.
- `return expr` or bare `return` (returns `null`); falling off the end
  returns `null`.
- Call by value; arguments are evaluated left to right.

## Conditionals and loops

```
if x > 10 {
print("large")
} else if x == 10 {
print("equal")
} else {
print("small")
}

while x < 10 {
x += 1          # compound assignment: +=, -=, *=, /=
if x == 5 {
  break       # early loop exit
}
if x % 2 == 0 {
  continue    # skip to next iteration
}
}

items = [10, 20, 30]
for item in items {
if item == 20 { continue }
println(item)
}
```

Truthiness: `false` and `null` are falsy, `0`/`""` are falsy, everything
else is truthy. `&&` and `||` return booleans.

## Operators (precedence, high to low)

1. `()` call, `[]` index, `.` member
2. unary `!` `-`
3. `*` `/` `%`
4. `+` `-` (`+` also concatenates when either side is a string)
5. `> < >= <=`
6. `== !=`
7. `&&`
8. `||`
9. Assignment: `=`, `+=`, `-=`, `*=`, `/=`

`/` and `%` on zero raise `Runtime error: division by zero`.
Int/float mix promotes to float. `+` with a string converts the other side
(int → decimal, float → decimal string, bool → `true`/`false`,
null → `null`, array → `[array]`, object → `{object}`).
`==` and `!=` on two strings compare contents; other compound values
compare by identity. Mixed-type `==` is always false.

## Strings

```
s = "Hello\n"
print(length(s))          # 6
print(lower("HeLLo"))     # hello
print(upper("hey"))       # HEY
print(contains(s, "ell")) # true
print(substring(s, 1, 3)) # ell
```

Escapes: `\" \\ \n \t \r`. `substring(s, start, len)` clamps to the string;
`substring(s, start)` takes the rest.

## Arrays

```
a = [1, 2, 3]
print(a[0])       # 1 (0-based; out of bounds -> null)
push(a, 4)        # append (grows); returns the array
print(pop(a))     # 4 (removes last; empty -> null)
print(length(a))  # 3
```

Literals evaluate elements left to right into a fresh heap array.

## Objects

```
user = { name: "Ruby", age: 18 }
print(user.name)  # Ruby
print(user.age)   # 18
```

Keys are identifiers or strings. Missing keys read as `null`.

## Imports

```
import math            # standard library module (abs/min/max/sqrt/...)
import "utils.sc"      # local file, relative to working directory
import "lib/helpers.sc"
```

- Each file executes at most once (import cache).
- Circular imports are an error: `Error: circular import detected for '...'`.
- Unknown bare names are an error suggesting stdlib-or-path.
- Missing files report `Error: cannot open file '...'`.

## Standard library

| fn | notes |
|---|---|
| `print(...)` | values separated by space, no trailing newline |
| `println(...)` | like print + newline |
| `input(...)` | optional prompt, reads one line (CR/LF stripped); works for console and piped/file input |
| `length(x)` | string chars / array items (else 0) |
| `lower(s)` `upper(s)` | new strings, else null |
| `contains(h, n)` | bool, string args |
| `substring(s, i[, n])` | clamped, else null |
| `push(a, v)` | returns array (also writes back `a` if variable) |
| `pop(a)` | last item or null |
| `abs(x)` `min(a,b)` `max(a,b)` | ints; min/max accept floats |
| `sqrt(x)` | float result (`nan` for negatives) |
| `read_file(p)` | whole file as string (missing file is fatal) |
| `write_file(p, d)` | bytes written, or null on failure |
| `file_exists(p)` | 1 if file/dir exists, 0 otherwise |
| `delete_file(p)` | 1 on success, 0 on failure |
| `make_dir(p)` | 1 on success, 0 on failure |
| `get_env(name)` | value of environment variable as string, or null |
| `set_env(name, val)` | sets environment variable in process, 1 or 0 |
| `system(cmd)` | runs command synchronously via CreateProcessA, returns exit code |
| `set_color(code)` | sets console text attribute (0..15 colors) |
| `clear_screen()` | resets console cursor position to top-left (0, 0) |
| `key_pressed([key])` | non-blocking key check (VK code or char, default: Space/Up/W); returns 1 if pressed, 0 otherwise |
| `set_clipboard(text)` | copies text string to Windows clipboard |
| `get_clipboard()` | reads text string from Windows clipboard |
| `http_get(url)` | sends HTTP/HTTPS GET request via WinINet, returns body string or null |
| `time()` | milliseconds since system boot (GetTickCount64) |
| `sleep(ms)` | pauses execution for ms milliseconds |
| `random([min, max])` | pseudo-random integer; range min..max or 0..limit |
| `beep([freq, ms])` | emits sound via PC speaker (Win32 Beep) |
| `alert([title, msg])` | displays Win32 MessageBox alert window |
| `args` | global array of command-line argument strings |

Wrong argument counts report `Runtime error: wrong number of arguments`.

## Errors

```
Error: undefined variable 'x'
Error: division by zero
Error: unterminated string literal
File: prog.sc
Line: 3
Column: 12
x = (1 + 2
        ^
```

Lex/parse errors show file, line, column, source line and caret.
Runtime errors name the problem. The REPL never dies on errors.

## Compiler subset

`shitcam build` accepts: int/string literals and variables, int arithmetic (+ - * / %)
and compound assignment (+= -= *= /=), comparisons, `print`/`println`,
`if`/`else if`/`else`, `while` loops with `break` and `continue`, assignment.
Rejected with a clear `Compile error at line N: ... (use interpreter ...)`:
floats, bools, null, arrays, objects, functions, imports, string `+` with
non-strings (use explicit conversion via interpreter), use-before-define.
Compiled booleans print as `1`/`0` (interpreter prints `true`/`false`).
