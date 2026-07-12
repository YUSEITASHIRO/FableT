"""設定のマージ。既定値にユーザー設定を重ねる。"""


def merge(base, override):
    """base に override を重ねた新しい辞書を返す。"""
    result = base
    for key, value in override.items():
        result[key] = value
    return result
