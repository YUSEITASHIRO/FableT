"""API へ送る前にレコードをバッチへ分割する。"""


def chunk(records, size):
    """records を size 件ずつのリストに分割して返す。"""
    result = []
    for i in range(0, len(records), size):
        result.append(records[i:i + size])
    return result


def chunk_by_bytes(records, max_bytes, sizeof):
    """合計サイズが max_bytes を超えないようにバッチへ分割する。

    sizeof(record) が1件のバイト数を返す。
    """
    batches = []
    current = []
    total = 0
    for r in records:
        current.append(r)
        total += sizeof(r)
        if total > max_bytes:
            batches.append(current)
            current = []
            total = 0
    return batches
