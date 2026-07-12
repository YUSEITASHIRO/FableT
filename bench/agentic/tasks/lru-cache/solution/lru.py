"""参照解答(エージェントには見せない)。"""

from collections import OrderedDict

_MISSING = object()


class LRUCache:
    def __init__(self, capacity):
        if capacity <= 0:
            raise ValueError(f"capacity は 1 以上でなければならない: {capacity}")
        self.capacity = capacity
        self._data = OrderedDict()

    def get(self, key, default=None):
        if key not in self._data:
            return default
        self._data.move_to_end(key)
        return self._data[key]

    def put(self, key, value):
        if key in self._data:
            self._data.move_to_end(key)
        self._data[key] = value
        if len(self._data) > self.capacity:
            self._data.popitem(last=False)

    def __len__(self):
        return len(self._data)
