import copy
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
    from events import dedupe
except Exception as e:  # noqa: BLE001
    print(f"FAIL: import できない: {type(e).__name__}: {e}")
    sys.exit(1)


def test_keeps_latest():
    evts = [
        {"key": "a", "ts": 1, "v": "old"},
        {"key": "b", "ts": 5, "v": "b1"},
        {"key": "a", "ts": 9, "v": "new"},
    ]
    got = dedupe(evts)
    assert [e["key"] for e in got] == ["a", "b"], f"初出順でない: {got!r}"
    assert got[0]["v"] == "new", f"最新が残っていない: {got[0]!r}"
    assert got[1]["v"] == "b1", f"b が壊れている: {got[1]!r}"


def test_tie_prefers_later():
    evts = [
        {"key": "a", "ts": 3, "v": "first"},
        {"key": "a", "ts": 3, "v": "second"},
    ]
    got = dedupe(evts)
    assert len(got) == 1, f"重複が残っている: {got!r}"
    assert got[0]["v"] == "second", f"同点で後勝ちになっていない: {got[0]!r}"


def test_first_seen_order():
    evts = [
        {"key": "z", "ts": 1},
        {"key": "y", "ts": 1},
        {"key": "z", "ts": 2},
    ]
    got = dedupe(evts)
    assert [e["key"] for e in got] == ["z", "y"], f"初出順が保たれていない: {got!r}"


def test_missing_field():
    for bad in ([{"ts": 1}], [{"key": "a"}]):
        try:
            dedupe(bad)
        except ValueError as e:
            assert "key" in str(e) or "ts" in str(e) or "{" in str(e), f"メッセージが不十分: {e}"
        except Exception as e:  # noqa: BLE001
            raise AssertionError(f"ValueError 以外が飛んだ: {type(e).__name__}") from e
        else:
            raise AssertionError(f"{bad!r} で ValueError が出ない")


def test_no_mutation():
    evts = [{"key": "a", "ts": 1}, {"key": "a", "ts": 2}]
    snapshot = copy.deepcopy(evts)
    dedupe(evts)
    assert evts == snapshot, f"入力が書き換えられた: {evts!r}"


def test_empty():
    assert dedupe([]) == [], "空リストで空が返らない"


run("keeps_latest", test_keeps_latest)
run("tie_prefers_later", test_tie_prefers_later)
run("first_seen_order", test_first_seen_order)
run("missing_field", test_missing_field)
run("no_mutation", test_no_mutation)
run("empty", test_empty)

if fails:
    print("FAIL")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("PASS: all 6 checks")
