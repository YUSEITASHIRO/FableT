"""2つのテキストの行差分。"""


def diff(old, new):
    """行ごとの差分を返す。

    戻り値: [(op, line), ...]。op は "=" (同じ) / "-" (削除) / "+" (追加)。
    共通する行はできるだけ "=" として残す(最長共通部分列)。
    """
    old_lines = old.splitlines()
    new_lines = new.splitlines()

    result = []
    for i in range(max(len(old_lines), len(new_lines))):
        o = old_lines[i] if i < len(old_lines) else None
        n = new_lines[i] if i < len(new_lines) else None
        if o == n:
            result.append(("=", o))
        else:
            if o is not None:
                result.append(("-", o))
            if n is not None:
                result.append(("+", n))
    return result
