"""参照解答(エージェントには見せない)。"""

import re


def slugify(title):
    """小文字・ハイフン区切りのスラッグ。英数字とハイフン以外は除去する。"""
    s = title.lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    s = re.sub(r"-+", "-", s).strip("-")

    if not s:
        raise ValueError(f"スラッグが空になる: {title!r}")
    return s


def unique_slug(title, existing):
    """existing と衝突しないスラッグ。衝突する限り連番を増やす。"""
    slug = slugify(title)
    if slug not in existing:
        return slug

    n = 2
    while f"{slug}-{n}" in existing:
        n += 1
    return f"{slug}-{n}"
