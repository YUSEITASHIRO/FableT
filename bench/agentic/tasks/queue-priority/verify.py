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
    import pqueue
    from pqueue import JobQueue
except Exception as e:  # noqa: BLE001
    print(f"FAIL: import できない: {type(e).__name__}: {e}")
    sys.exit(1)


def test_priority_order():
    q = JobQueue()
    q.push(5, "low")
    q.push(1, "high")
    q.push(3, "mid")
    assert [q.pop() for _ in range(3)] == ["high", "mid", "low"], "優先度順でない"


def test_fifo_within_same_priority():
    q = JobQueue()
    for name in ("zeta", "alpha", "mike"):  # 値の順に並べると alpha が先になる
        q.push(1, name)
    got = [q.pop() for _ in range(3)]
    assert got == ["zeta", "alpha", "mike"], f"同一優先度で FIFO になっていない: {got!r}"


def test_uncomparable_job():
    q = JobQueue()
    a, b = {"id": 1}, {"id": 2}
    q.push(1, a)
    q.push(1, b)  # dict 同士は '<' で比較できない
    assert q.pop() is a, "先入れ先出しになっていない"
    assert q.pop() is b, "先入れ先出しになっていない"


def test_pop_empty_returns_none():
    q = JobQueue()
    assert q.pop() is None, "空の pop が None を返さない"


def test_len():
    q = JobQueue()
    assert len(q) == 0
    q.push(1, "a")
    q.push(2, "b")
    assert len(q) == 2, f"len が違う: {len(q)}"
    q.pop()
    assert len(q) == 1, f"pop 後の len が違う: {len(q)}"


def test_uses_heapq():
    src = open("pqueue.py", encoding="utf-8").read()
    assert "heapq" in src, "heapq を使っていない(方針違反)"
    assert "sort()" not in src and "sorted(" not in src, "全件ソートしている(方針違反)"


run("priority_order", test_priority_order)
run("fifo_same_priority", test_fifo_within_same_priority)
run("uncomparable_job", test_uncomparable_job)
run("pop_empty_none", test_pop_empty_returns_none)
run("len", test_len)
run("uses_heapq", test_uses_heapq)

if fails:
    print("FAIL")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("PASS: all 6 checks")
