"""失敗するかもしれない呼び出しを再試行するユーティリティ。"""

import time

from errors import FatalError, TransientError


def call_with_retry(fn, max_attempts=3, base_delay=1.0, sleep=time.sleep):
    """fn() を呼ぶ。失敗したら指数バックオフで再試行する。

    sleep は差し替え可能(テスト用)。
    """
    attempt = 0
    while True:
        attempt += 1
        sleep(base_delay * (2 ** attempt))
        try:
            return fn()
        except Exception:
            if attempt >= max_attempts:
                raise
