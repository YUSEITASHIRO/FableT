"""呼び出し失敗の分類。"""


class TransientError(Exception):
    """一時的な失敗。再試行すれば成功しうる(ネットワーク瞬断、503 など)。"""


class FatalError(Exception):
    """恒久的な失敗。何度試しても同じ(認証エラー、400 など)。"""
