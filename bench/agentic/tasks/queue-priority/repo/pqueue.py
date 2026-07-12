"""優先度つきジョブキュー。"""

import heapq


class JobQueue:
    """優先度が小さいものから取り出すキュー。同じ優先度なら先入れ先出し。"""

    def __init__(self):
        self._heap = []

    def push(self, priority, job):
        heapq.heappush(self._heap, (priority, job))

    def pop(self):
        """次に処理すべきジョブを返す。空なら None。"""
        return heapq.heappop(self._heap)[1]

    def __len__(self):
        return len(self._heap)
