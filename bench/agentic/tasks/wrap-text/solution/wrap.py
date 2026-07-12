"""参照解答(エージェントには見せない)。"""


def wrap(text, width):
    """width 文字以内の行に折り返す。単語の途中では切らない。"""
    if width < 1:
        raise ValueError(f"width は 1 以上: {width}")

    words = text.split()
    if not words:
        return []

    lines = []
    current = words[0]

    for word in words[1:]:
        if len(current) + 1 + len(word) <= width:
            current = f"{current} {word}"
        else:
            lines.append(current)
            current = word

    lines.append(current)
    return lines
