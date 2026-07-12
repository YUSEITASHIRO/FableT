import sys

sys.path.insert(0, ".")
fails = []


def run(name, fn):
    try:
        fn()
    except AssertionError as e:
        fails.append(f"{name}: {e}")
    except Exception as e:  # noqa: BLE001
        fails.append(f"{name}: 予期しない例外 {type(e).__name__}: {e}")


try:
    from bucket import TokenBucket
except Exception as e:  # noqa: BLE001
    print(f"FAIL: import できない: {type(e).__name__}: {e}")
    sys.exit(1)


def test_cap_on_refill():
    b = TokenBucket(capacity=5, rate=1.0, now=0.0)
    for _ in range(5):
        assert b.allow(0.0), "初期満タンなのに拒否された"
    assert not b.allow(0.0), "空のはずが通った"
    # 1000秒放置しても上限は capacity=5
    allowed = sum(1 for _ in range(10) if b.allow(1000.0))
    assert allowed == 5, f"上限を超えて貯まっている: {allowed} 回通った (want 5)"


def test_clock_going_backwards():
    b = TokenBucket(capacity=5, rate=1.0, now=100.0)
    assert b.allow(100.0), "初期状態で拒否された"
    b.allow(90.0)  # 時刻が巻き戻る
    allowed = sum(1 for _ in range(10) if b.allow(90.0))
    assert allowed >= 3, f"巻き戻りでトークンが減った: 残り {allowed} 回しか通らない"


def test_cost_larger_than_capacity():
    b = TokenBucket(capacity=5, rate=1.0, now=0.0)
    try:
        b.allow(0.0, cost=6)
    except ValueError:
        return
    raise AssertionError("cost > capacity で ValueError が出ない")


def test_refill_proportional():
    b = TokenBucket(capacity=10, rate=2.0, now=0.0)
    for _ in range(10):
        b.allow(0.0)
    assert not b.allow(0.0), "空でないとおかしい"
    assert b.allow(1.5), "1.5秒で 3 個補充されるはずが通らない"


def test_no_consume_on_reject():
    b = TokenBucket(capacity=2, rate=0.0, now=0.0)
    assert b.allow(0.0, cost=2), "満タンなのに拒否された"
    assert not b.allow(0.0, cost=1), "空のはずが通った"
    assert not b.allow(0.0, cost=1), "拒否時に状態が壊れている"


run("cap_on_refill", test_cap_on_refill)
run("clock_backwards", test_clock_going_backwards)
run("cost_larger_than_capacity", test_cost_larger_than_capacity)
run("refill_proportional", test_refill_proportional)
run("no_consume_on_reject", test_no_consume_on_reject)

if fails:
    print("FAIL")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("PASS: all 5 checks")
