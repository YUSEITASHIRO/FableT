"""参照解答(エージェントには見せない)。"""


def parse_ini(text):
    """INI 形式を {セクション: {キー: 値}} に分解する。"""
    result = {}
    section = None

    for raw in text.splitlines():
        line = raw.strip()

        if not line or line.startswith("#") or line.startswith(";"):
            continue

        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip()
            result.setdefault(section, {})  # 再出現は追記
            continue

        if "=" not in line:
            raise ValueError(f"'=' の無い行: {raw!r}")

        if section is None:
            raise ValueError(f"セクションの外にキーがある: {raw!r}")

        key, _, value = line.partition("=")
        result[section][key.strip()] = value.strip()

    return result
