"""参照解答(エージェントには見せない)。"""

import os


def safe_join(base_dir, user_path):
    """base_dir 配下の正規化された絶対パスを返す。外に出る入力は ValueError。"""
    base = os.path.abspath(base_dir)

    if os.path.isabs(user_path):
        raise ValueError(f"絶対パスは受け付けない: {user_path!r}")

    target = os.path.abspath(os.path.join(base, user_path))

    if target == base:
        raise ValueError("base_dir 自身は指定できない")

    # 兄弟ディレクトリ(/srv/data-evil)を弾くため、区切り文字まで含めて比較する
    if not target.startswith(base + os.sep):
        raise ValueError(f"base_dir の外に出ている: {user_path!r}")

    return target
