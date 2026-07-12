"""予約の期間が重なっているかを調べる。"""

from datetime import date


def overlaps(a_start, a_end, b_start, b_end):
    """期間 [a_start, a_end) と [b_start, b_end) が重なるか。

    終端は含まない(半開区間)。
    """
    return a_start <= b_end and b_start <= a_end


def total_days(ranges):
    """複数の期間 [(start, end), ...] が覆う日数の合計(重複は1回だけ数える)。"""
    total = 0
    for start, end in ranges:
        total += (end - start).days
    return total
