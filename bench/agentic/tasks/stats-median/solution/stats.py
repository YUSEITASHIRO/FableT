"""参照解答(エージェントには見せない)。"""


def median(values):
    """中央値。偶数個なら中央2つの平均。入力は破壊しない。"""
    if not values:
        raise ValueError("空のリストの中央値は定義できない")

    ordered = sorted(values)
    n = len(ordered)
    mid = n // 2

    if n % 2 == 1:
        return ordered[mid]
    return (ordered[mid - 1] + ordered[mid]) / 2


def percentile(values, p):
    """p パーセンタイル(線形補間)。入力は破壊しない。"""
    if not values:
        raise ValueError("空のリストのパーセンタイルは定義できない")
    if p < 0 or p > 100:
        raise ValueError(f"p は 0〜100: {p}")

    ordered = sorted(values)
    k = (len(ordered) - 1) * (p / 100)
    lo = int(k)
    hi = min(lo + 1, len(ordered) - 1)
    frac = k - lo

    return ordered[lo] + (ordered[hi] - ordered[lo]) * frac
