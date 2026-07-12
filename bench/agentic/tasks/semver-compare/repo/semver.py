"""セマンティックバージョンの比較。"""


def compare(a, b):
    """a < b なら -1、a == b なら 0、a > b なら 1 を返す。"""
    pa = [int(x) for x in a.split(".")]
    pb = [int(x) for x in b.split(".")]
    if pa < pb:
        return -1
    if pa > pb:
        return 1
    return 0
