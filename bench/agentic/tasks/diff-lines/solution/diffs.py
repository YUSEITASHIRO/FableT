"""参照解答(エージェントには見せない)。LCS ベースの行差分。"""


def diff(old, new):
    """行ごとの差分 [(op, line), ...] を返す。op は "=" / "-" / "+"。"""
    a = old.splitlines()
    b = new.splitlines()
    n, m = len(a), len(b)

    # lcs[i][j] = a[i:] と b[j:] の最長共通部分列の長さ
    lcs = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n - 1, -1, -1):
        for j in range(m - 1, -1, -1):
            if a[i] == b[j]:
                lcs[i][j] = lcs[i + 1][j + 1] + 1
            else:
                lcs[i][j] = max(lcs[i + 1][j], lcs[i][j + 1])

    result = []
    i = j = 0
    while i < n and j < m:
        if a[i] == b[j]:
            result.append(("=", a[i]))
            i += 1
            j += 1
        elif lcs[i + 1][j] >= lcs[i][j + 1]:
            result.append(("-", a[i]))
            i += 1
        else:
            result.append(("+", b[j]))
            j += 1

    result.extend(("-", line) for line in a[i:])
    result.extend(("+", line) for line in b[j:])
    return result
