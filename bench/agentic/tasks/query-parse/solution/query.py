"""参照解答(エージェントには見せない)。"""

_HEX = "0123456789abcdefABCDEF"


def _unquote(s):
    """パーセントデコード + '+' をスペースに。UTF-8 として解釈する。"""
    out = bytearray()
    i = 0
    n = len(s)
    while i < n:
        ch = s[i]
        if ch == "+":
            out.append(0x20)
            i += 1
        elif ch == "%":
            if i + 2 >= n or s[i + 1] not in _HEX or s[i + 2] not in _HEX:
                raise ValueError(f"不正なパーセントエンコード: {s[i:i + 3]!r}")
            out.append(int(s[i + 1:i + 3], 16))
            i += 3
        else:
            out.extend(ch.encode("utf-8"))
            i += 1
    return out.decode("utf-8")


def parse_query(qs):
    """クエリ文字列を辞書に分解する。重複キーはリストにまとめる。"""
    if qs.startswith("?"):
        qs = qs[1:]
    if not qs:
        return {}

    result = {}
    for pair in qs.split("&"):
        if not pair:
            continue
        key, sep, value = pair.partition("=")
        key = _unquote(key)
        value = _unquote(value) if sep else ""

        if key in result:
            if isinstance(result[key], list):
                result[key].append(value)
            else:
                result[key] = [result[key], value]
        else:
            result[key] = value

    return result
