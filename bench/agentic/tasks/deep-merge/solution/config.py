"""参照解答(エージェントには見せない)。"""

import copy


def merge(base, override):
    """base に override を重ねた新しい辞書を返す。None は削除を意味する。"""
    result = copy.deepcopy(base)

    for key, value in override.items():
        if value is None:
            result.pop(key, None)
            continue

        current = result.get(key)
        if isinstance(current, dict) and isinstance(value, dict):
            result[key] = merge(current, value)
        else:
            result[key] = copy.deepcopy(value)

    return result
