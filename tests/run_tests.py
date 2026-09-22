#!/usr/bin/env python3
"""ShitCam regression + parity tests. Exits nonzero on first failure."""
import os, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = os.path.join(ROOT, "build", "shitcam.exe")
TMP = os.path.join(ROOT, "build", "test_tmp")
PASS = 0

def run(args, inp=None, cwd=None):
    if isinstance(inp, str):
        inp = inp.encode("utf-8")
    p = subprocess.run([EXE] + args, input=inp, capture_output=True,
                       cwd=cwd or ROOT, timeout=120)
    return p.returncode, p.stdout.decode("utf-8", "replace")

def check(name, cond, detail=""):
    global PASS
    if cond:
        PASS += 1
        print(f"ok: {name}")
    else:
        print(f"FAIL: {name} {detail}")
        sys.exit(1)

def main():
    if not os.path.isfile(EXE):
        sys.exit("build/shitcam.exe missing; run tools/build.py first")
    os.makedirs(TMP, exist_ok=True)

    # --- CLI ---
    rc, out = run(["--version"])
    check("cli-version", rc == 0 and "ShitCam 0.1.0" in out, repr(out))
    rc, out = run(["--help"])
    check("cli-help", rc == 0 and "shitcam" in out.lower(), repr(out))
    rc, out = run(["lextest", "tests/fixtures/hello.sc"])
    check("cli-lextest", rc == 0 and 'STRING "Hello World"' in out, repr(out))
    rc, out = run(["parsetest", "tests/fixtures/hello.sc"])
    check("cli-parsetest", rc == 0 and "Program" in out, repr(out))
    rc, out = run(["run", "nope_missing_xyz.sc"])
    check("cli-missing-file", rc != 0 and "cannot open file" in out, repr(out))

    # --- interpreter: fixtures with exact expected output ---
    cases = {
        "tests/fixtures/hello.sc": "Hello World",
        "tests/fixtures/variables.sc": "10Rubytruenull3.140000hello",
        "tests/fixtures/functions.sc": "30Hello Ruby",
        "tests/fixtures/conditions.sc": "largefifteennot ten",
        "tests/fixtures/loops.sc": "545",
        "tests/fixtures/arrays.sc": "[1, 2, 3]13[1, 2, 3, 4]4[1, 2, 3]",
        "tests/fixtures/objects.sc": "{name: Ruby, age: 18}Ruby18",
        "tests/fixtures/strings.sc": "Hello World11hello worldHELLO WORLDtrueWorldabc",
        "tests/fixtures/fibonacci.sc": "55610",
        "tests/fixtures/imports.sc": "42ShitCam utils7.000000",
        "tests/fixtures/break_continue.sc": "525",
        "tests/fixtures/stdlib_os.sc": "time_okrand_okrand_ok",
        "tests/fixtures/compound_ops.sc": "24",
        "tests/fixtures/else_if.sc": "B",
        "tests/fixtures/for_in.sc": "40",
        "tests/fixtures/fs_env.sc": "110hello_env",
        "tests/fixtures/clipboard.sc": "ShitCamClipVal",
        "tests/fixtures/terminal_color.sc": "colored",
    }
    for f, exp in cases.items():
        rc, out = run([f])
        check(f"interp-{f}", rc == 0 and out == exp, f"rc={rc} out={out!r} exp={exp!r}")
    rc, out = run([os.path.join(ROOT, "tests/fixtures/file_io.sc")], cwd=TMP)
    check("interp-file_io", rc == 0 and out == "Hello from ShitCam",
          f"rc={rc} out={out!r}")
    check("interp-file_io-artifact",
          os.path.isfile(os.path.join(TMP, "hello_out.txt")))
    rc, out = run(["tests/fixtures/args_demo.sc", "alpha", "beta"])
    check("interp-args", rc == 0 and out == "2alphabeta", f"rc={rc} out={out!r}")

    # --- runtime errors (must fail cleanly, never crash) ---
    err_cases = [
        ("x", "undefined variable"),
        ('print(1/0)', "division by zero"),
        ('print("oops', "unterminated string"),
        ("x = (1 + 2", "expected"),
        ('import nosuchmod', "unknown module"),
    ]
    for i, (src, frag) in enumerate(err_cases):
        p = os.path.join(TMP, f"err{i}.sc")
        with open(p, "w", encoding="utf-8", newline="") as f:
            f.write(src)
        rc, out = run([p])
        check(f"err-{i}", rc != 0 and frag in out, f"rc={rc} out={out!r}")
    # circular import
    with open(os.path.join(TMP, "c1.sc"), "w") as f:
        f.write('import "c2.sc"')
    with open(os.path.join(TMP, "c2.sc"), "w") as f:
        f.write('import "c1.sc"')
    rc, out = run([os.path.join(TMP, "c1.sc")], cwd=TMP)
    check("err-circular", rc != 0 and "circular import" in out, repr(out))

    # --- REPL (piped): persistence, echo, error survival, multiline, exit ---
    repl_in = ("x = 10\r\nprint(x)\r\nx + 20\r\nbad syntax here(((\r\n"
               "print(x + 1)\r\nfn add(a, b) {\r\nreturn a + b\r\n}\r\n"
               "print(add(3, 4))\r\nexit\r\n")
    rc, out = run(["repl"], inp=repl_in)
    check("repl-exit0", rc == 0, f"rc={rc}")
    for frag in ["10", "30", "unexpected token", "11", "7"]:
        check(f"repl-has-{frag}", frag in out, repr(out))

    # --- calculator app (piped menu session) ---
    calc_in = ("1\n3 + 4 * (2 - 1)\n"
               "1\n(2 + 3) * (10 - 4) / 3\n"
               "1\n2.5 + 0.5\n"
               "1\n1 / 0\n"
               "1\n2 * (3 + 4\n"
               "2\n12\n*\n5\n"
               "2\n7\n/\n0\n"
               "3\nsqrt\n16\n"
               "3\nsqrt\n-9\n"
               "3\nabs\n-42\n"
               "3\nmod\n7.5\n2\n"
               "3\nmin\n3\n7\n"
               "3\nmax\n3\n7\n"
               "9\n"
               "q\n")
    rc, out = run(["tests/fixtures/calculator.sc"], inp=calc_in)
    check("calc-exit0", rc == 0, f"rc={rc} out={out!r}")
    for frag in ["7", "10", "3", "invalid expression",
                 "60", "division by zero", "4", "sqrt of negative",
                 "42", "1.5", "3", "7", "unknown choice", "bye"]:
        check(f"calc-has-{frag}", frag in out, repr(out))

    # --- compiler: subset parity (interp vs native exe) ---
    parity = [
        ("tests/fixtures/hello.sc", None),
        ("tests/fixtures/conditions.sc", None),
        ("tests/fixtures/loops.sc", None),
        ("tests/fixtures/break_continue.sc", None),
        ("tests/fixtures/compound_ops.sc", None),
        ("tests/fixtures/else_if.sc", None),
        ("tests/fixtures/functions.sc", "SKIP"),  # fn unsupported in compiler v1
    ]
    for f, _ in parity:
        if _ == "SKIP":
            rc, out = run(["build", f])
            check(f"cc-reject-{f}", rc != 0 and "not supported" in out,
                  f"rc={rc} out={out!r}")
            continue
        rc, out = run([f])
        check(f"cc-interp-{f}", rc == 0)
        iexp = out.replace("true", "1").replace("false", "0")
        rc, out = run(["build", f])
        check(f"cc-build-{f}", rc == 0, repr(out))
        stem = os.path.splitext(os.path.basename(f))[0]
        exedir = os.path.dirname(os.path.join(ROOT, f))
        exe = os.path.join(exedir, stem + ".exe")
        try:
            p = subprocess.run([exe], capture_output=True, cwd=ROOT, timeout=120)
            cout = p.stdout.decode("utf-8", "replace")
            check(f"cc-run-{f}", p.returncode == 0 and cout == iexp,
                  f"rc={p.returncode} out={cout!r} exp={iexp!r}")
        finally:
            for ext in (".exe",):
                try:
                    os.remove(os.path.join(exedir, stem + ext))
                except OSError:
                    pass
    # int arithmetic parity (extra file in TMP)
    arith = ("a = 20\nb = 6\nprint(a + b)\nprint(a - b)\nprint(a * b)\n"
             "print(a / b)\nprint(a % b)\n")
    ap = os.path.join(TMP, "arith.sc")
    with open(ap, "w", encoding="utf-8", newline="") as f:
        f.write(arith)
    rc, iout = run([ap])
    check("cc-arith-interp", rc == 0 and iout == "261412032", repr(iout))
    rc, out = run(["build", ap])
    check("cc-arith-build", rc == 0, repr(out))
    p = subprocess.run([os.path.join(TMP, "arith.exe")], capture_output=True,
                       cwd=ROOT, timeout=60)
    cout = p.stdout.decode("utf-8", "replace")
    check("cc-arith-run", p.returncode == 0 and cout == "261412032", repr(cout))

    print(f"\nALL {PASS} TESTS PASSED")

if __name__ == "__main__":
    main()
