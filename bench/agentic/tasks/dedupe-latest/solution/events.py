"""参照解答(エージェントには見せない)。"""


def dedupe(events):
    """同じ key は ts が最大のものを残す。並びは初出順、同点は後勝ち。"""
    best = {}
    order = []

    for e in events:
        if "key" not in e or "ts" not in e:
            raise ValueError(f"key と ts が必要: {e!r}")
        key = e["key"]
        if key not in best:
            order.append(key)
            best[key] = e
        elif e["ts"] >= best[key]["ts"]:  # 同点は後勝ち
            best[key] = e

    return [best[k] for k in order]
