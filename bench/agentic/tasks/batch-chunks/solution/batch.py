"""参照解答(エージェントには見せない)。"""


def chunk(records, size):
    """records を size 件ずつに分割する。"""
    if size < 1:
        raise ValueError(f"size は 1 以上: {size}")
    return [records[i:i + size] for i in range(0, len(records), size)]


def chunk_by_bytes(records, max_bytes, sizeof):
    """合計が max_bytes を超えないようにバッチへ分割する。"""
    if max_bytes < 1:
        raise ValueError(f"max_bytes は 1 以上: {max_bytes}")

    batches = []
    current = []
    total = 0

    for r in records:
        size = sizeof(r)

        if size > max_bytes:
            if current:
                batches.append(current)
                current = []
                total = 0
            batches.append([r])  # 単独で超えるものは単独バッチ
            continue

        if current and total + size > max_bytes:
            batches.append(current)
            current = []
            total = 0

        current.append(r)
        total += size

    if current:
        batches.append(current)

    return batches
