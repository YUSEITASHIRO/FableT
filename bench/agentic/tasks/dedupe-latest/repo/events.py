"""イベントの重複排除。"""


def dedupe(events):
    """同じ key のイベントは最新(ts が最大)のものだけ残す。

    events: [{"key": str, "ts": int, ...}, ...]
    戻り値: 元のリストでの最初の出現順を保った、重複排除済みのリスト。
    """
    seen = {}
    for e in events:
        if e["key"] not in seen:
            seen[e["key"]] = e
    return list(seen.values())
