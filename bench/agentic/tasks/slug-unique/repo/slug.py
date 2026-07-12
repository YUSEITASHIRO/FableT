"""記事タイトルから URL スラッグを作る。"""

import re


def slugify(title):
    """タイトルを小文字・ハイフン区切りのスラッグにする。"""
    return re.sub(r"\s+", "-", title.lower())


def unique_slug(title, existing):
    """既存のスラッグ集合と衝突しないスラッグを返す。"""
    slug = slugify(title)
    if slug in existing:
        slug = slug + "-2"
    return slug
