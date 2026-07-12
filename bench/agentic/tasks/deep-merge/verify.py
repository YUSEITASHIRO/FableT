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
    from config import merge
except Exception as e:  # noqa: BLE001
    print(f"FAIL: import できない: {type(e).__name__}: {e}")
    sys.exit(1)


def test_no_mutation():
    base = {"a": 1, "nested": {"x": 1}}
    merge(base, {"a": 2, "nested": {"x": 9}})
    assert base == {"a": 1, "nested": {"x": 1}}, f"base が破壊された: {base!r}"


def test_deep_copy_of_result():
    base = {"nested": {"x": 1}}
    got = merge(base, {})
    got["nested"]["x"] = 99
    assert base["nested"]["x"] == 1, "結果を書き換えたら base まで変わった(浅いコピー)"


def test_recursive_merge():
    got = merge({"db": {"host": "h", "port": 1}}, {"db": {"port": 2}})
    assert got == {"db": {"host": "h", "port": 2}}, f"ネストがマージされていない: {got!r}"


def test_none_deletes():
    got = merge({"a": 1, "b": 2}, {"b": None})
    assert got == {"a": 1}, f"None で削除されていない: {got!r}"


def test_none_missing_key_ok():
    got = merge({"a": 1}, {"zzz": None})
    assert got == {"a": 1}, f"存在しないキーの None で壊れた: {got!r}"


def test_none_nested():
    got = merge({"db": {"host": "h", "port": 1}}, {"db": {"port": None}})
    assert got == {"db": {"host": "h"}}, f"ネスト内の None 削除ができていない: {got!r}"


def test_type_mismatch_overrides():
    got = merge({"a": {"x": 1}}, {"a": 5})
    assert got == {"a": 5}, f"型不一致は上書きのはず: {got!r}"
    got2 = merge({"a": 5}, {"a": {"x": 1}})
    assert got2 == {"a": {"x": 1}}, f"型不一致は上書きのはず: {got2!r}"


def test_plain_override():
    got = merge({"a": 1}, {"b": 2})
    assert got == {"a": 1, "b": 2}, f"単純な追加ができていない: {got!r}"


run("no_mutation", test_no_mutation)
run("deep_copy_of_result", test_deep_copy_of_result)
run("recursive_merge", test_recursive_merge)
run("none_deletes", test_none_deletes)
run("none_missing_key_ok", test_none_missing_key_ok)
run("none_nested", test_none_nested)
run("type_mismatch_overrides", test_type_mismatch_overrides)
run("plain_override", test_plain_override)

if fails:
    print("FAIL")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("PASS: all 8 checks")
