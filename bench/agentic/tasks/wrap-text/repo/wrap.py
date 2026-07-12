"""テキストの折り返し(標準ライブラリの textwrap は使わない方針)。"""


def wrap(text, width):
    """text を width 文字以内の行に折り返して、行のリストを返す。"""
    lines = []
    line = ""
    for word in text.split(" "):
        line = line + " " + word
        if len(line) >= width:
            lines.append(line)
            line = ""
    return lines
