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
    import graph
    from graph import resolve_order
except Exception as e:  # noqa: BLE001
    print(f"FAIL: import できない: {type(e).__name__}: {e}")
    sys.exit(1)


def test_cycle_error_defined():
    assert hasattr(graph, "CycleError"), "CycleError が定義されていない"
    assert issubclass(graph.CycleError, ValueError), "CycleError が ValueError を継承していない"


def test_cycle_detected():
    deps = {"a": ["b"], "b": ["c"], "c": ["a"]}
    try:
        got = resolve_order(deps)
    except graph.CycleError as e:
        assert any(n in str(e) for n in ("a", "b", "c")), f"メッセージにノード名が無い: {e}"
        return
    raise AssertionError(f"循環なのに CycleError が出ず {got!r} を返した")


def test_self_cycle():
    try:
        resolve_order({"a": ["a"]})
    except graph.CycleError:
        return
    raise AssertionError("自己ループで CycleError が出ない")


def test_leaf_included():
    got = resolve_order({"a": ["b"]})
    assert got == ["b", "a"], f"葉ノードが欠けている: {got!r}"


def test_dependency_before():
    deps = {"app": ["lib", "util"], "lib": ["util"], "util": []}
    got = resolve_order(deps)
    assert set(got) == {"app", "lib", "util"}, f"ノードが欠けている: {got!r}"
    for node, ds in deps.items():
        for d in ds:
            assert got.index(d) < got.index(node), f"{d} が {node} より後ろ: {got!r}"


def test_stable_order():
    got = resolve_order({"a": [], "b": [], "c": []})
    assert got == ["a", "b", "c"], f"挿入順が保たれていない: {got!r}"


def test_diamond():
    deps = {"d": ["b", "c"], "b": ["a"], "c": ["a"], "a": []}
    got = resolve_order(deps)
    assert got.index("a") < got.index("b") < got.index("d"), f"順序が不正: {got!r}"
    assert got.index("c") < got.index("d"), f"順序が不正: {got!r}"
    assert len(got) == len(set(got)) == 4, f"重複か欠落がある: {got!r}"


run("cycle_error_defined", test_cycle_error_defined)
run("cycle_detected", test_cycle_detected)
run("self_cycle", test_self_cycle)
run("leaf_included", test_leaf_included)
run("dependency_before", test_dependency_before)
run("stable_order", test_stable_order)
run("diamond", test_diamond)

if fails:
    print("FAIL")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("PASS: all 7 checks")
