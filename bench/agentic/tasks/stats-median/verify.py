import sys

sys.path.insert(0, ".")
fails = []


def expect(name, fn, want, tol=1e-9):
    try:
        got = fn()
    except Exception as e:  # noqa: BLE001
        fails.append(f"{name}: 例外 {type(e).__name__}: {e}")
        return
    if not isinstance(got, (int, float)) or abs(got - want) > tol:
        fails.append(f"{name}: got {got!r}, want {want!r}")


try:
    import stats
    from stats import median, percentile
except Exception as e:  # noqa: BLE001
    print(f"FAIL: import できない: {type(e).__name__}: {e}")
    sys.exit(1)

src = open("stats.py", encoding="utf-8").read()
for banned in ("import statistics", "import numpy"):
    if banned in src:
        fails.append(f"policy: {banned} を使っている(方針違反)")

expect("median odd", lambda: median([3, 1, 2]), 2)
expect("median even", lambda: median([1, 2, 3, 4]), 2.5)
expect("median single", lambda: median([7]), 7)
expect("median unsorted even", lambda: median([4, 1, 3, 2]), 2.5)

expect("p50", lambda: percentile([1, 2, 3, 4], 50), 2.5)
expect("p0", lambda: percentile([1, 2, 3, 4], 0), 1)
expect("p100", lambda: percentile([1, 2, 3, 4], 100), 4)
expect("p25 interp", lambda: percentile([10, 20], 25), 12.5)
expect("p90", lambda: percentile([1, 2, 3, 4, 5], 90), 4.6)

# 引数を破壊しないこと
data = [3, 1, 2]
median(data)
if data != [3, 1, 2]:
    fails.append(f"median が入力を破壊した: {data!r}")

data2 = [3, 1, 2]
percentile(data2, 50)
if data2 != [3, 1, 2]:
    fails.append(f"percentile が入力を破壊した: {data2!r}")

for name, fn in [
    ("median empty", lambda: median([])),
    ("percentile empty", lambda: percentile([], 50)),
    ("p negative", lambda: percentile([1, 2], -1)),
    ("p over 100", lambda: percentile([1, 2], 101)),
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
