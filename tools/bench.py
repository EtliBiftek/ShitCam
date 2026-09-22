#!/usr/bin/env python3
"""ShitCam benchmarks: interpreter vs compiled native exe (where supported).
No cross-language speed claims - just ShitCam vs ShitCam numbers."""
import os, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXE = os.path.join(ROOT, "build", "shitcam.exe")
TMP = os.path.join(ROOT, "build", "bench_tmp")
os.makedirs(TMP, exist_ok=True)

CASES = {
    # name: (source, compilable)
    "loop": ("i = 0\nwhile i < 200000 {\ni = i + 1\n}\nprint(i)",
             True),
    "arith": ("x = 0\ni = 0\nwhile i < 50000 {\nx = x + i * 2 - i / 3\ni = i + 1\n}\nprint(x)",
              True),
    "fib15": ("fn fib(n) {\nif n <= 1 {\nreturn n\n}\nreturn fib(n - 1) + fib(n - 2)\n}\nprint(fib(15))",
              False),
    "strcat": ('s = ""\ni = 0\nwhile i < 2000 {\ns = s + "ab"\ni = i + 1\n}\nprint(length(s))',
               False),
    "arriter": ("a = []\ni = 0\nwhile i < 5000 {\npush(a, i)\ni = i + 1\n}\ns = 0\nj = 0\nwhile j < length(a) {\ns = s + a[j]\nj = j + 1\n}\nprint(s)",
                False),
}

def run_interp(path):
    t = time.perf_counter()
    p = subprocess.run([EXE, path], capture_output=True, cwd=ROOT, timeout=300)
    dt = time.perf_counter() - t
    return p.returncode, p.stdout.decode("utf-8", "replace"), dt

def build(path):
    p = subprocess.run([EXE, "build", path], capture_output=True, cwd=ROOT,
                       timeout=300)
    if p.returncode != 0:
        return None
    stem = os.path.splitext(os.path.basename(path))[0]
    return os.path.join(os.path.dirname(path), stem + ".exe")

def run_exe(path):
    t = time.perf_counter()
    p = subprocess.run([path], capture_output=True, cwd=ROOT, timeout=300)
    dt = time.perf_counter() - t
    return p.returncode, p.stdout.decode("utf-8", "replace"), dt

def main():
    print(f"{'bench':<8}{'interp(s)':>10}{'interp out':>14}"
          f"{'native(s)':>10}{'native out':>14}{'match':>8}")
    for name, (src, comp) in CASES.items():
        path = os.path.join(TMP, name + ".sc")
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(src)
        irc, iout, idt = run_interp(path)
        nout, ndt, match = "-", "-", "-"
        if comp and irc == 0:
            exe = build(path)
            if exe and os.path.isfile(exe):
                nrc, nout, ndt = run_exe(exe)
                nout = nout.strip()
                iouts = iout.strip().replace("true", "1").replace("false", "0")
                match = "YES" if (nrc == 0 and nout == iouts) else "NO"
                ndt = f"{ndt:.3f}"
                try:
                    os.remove(exe)
                except OSError:
                    pass
            else:
                nout = "BUILDFAIL"
        print(f"{name:<8}{idt:>10.3f}{iout.strip()!r:>14}{str(ndt):>10}"
              f"{str(nout):>14}{match:>8}")
        if irc != 0:
            print(f"  INTERP FAILED rc={irc}: {iout!r}")
            sys.exit(1)

if __name__ == "__main__":
    main()
