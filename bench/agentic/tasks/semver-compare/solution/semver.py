"""参照解答(エージェントには見せない)。"""


def _parse(v):
    if not isinstance(v, str):
        raise ValueError(f"文字列でない: {v!r}")
    core, _, pre = v.partition("-")
    parts = core.split(".")
    if len(parts) != 3:
        raise ValueError(f"数値部が3つでない: {v!r}")
    try:
        nums = [int(p) for p in parts]
    except ValueError as e:
        raise ValueError(f"数値部が数値でない: {v!r}") from e
    idents = pre.split(".") if pre else []
    return nums, idents


def _cmp(x, y):
    return (x > y) - (x < y)


def _cmp_ident(a, b):
    a_num, b_num = a.isdigit(), b.isdigit()
    if a_num and b_num:
        return _cmp(int(a), int(b))
    if a_num:
        return -1  # 数値の要素は英数字の要素より小さい
    if b_num:
        return 1
    return _cmp(a, b)


def compare(a, b):
    """a < b なら -1、a == b なら 0、a > b なら 1。"""
    na, pa = _parse(a)
    nb, pb = _parse(b)

    if na != nb:
        return _cmp(na, nb)

    # プレリリースは正式版より古い
    if pa and not pb:
        return -1
    if pb and not pa:
        return 1
    if not pa and not pb:
        return 0

    for ia, ib in zip(pa, pb):
        c = _cmp_ident(ia, ib)
        if c != 0:
            return c
    return _cmp(len(pa), len(pb))
