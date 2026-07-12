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
    from batch import chunk, chunk_by_bytes
except Exception as e:  # noqa: BLE001
    print(f"FAIL: import できない: {type(e).__name__}: {e}")
    sys.exit(1)

size_of = len  # レコードは文字列。バイト数 = 長さ とみなす

expect("chunk basic", lambda: chunk([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]])
expect("chunk empty", lambda: chunk([], 2), [])

# 合計が max を超えない。超えるなら次のバッチへ
expect(
    "bytes no overflow",
    lambda: chunk_by_bytes(["aa", "bb", "cc"], 4, size_of),
    [["aa", "bb"], ["cc"]],
)
expect(
    "bytes keeps last batch",
    lambda: chunk_by_bytes(["a", "b"], 10, size_of),
    [["a", "b"]],
)
expect(
    "oversized alone",
    lambda: chunk_by_bytes(["a", "xxxxxxxxxx", "b"], 3, size_of),
    [["a"], ["xxxxxxxxxx"], ["b"]],
)
expect("bytes empty", lambda: chunk_by_bytes([], 5, size_of), [])
expect("exact fit", lambda: chunk_by_bytes(["ab", "cd"], 2, size_of), [["ab"], ["cd"]])

# 不変条件: どのバッチも max_bytes 以内(単独で超えるものを除く)、レコードの欠落なし
records = ["a", "bb", "ccc", "dddd", "e", "ff"]
for max_bytes in (1, 3, 5, 100):
    try:
        batches = chunk_by_bytes(records, max_bytes, size_of)
    except Exception as e:  # noqa: BLE001
        fails.append(f"invariant(max={max_bytes}): 例外 {type(e).__name__}: {e}")
        continue
    flat = [r for b in batches for r in b]
    if flat != records:
        fails.append(f"invariant(max={max_bytes}): レコードが欠落/順序が変わった: {batches!r}")
    for b in batches:
        total = sum(size_of(r) for r in b)
        if total > max_bytes and len(b) > 1:
            fails.append(f"invariant(max={max_bytes}): 超過バッチがある: {b!r} (={total})")
        if not b:
            fails.append(f"invariant(max={max_bytes}): 空バッチがある: {batches!r}")

for name, fn in [
    ("chunk size 0", lambda: chunk([1, 2], 0)),
    ("chunk size -1", lambda: chunk([1, 2], -1)),
    ("max_bytes 0", lambda: chunk_by_bytes(["a"], 0, size_of)),
]:
    try:
        fn()
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
print("PASS: all checks")
