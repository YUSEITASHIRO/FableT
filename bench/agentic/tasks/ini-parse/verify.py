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
    from ini import parse_ini
except Exception as e:  # noqa: BLE001
    print(f"FAIL: import できない: {type(e).__name__}: {e}")
    sys.exit(1)

src = open("ini.py", encoding="utf-8").read()
if "configparser" in src:
    fails.append("policy: configparser を使っている(方針違反)")

TEXT = """
[server]
# コメント
host = example.com
port=8080

; 別のコメント形式
[client]
  url = http://x/?a=1
[server]
timeout = 30
"""

expect(
    "full parse",
    lambda: parse_ini(TEXT),
    {
        "server": {"host": "example.com", "port": "8080", "timeout": "30"},
        "client": {"url": "http://x/?a=1"},
    },
)

expect("empty text", lambda: parse_ini(""), {})
expect("section only", lambda: parse_ini("[a]"), {"a": {}})
expect("spaces in section", lambda: parse_ini("[ a ]\nk=v"), {"a": {"k": "v"}})
expect("comment only", lambda: parse_ini("# nothing\n; nothing"), {})
expect("value with equals", lambda: parse_ini("[s]\nk = a=b=c"), {"s": {"k": "a=b=c"}})
expect("empty value", lambda: parse_ini("[s]\nk ="), {"s": {"k": ""}})

for name, text in [
    ("key outside section", "k=v"),
    ("line without equals", "[s]\nbroken line"),
]:
    try:
        parse_ini(text)
        fails.append(f"{name}: ValueError が送出されなかった")
    except ValueError:
        pass
    except Exception as e:  # noqa: BLE001
        fails.append(f"{name}: ValueError 以外が飛んだ: {type(e).__name__}")

if fails:
    print("FAIL")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("PASS: all 10 checks")
