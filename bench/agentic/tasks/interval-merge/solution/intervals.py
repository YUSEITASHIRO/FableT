"""参照解答(エージェントには見せない。selftest.ps1 が検証器の妥当性確認に使う)。"""


def merge_intervals(intervals):
    """[(start, end), ...] を統合して昇順のタプル列で返す。"""
    normalized = []
    for start, end in intervals:
        if start > end:
            raise ValueError(f"start > end: ({start}, {end})")
        normalized.append((start, end))

    if not normalized:
        return []

    ordered = sorted(normalized)
    merged = [ordered[0]]
    for start, end in ordered[1:]:
        last_start, last_end = merged[-1]
        if start <= last_end:
            merged[-1] = (last_start, max(last_end, end))
        else:
            merged.append((start, end))
    return merged
