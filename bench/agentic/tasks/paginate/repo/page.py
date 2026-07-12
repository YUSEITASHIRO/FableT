"""一覧のページ分割。"""


def paginate(items, page, per_page):
    """1始まりの page 番号で items を切り出して返す。"""
    start = page * per_page
    return items[start:start + per_page]


def page_count(total, per_page):
    """総ページ数を返す。"""
    return total // per_page
