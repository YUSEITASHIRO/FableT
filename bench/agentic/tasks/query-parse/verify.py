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
    from query import parse_query
except Exception as e:  # noqa: BLE001
    print(f"FAIL: import できない: {type(e).__name__}: {e}")
    sys.exit(1)

src = open("query.py", encoding="utf-8").read()
for banned in ("urllib", "import cgi", "from cgi"):
    if banned in src:
        fails.append(f"policy: {banned} を使っている(方針違反)")

expect("basic", lambda: parse_query("a=1&b=2"), {"a": "1", "b": "2"})
expect("equals in value", lambda: parse_query("a=1=2"), {"a": "1=2"})
expect("repeated key", lambda: parse_query("a=1&a=2&b=3"), {"a": ["1", "2"], "b": "3"})
expect("repeated three", lambda: parse_query("a=1&a=2&a=3"), {"a": ["1", "2", "3"]})
expect("valueless key", lambda: parse_query("a&b=1"), {"a": "", "b": "1"})
expect("plus is space", lambda: parse_query("q=hello+world"), {"q": "hello world"})
expect("percent utf8", lambda: parse_query("t=%E6%97%A5"), {"t": "日"})
expect("percent in key", lambda: parse_query("%E6%97%A5=1"), {"日": "1"})
expect("empty string", lambda: parse_query(""), {})
expect("leading question mark", lambda: parse_query("?a=1"), {"a": "1"})
expect("empty value", lambda: parse_query("a="), {"a": ""})

for bad in ("a=%ZZ", "a=%E"):
    try:
        parse_query(bad)
        fails.append(f"invalid {bad!r}: ValueError が送出されなかった")
    except ValueError:
        pass
    except Exception as e:  # noqa: BLE001
        fails.append(f"invalid {bad!r}: ValueError 以外が飛んだ: {type(e).__name__}")

if fails:
    print("FAIL")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("PASS: all 13 checks")
