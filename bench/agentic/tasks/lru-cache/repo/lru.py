"""容量制限つきキャッシュ。"""


class LRUCache:
    """最も長く使われていない要素から捨てるキャッシュ。"""

    def __init__(self, capacity):
        self.capacity = capacity
        self._data = {}

    def get(self, key, default=None):
        """値を返す。無ければ default。"""
        if key not in self._data:
            return default
        return self._data[key]

    def put(self, key, value):
        """値を入れる。容量を超えたら最も古いものを捨てる。"""
        self._data[key] = value
        if len(self._data) > self.capacity:
            oldest = next(iter(self._data))
            del self._data[oldest]

    def __len__(self):
        return len(self._data)
