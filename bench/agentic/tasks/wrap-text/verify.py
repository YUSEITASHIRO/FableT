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
    from wrap import wrap
except Exception as e:  # noqa: BLE001
    print(f"FAIL: import できない: {type(e).__name__}: {e}")
    sys.exit(1)

src = open("wrap.py", encoding="utf-8").read()
if "textwrap" in src:
    fails.append("policy: textwrap を使っている(方針違反)")

expect("basic", lambda: wrap("a bb ccc", 5), ["a bb", "ccc"])
expect("exact fit", lambda: wrap("aaa bbb", 3), ["aaa", "bbb"])
expect("long word alone", lambda: wrap("ab abcdefgh ij", 4), ["ab", "abcdefgh", "ij"])
expect("single word", lambda: wrap("hello", 10), ["hello"])
expect("empty", lambda: wrap("", 5), [])
expect("spaces only", lambda: wrap("   ", 5), [])
expect("collapse spaces", lambda: wrap("a   b", 5), ["a b"])
expect("all fits", lambda: wrap("a b c", 10), ["a b c"])

# 不変条件: 行頭行末に空白が無い / 単語の欠落や重複が無い
text = "the quick brown fox jumps over the lazy dog"
for width in (3, 5, 10, 20):
    try:
        lines = wrap(text, width)
    except Exception as e:  # noqa: BLE001
        fails.append(f"invariant(width={width}): 例外 {type(e).__name__}: {e}")
        continue
    if any(ln != ln.strip() for ln in lines):
        fails.append(f"invariant(width={width}): 行頭/行末に空白がある: {lines!r}")
    if " ".join(lines).split() != text.split():
        fails.append(f"invariant(width={width}): 単語が欠落/重複している: {lines!r}")
    for ln in lines:
        if len(ln) > width and " " in ln:
            fails.append(f"invariant(width={width}): width 超過の行がある: {ln!r}")

for bad in (0, -1):
    try:
        wrap("a b", bad)
        fails.append(f"width {bad}: ValueError が送出されなかった")
    except ValueError:
        pass
    except Exception as e:  # noqa: BLE001
        fails.append(f"width {bad}: ValueError 以外が飛んだ: {type(e).__name__}")

if fails:
    print("FAIL")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("PASS: all checks")
