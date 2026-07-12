"""参照解答(エージェントには見せない)。"""


def _check(start, end):
    if start > end:
        raise ValueError(f"start > end: {start} > {end}")


def overlaps(a_start, a_end, b_start, b_end):
    """半開区間 [start, end) として重なりを判定する。空区間はどことも重ならない。"""
    _check(a_start, a_end)
    _check(b_start, b_end)

    if a_start == a_end or b_start == b_end:
        return False

    return a_start < b_end and b_start < a_end


def total_days(ranges):
    """重なりを1回だけ数えた総日数。"""
    for start, end in ranges:
        _check(start, end)

    spans = sorted((s, e) for s, e in ranges if s < e)
    if not spans:
        return 0

    total = 0
    cur_start, cur_end = spans[0]
    for start, end in spans[1:]:
        if start <= cur_end:
            cur_end = max(cur_end, end)
        else:
            total += (cur_end - cur_start).days
            cur_start, cur_end = start, end

    total += (cur_end - cur_start).days
    return total
