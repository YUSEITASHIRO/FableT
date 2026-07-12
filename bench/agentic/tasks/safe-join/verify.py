import os
import sys

sys.path.insert(0, ".")
fails = []

try:
    from paths import safe_join
except Exception as e:  # noqa: BLE001
    print(f"FAIL: import できない: {type(e).__name__}: {e}")
    sys.exit(1)

BASE = os.path.abspath(os.path.join(os.sep, "srv", "data"))

REJECT = [
    "../etc/passwd",
    "sub/../../etc/passwd",
    os.path.join(os.sep, "etc", "passwd"),
    "../data-evil/x",
    "",
    ".",
]

for bad in REJECT:
    try:
        got = safe_join(BASE, bad)
        fails.append(f"reject {bad!r}: 通ってしまった -> {got!r}")
    except ValueError:
        pass
    except Exception as e:  # noqa: BLE001
        fails.append(f"reject {bad!r}: ValueError 以外が飛んだ: {type(e).__name__}: {e}")

ACCEPT = {
    "a.txt": os.path.join(BASE, "a.txt"),
    "sub/dir/a.txt": os.path.join(BASE, "sub", "dir", "a.txt"),
    "./a.txt": os.path.join(BASE, "a.txt"),
    "sub/../a.txt": os.path.join(BASE, "a.txt"),
}

for good, want in ACCEPT.items():
    try:
        got = safe_join(BASE, good)
    except Exception as e:  # noqa: BLE001
        fails.append(f"accept {good!r}: 例外 {type(e).__name__}: {e}")
        continue
    if os.path.abspath(got) != os.path.abspath(want):
        fails.append(f"accept {good!r}: got {got!r}, want {want!r}")

if fails:
    print("FAIL")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print(f"PASS: all {len(REJECT) + len(ACCEPT)} checks")
