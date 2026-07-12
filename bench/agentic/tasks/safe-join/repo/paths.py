"""アップロードされたファイル名を保存先へ解決する。"""

import os


def safe_join(base_dir, user_path):
    """base_dir の外に出ないことを保証して、絶対パスを返す。

    base_dir の外に出ようとする入力は ValueError。
    """
    joined = os.path.join(base_dir, user_path)
    if not joined.startswith(base_dir):
        raise ValueError(f"base_dir の外に出ている: {user_path!r}")
    return joined
