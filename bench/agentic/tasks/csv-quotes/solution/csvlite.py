"""参照解答(エージェントには見せない)。"""


def parse_line(line):
    """CSV の1行をフィールドのリストに分解する。引用符内のカンマは区切らない。"""
    line = line.rstrip("\n")
    fields = []
    field = []
    i = 0
    n = len(line)

    while i < n:
        ch = line[i]
        if ch == '"':
            i += 1
            closed = False
            while i < n:
                if line[i] == '"':
                    if i + 1 < n and line[i + 1] == '"':
                        field.append('"')
                        i += 2
                        continue
                    closed = True
                    i += 1
                    break
                field.append(line[i])
                i += 1
            if not closed:
                raise ValueError(f"引用符が閉じられていない: {line!r}")
        elif ch == ",":
            fields.append("".join(field))
            field = []
            i += 1
        else:
            field.append(ch)
            i += 1

    fields.append("".join(field))
    return fields
