import sys
from datetime import date

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
    from ranges import overlaps, total_days
except Exception as e:  # noqa: BLE001
    print(f"FAIL: import できない: {type(e).__name__}: {e}")
    sys.exit(1)


def d(day):
    return date(2026, 1, day)


expect("touching not overlap", lambda: overlaps(d(1), d(3), d(3), d(5)), False)
expect("real overlap", lambda: overlaps(d(1), d(4), d(3), d(5)), True)
expect("disjoint", lambda: overlaps(d(1), d(2), d(5), d(6)), False)
expect("contained", lambda: overlaps(d(1), d(9), d(3), d(4)), True)
expect("empty range never overlaps", lambda: overlaps(d(3), d(3), d(1), d(5)), False)
expect("reversed args same result", lambda: overlaps(d(3), d(5), d(1), d(3)), False)

expect("merged days", lambda: total_days([(d(1), d(5)), (d(3), d(7))]), 6)
expect("disjoint days", lambda: total_days([(d(1), d(2)), (d(5), d(6))]), 2)
expect("single", lambda: total_days([(d(1), d(4))]), 3)
expect("empty list", lambda: total_days([]), 0)
expect("empty range", lambda: total_days([(d(1), d(1))]), 0)
expect("contained days", lambda: total_days([(d(1), d(10)), (d(3), d(4))]), 9)
expect("touching days", lambda: total_days([(d(1), d(3)), (d(3), d(5))]), 4)
expect("unsorted", lambda: total_days([(d(5), d(7)), (d(1), d(3))]), 4)

for name, fn in [
    ("overlaps invalid", lambda: overlaps(d(5), d(1), d(1), d(2))),
    ("total_days invalid", lambda: total_days([(d(5), d(1))])),
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
print("PASS: all 16 checks")
