"""URL のクエリ文字列をパースする(標準ライブラリの urllib は使わない方針)。"""


def parse_query(qs):
    """"a=1&b=2" のような文字列を辞書に分解する。"""
    result = {}
    for pair in qs.split("&"):
        key, value = pair.split("=")
        result[key] = value
    return result
