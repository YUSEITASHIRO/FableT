"""簡易 INI パーサ(標準ライブラリの configparser は使わない方針)。"""


def parse_ini(text):
    """INI 形式の文字列を {セクション: {キー: 値}} に分解する。"""
    result = {}
    section = None
    for line in text.splitlines():
        if line.startswith("["):
            section = line.strip("[]")
            result[section] = {}
        else:
            key, value = line.split("=")
            result[section][key] = value
    return result
