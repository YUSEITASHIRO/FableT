"""参照解答(エージェントには見せない)。"""

import heapq
import itertools


class JobQueue:
    """優先度が小さいものから取り出す。同じ優先度なら FIFO。"""

    def __init__(self):
        self._heap = []
        self._counter = itertools.count()

    def push(self, priority, job):
        # 単調増加のカウンタをタイブレークに使う。job 自体は比較対象にしない。
        heapq.heappush(self._heap, (priority, next(self._counter), job))

    def pop(self):
        if not self._heap:
            return None
        return heapq.heappop(self._heap)[2]

    def __len__(self):
        return len(self._heap)
