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
    from money import apply_tax, split_bill
except Exception as e:  # noqa: BLE001
    print(f"FAIL: import できない: {type(e).__name__}: {e}")
    sys.exit(1)

# 四捨五入(0.5 切り上げ)。組込み round は 10 を返すので、ここで差がつく
expect("tax half up", lambda: apply_tax(10, 0.05), 11)
expect("tax 105", lambda: apply_tax(105, 0.05), 110)
expect("tax 101", lambda: apply_tax(101, 0.05), 106)
expect("tax zero rate", lambda: apply_tax(100, 0.0), 100)

# 割り勘: 合計が total とちょうど一致し、端数は先頭から
expect("split 1000/3", lambda: split_bill(1000, 3), [334, 333, 333])
expect("split 100/3", lambda: split_bill(100, 3), [34, 33, 33])
expect("split 90/3", lambda: split_bill(90, 3), [30, 30, 30])
expect("split 1/2", lambda: split_bill(1, 2), [1, 0])
expect("split single", lambda: split_bill(7, 1), [7])

for name, args in [("people 0", (100, 0)), ("people -1", (100, -1)), ("negative total", (-1, 2))]:
    try:
        split_bill(*args)
        fails.append(f"{name}: ValueError が送出されなかった")
    except ValueError:
        pass
    except Exception as e:  # noqa: BLE001
        fails.append(f"{name}: ValueError 以外が飛んだ: {type(e).__name__}")

# 合計一致は不変条件として広めに確認する
for total in (0, 1, 7, 999, 100000):
    for people in (1, 2, 3, 7):
        try:
            parts = split_bill(total, people)
        except Exception as e:  # noqa: BLE001
            fails.append(f"invariant({total},{people}): 例外 {type(e).__name__}: {e}")
            continue
        if len(parts) != people or sum(parts) != total:
            fails.append(f"invariant({total},{people}): got {parts!r} (sum={sum(parts)})")

if fails:
    print("FAIL")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("PASS: all checks")
