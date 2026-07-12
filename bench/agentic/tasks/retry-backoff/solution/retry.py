"""参照解答(エージェントには見せない)。"""

import time

from errors import FatalError, TransientError  # noqa: F401


def call_with_retry(fn, max_attempts=3, base_delay=1.0, sleep=time.sleep):
    """fn() を呼ぶ。TransientError のみ指数バックオフで再試行する。"""
    for attempt in range(1, max_attempts + 1):
        try:
            return fn()
        except TransientError:
            if attempt >= max_attempts:
                raise
            sleep(base_delay * (2 ** (attempt - 1)))
