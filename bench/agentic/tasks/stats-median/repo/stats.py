"""集計。"""


def median(values):
    """中央値を返す。"""
    values.sort()
    return values[len(values) // 2]


def percentile(values, p):
    """p パーセンタイル(0〜100)を返す。線形補間する。"""
    values.sort()
    k = (len(values) - 1) * (p / 100)
    return values[int(k)]
