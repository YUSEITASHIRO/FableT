"""隠しテスト。エージェントには見せない(repo/ の外に置いてある)。

終了コード 0 で合格。各チェックは独立に走らせ、例外で落ちても残りを続ける。
"""
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
    from errors import FatalError, TransientError
    from retry import call_with_retry
except Exception as e:  # noqa: BLE001
    print(f"FAIL: import できない: {type(e).__name__}: {e}")
    sys.exit(1)


def test_success_no_sleep():
    """成功する呼び出しでは一度も待たない(1回目は即座に呼ぶ)。"""
    slept = []
    result = call_with_retry(lambda: "ok", sleep=slept.append)
    assert result == "ok", f"戻り値が違う: {result!r}"
    assert slept == [], f"成功時に待っている: {slept!r}"


def test_backoff_schedule():
    """失敗後のみ待ち、遅延は base_delay の指数増加になる。"""
    slept = []
    calls = []

    def flaky():
        calls.append(1)
        if len(calls) < 3:
            raise TransientError("boom")
        return "done"

    result = call_with_retry(flaky, max_attempts=5, base_delay=1.0, sleep=slept.append)
    assert result == "done", f"戻り値が違う: {result!r}"
    assert len(calls) == 3, f"呼び出し回数が違う: {len(calls)}"
    assert slept == [1.0, 2.0], f"バックオフ列が違う: {slept!r} (want [1.0, 2.0])"


def test_fatal_not_retried():
    """FatalError は再試行せず、待たずにそのまま送出する。"""
    calls = []
    slept = []

    def fatal():
        calls.append(1)
        raise FatalError("nope")

    try:
        call_with_retry(fatal, max_attempts=5, sleep=slept.append)
    except FatalError:
        pass
    else:
        raise AssertionError("FatalError が送出されなかった")
    assert len(calls) == 1, f"FatalError を再試行している: {len(calls)} 回呼ばれた"
    assert slept == [], f"FatalError なのに待っている: {slept!r}"


def test_unexpected_not_retried():
    """想定外の例外も再試行しない。"""
    calls = []

    def boom():
        calls.append(1)
        raise KeyError("unexpected")

    try:
        call_with_retry(boom, max_attempts=5, sleep=lambda _: None)
    except KeyError:
        pass
    else:
        raise AssertionError("KeyError が送出されなかった")
    assert len(calls) == 1, f"想定外例外を再試行している: {len(calls)} 回呼ばれた"


def test_exhausted_raises_last():
    """全試行が TransientError なら最後の TransientError を送出する。"""
    calls = []

    def always_fail():
        calls.append(1)
        raise TransientError(f"fail-{len(calls)}")

    try:
        call_with_retry(always_fail, max_attempts=3, base_delay=0.5, sleep=lambda _: None)
    except TransientError as e:
        assert str(e) == "fail-3", f"最後の例外でない: {e}"
    else:
        raise AssertionError("TransientError が送出されなかった")
    assert len(calls) == 3, f"試行回数が違う: {len(calls)} (want 3)"


run("success_no_sleep", test_success_no_sleep)
run("backoff_schedule", test_backoff_schedule)
run("fatal_not_retried", test_fatal_not_retried)
run("unexpected_not_retried", test_unexpected_not_retried)
run("exhausted_raises_last", test_exhausted_raises_last)

if fails:
    print("FAIL")
    for f in fails:
        print("  -", f)
    sys.exit(1)

print("PASS: all 5 checks")
