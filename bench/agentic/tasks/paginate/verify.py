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


def expect_raises(name, fn, exc=ValueError):
    try:
        fn()
    except exc:
        return
    except Exception as e:  # noqa: BLE001
        fails.append(f"{name}: {exc.__name__} 以外が飛んだ: {type(e).__name__}")
        return
    fails.append(f"{name}: {exc.__name__} が送出されなかった")


try:
    from page import page_count, paginate
except Exception as e:  # noqa: BLE001
    print(f"FAIL: import できない: {type(e).__name__}: {e}")
    sys.exit(1)

items = [1, 2, 3, 4, 5]

expect("first page", lambda: paginate(items, 1, 2), [1, 2])
expect("second page", lambda: paginate(items, 2, 2), [3, 4])
expect("last partial page", lambda: paginate(items, 3, 2), [5])
expect("out of range", lambda: paginate(items, 9, 2), [])
expect("empty items", lambda: paginate([], 1, 2), [])
expect("per_page bigger than items", lambda: paginate(items, 1, 100), [1, 2, 3, 4, 5])

expect("count 5/2", lambda: page_count(5, 2), 3)
expect("count 4/2", lambda: page_count(4, 2), 2)
expect("count 0/2", lambda: page_count(0, 2), 0)
expect("count 1/10", lambda: page_count(1, 10), 1)

expect_raises("page 0", lambda: paginate(items, 0, 2))
expect_raises("page -1", lambda: paginate(items, -1, 2))
expect_raises("per_page 0", lambda: paginate(items, 1, 0))
expect_raises("count per_page 0", lambda: page_count(5, 0))

if fails:
    print("FAIL")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("PASS: all 14 checks")
