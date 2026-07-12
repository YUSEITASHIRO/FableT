"""参照解答(エージェントには見せない)。"""

import math


def paginate(items, page, per_page):
    """1始まりの page 番号で items を切り出す。"""
    if page < 1:
        raise ValueError(f"page は 1 以上: {page}")
    if per_page < 1:
        raise ValueError(f"per_page は 1 以上: {per_page}")

    start = (page - 1) * per_page
    return items[start:start + per_page]


def page_count(total, per_page):
    """端数を切り上げた総ページ数。"""
    if per_page < 1:
        raise ValueError(f"per_page は 1 以上: {per_page}")
    return math.ceil(total / per_page)
