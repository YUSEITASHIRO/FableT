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
    from lru import LRUCache
except Exception as e:  # noqa: BLE001
    print(f"FAIL: import できない: {type(e).__name__}: {e}")
    sys.exit(1)


def test_get_refreshes():
    c = LRUCache(2)
    c.put("a", 1)
    c.put("b", 2)
    assert c.get("a") == 1, "a が取れない"
    c.put("c", 3)  # 追い出されるべきは b(a は今 get したばかり)
    assert c.get("a") == 1, "get したのに a が追い出された"
    assert c.get("b") is None, "b が追い出されていない"
    assert c.get("c") == 3, "c が入っていない"


def test_put_existing_refreshes():
    c = LRUCache(2)
    c.put("a", 1)
    c.put("b", 2)
    c.put("a", 10)  # a を更新 → a が最新
    assert len(c) == 2, f"要素数が増えた: {len(c)}"
    assert c.get("a") == 10, "値が更新されていない"
    c.put("c", 3)  # 追い出されるべきは b
    assert c.get("b") is None, "b が追い出されていない"
    assert c.get("a") == 10, "a が追い出された"


def test_capacity_validation():
    for bad in (0, -1):
        try:
            LRUCache(bad)
        except ValueError:
            continue
        raise AssertionError(f"capacity={bad} で ValueError が出ない")


def test_basic_behaviour():
    c = LRUCache(2)
    assert c.get("x") is None, "無いキーで None が返らない"
    assert c.get("x", "d") == "d", "default が効かない"
    c.put("a", 1)
    assert len(c) == 1, f"len が違う: {len(c)}"


def test_evicts_only_one():
    c = LRUCache(2)
    c.put("a", 1)
    c.put("b", 2)
    c.put("c", 3)
    assert len(c) == 2, f"容量を超えている/減りすぎ: {len(c)}"


run("get_refreshes", test_get_refreshes)
run("put_existing_refreshes", test_put_existing_refreshes)
run("capacity_validation", test_capacity_validation)
run("basic_behaviour", test_basic_behaviour)
run("evicts_only_one", test_evicts_only_one)

if fails:
    print("FAIL")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("PASS: all 5 checks")
