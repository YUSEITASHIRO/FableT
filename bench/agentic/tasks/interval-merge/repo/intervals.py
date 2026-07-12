"""区間ユーティリティ。

merge_intervals は重なり合う区間を統合して返す。
"""


def merge_intervals(intervals):
    """[(start, end), ...] を受け取り、重なる区間を統合して昇順で返す。

    端点が接している区間(例: (1, 3) と (3, 5))も1つに統合する。
    """
    if not intervals:
        return []

    ordered = sorted(intervals)
    merged = [ordered[0]]

    for start, end in ordered[1:]:
        last_start, last_end = merged[-1]
        if start < last_end:
            merged[-1] = (last_start, max(last_end, end))
        else:
            merged.append((start, end))

    return merged
