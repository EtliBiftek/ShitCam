# ShitCam

ShitCam is a simple, lightweight, and dynamically typed programming language for Windows x64.

It features an interpreter, an interactive REPL, and a native compiler, built directly in x86-64 NASM assembly without any C runtime dependencies.

---

## Features

- **Simple Syntax:** Clean, easy-to-read syntax with curly braces `{}`.
- **Dynamic Typing:** Numbers (`int`, `float`), `string`, `bool`, `null`, `array`, and `object`.
- **Three Modes:**
  - **Interpreter:** Run scripts directly (`shitcam file.sc`).
  - **REPL:** Interactive shell (`shitcam repl`).
  - **Native Compiler:** Compile directly to standalone `.exe` (`shitcam build file.sc`).
- **Standard Library:** Built-in I/O, strings, math, file system, networking, and Windows clipboard/dialogs.

---

## Quick Start

### Requirements
- Windows 10 / 11 (x64)
- Python 3.8+ (for the build script)
- Visual Studio Build Tools or VS Community (`link.exe` and Windows SDK)

### Build & Run

```bat
# 1. Build the project
python tools\build.py

# 2. Run a script
build\shitcam.exe hello.sc
```

### Example (`hello.sc`)

```sc
// Variables & Dynamic Types
name = "World"
count = 3

// Functions
fn greet(target) {
    return "Hello, " + target + "!"
}

// Loops & Conditionals
for i in [1, 2, 3] {
    if i == count {
        println(greet(name))
    }
}
```

---

## Usage

| Action | Command |
| :--- | :--- |
| **Run script** | `shitcam file.sc` |
| **Interactive REPL** | `shitcam repl` |
| **Compile to EXE** | `shitcam build file.sc` |
| **Check Version** | `shitcam --version` |

---

## Installation

Add `shitcam` to your system `PATH`:

```bat
install.bat      :: Copies binaries and adds ShitCam to user PATH
uninstall.bat    :: Removes ShitCam from PATH and deletes installed files
```

---

## Documentation

- **[Language Guide](docs/LANGUAGE.md)**: Full syntax reference, types, standard library functions, and modules.
- **[Architecture](docs/ARCHITECTURE.md)**: Details on the NASM x64 assembly architecture, compiler internals, and memory layout.
- **VS Code Extension**: Syntax highlighting is available in `editors/vscode/`.
