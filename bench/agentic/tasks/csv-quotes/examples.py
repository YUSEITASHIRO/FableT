# 公開例テスト — prompt.txt に明記された入出力例だけを実行可能にしたもの。
# これは隠しテスト(verify.py)ではない。課題文が既にエージェントへ与えている契約を、
# 強制検証ループ(run.ps1 の loop アーム)が機械的に確認するために使う。
# work ディレクトリをカレントにして実行する(verify.py と同じ方式)。
import sys

sys.path.insert(0, ".")
fails = []


def expect(name, fn, want):
    try:
        got = fn()
    except Exception as e:  # noqa: BLE001
        fails.append(f"{name}: 例外 {type(e).__name__}: {e}")
        return
    if got != want:
        fails.append(f"{name}: got {got!r}, want {want!r}")


try:
    from csvlite import parse_line
except Exception as e:  # noqa: BLE001
    print(f"FAIL: import できない: {type(e).__name__}: {e}")
    sys.exit(1)

# prompt.txt に明記された例のみ
expect("quoted comma", lambda: parse_line('a,"b,c",d'), ["a", "b,c", "d"])
expect("escaped quotes", lambda: parse_line('a,"he said ""hi""",b'), ["a", 'he said "hi"', "b"])
expect("plain unquoted, spaces kept", lambda: parse_line("a, b ,c"), ["a", " b ", "c"])
expect("empty field", lambda: parse_line("a,,b"), ["a", "", "b"])
expect("trailing newline removed", lambda: parse_line("a,b\n"), ["a", "b"])

try:
    parse_line('a,"unterminated')
    fails.append("unterminated: ValueError が送出されなかった")
except ValueError:
    pass
except Exception as e:  # noqa: BLE001
    fails.append(f"unterminated: ValueError 以外が飛んだ: {type(e).__name__}: {e}")

if fails:
    print("FAIL (公開例):")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("PASS: 公開例をすべて満たしている")
