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
    from diffs import diff
except Exception as e:  # noqa: BLE001
    print(f"FAIL: import できない: {type(e).__name__}: {e}")
    sys.exit(1)

src = open("diffs.py", encoding="utf-8").read()
if "difflib" in src:
    fails.append("policy: difflib を使っている(方針違反)")

expect(
    "insertion keeps common lines",
    lambda: diff("a\nb\nc", "a\nX\nb\nc"),
    [("=", "a"), ("+", "X"), ("=", "b"), ("=", "c")],
)
expect(
    "deletion",
    lambda: diff("a\nb\nc", "a\nc"),
    [("=", "a"), ("-", "b"), ("=", "c")],
)
expect("identical", lambda: diff("a\nb", "a\nb"), [("=", "a"), ("=", "b")])
expect("all added", lambda: diff("", "a\nb"), [("+", "a"), ("+", "b")])
expect("all removed", lambda: diff("a\nb", ""), [("-", "a"), ("-", "b")])
expect("both empty", lambda: diff("", ""), [])
expect(
    "delete before add at same spot",
    lambda: diff("a\nb", "a\nc"),
    [("=", "a"), ("-", "b"), ("+", "c")],
)

# 復元可能性(不変条件)
cases = [
    ("a\nb\nc\nd", "a\nc\nx\nd"),
    ("1\n2\n3", "3\n2\n1"),
    ("same", "same"),
    ("x", "y"),
]
for old, new in cases:
    try:
        ops = diff(old, new)
    except Exception as e:  # noqa: BLE001
        fails.append(f"invariant({old!r},{new!r}): 例外 {type(e).__name__}: {e}")
        continue
    rebuilt_old = [ln for op, ln in ops if op in ("=", "-")]
    rebuilt_new = [ln for op, ln in ops if op in ("=", "+")]
    if rebuilt_old != old.splitlines():
        fails.append(f"invariant({old!r},{new!r}): old を復元できない: {ops!r}")
    if rebuilt_new != new.splitlines():
        fails.append(f"invariant({old!r},{new!r}): new を復元できない: {ops!r}")
    if any(op not in ("=", "-", "+") for op, _ in ops):
        fails.append(f"invariant({old!r},{new!r}): 未知の op がある: {ops!r}")

# LCS であること: 共通行の数が最大化されている(この例では 3 行が = になるはず)
ops = diff("a\nb\nc\nd", "a\nc\nx\nd")
same_count = sum(1 for op, _ in ops if op == "=")
if same_count != 3:
    fails.append(f"LCS になっていない: '=' が {same_count} 行 (want 3): {ops!r}")

if fails:
    print("FAIL")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("PASS: all checks")
