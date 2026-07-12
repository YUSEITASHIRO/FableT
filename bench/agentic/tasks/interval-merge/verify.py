"""隠しテスト。エージェントには見せない(repo/ の外に置いてある)。

実行時のカレントディレクトリはエージェントの作業ディレクトリ(repo の複製)。
終了コード 0 で合格。各チェックは独立に実行し、1つが例外で落ちても残りを続ける。
"""
import sys

sys.path.insert(0, ".")

fails = []


def expect(name, fn, want):
    """fn() == want を確認する。例外も失敗として記録し、次のチェックへ進む。"""
    try:
        got = fn()
    except Exception as e:  # noqa: BLE001
        fails.append(f"{name}: 例外 {type(e).__name__}: {e}")
        return
    if got != want:
        fails.append(f"{name}: got {got!r}, want {want!r}")


try:
    from intervals import merge_intervals
except Exception as e:  # noqa: BLE001
    print(f"FAIL: intervals.merge_intervals を import できない: {type(e).__name__}: {e}")
    sys.exit(1)

# 1. 接する区間の統合(バグ本体)
expect("touching", lambda: merge_intervals([(1, 3), (3, 5)]), [(1, 5)])

# 2. list 入力を受け付け、tuple のリストを返す
expect("list input", lambda: merge_intervals([[1, 3], (2, 4)]), [(1, 4)])
try:
    got = merge_intervals([[1, 3], (2, 4)])
    if got and not all(isinstance(x, tuple) for x in got):
        fails.append(f"list input: 戻り値が tuple のリストでない: {got!r}")
except Exception:  # noqa: BLE001, S110
    pass  # 上の expect ですでに記録済み

# 3. start > end は ValueError
try:
    merge_intervals([(5, 1)])
    fails.append("inverted: ValueError が送出されなかった")
except ValueError:
    pass
except Exception as e:  # noqa: BLE001
    fails.append(f"inverted: ValueError 以外が飛んだ: {type(e).__name__}")

# 既存の振る舞い(回帰チェック)
expect("empty", lambda: merge_intervals([]), [])
expect("unsorted", lambda: merge_intervals([(5, 7), (1, 3), (2, 4)]), [(1, 4), (5, 7)])
expect("containment", lambda: merge_intervals([(1, 10), (2, 3)]), [(1, 10)])
expect("disjoint", lambda: merge_intervals([(1, 2), (4, 5)]), [(1, 2), (4, 5)])

if fails:
    print("FAIL")
    for f in fails:
        print("  -", f)
    sys.exit(1)

print("PASS: all 7 checks")
