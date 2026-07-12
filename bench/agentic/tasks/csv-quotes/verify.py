import sys

sys.path.insert(0, ".")
fails = []


def expect(name, fn, want):
    try:
        got = fn()
    except Exception as e:  # noqa: BLE001
        fails.append(f"{name}: 例外 {type(e).__name__}: {e}")
        return
    if got != want:
        fails.append(f"{name}: got {got!r}, want {want!r}")


try:
    import csvlite
    from csvlite import parse_line
except Exception as e:  # noqa: BLE001
    print(f"FAIL: import できない: {type(e).__name__}: {e}")
    sys.exit(1)

# 方針: 標準ライブラリの csv を使っていないこと
src = open("csvlite.py", encoding="utf-8").read()
if "import csv" in src or "from csv " in src:
    fails.append("policy: 標準ライブラリの csv モジュールを使っている(方針違反)")

expect("quoted comma", lambda: parse_line('a,"b,c",d'), ["a", "b,c", "d"])
expect("escaped quotes", lambda: parse_line('a,"he said ""hi""",b'), ["a", 'he said "hi"', "b"])
expect("plain", lambda: parse_line("a,b,c"), ["a", "b", "c"])
expect("empty fields", lambda: parse_line("a,,b"), ["a", "", "b"])
expect("trailing newline", lambda: parse_line("a,b\n"), ["a", "b"])
expect("spaces kept", lambda: parse_line("a, b ,c"), ["a", " b ", "c"])
expect("quoted empty", lambda: parse_line('a,"",b'), ["a", "", "b"])

try:
    parse_line('a,"unterminated')
    fails.append("unterminated: ValueError が送出されなかった")
except ValueError:
    pass
except Exception as e:  # noqa: BLE001
    fails.append(f"unterminated: ValueError 以外が飛んだ: {type(e).__name__}")

if fails:
    print("FAIL")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("PASS: all 9 checks")
