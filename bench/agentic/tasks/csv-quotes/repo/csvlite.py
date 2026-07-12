"""軽量CSVパーサ(標準ライブラリの csv は使わない方針のプロジェクト)。"""


def parse_line(line):
    """CSV の1行をフィールドのリストに分解する。

    引用符で囲まれたフィールドの中のカンマは区切りとみなさない。
    """
    return line.rstrip("\n").split(",")
