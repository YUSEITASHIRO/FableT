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
    from semver import compare
except Exception as e:  # noqa: BLE001
    print(f"FAIL: import できない: {type(e).__name__}: {e}")
    sys.exit(1)

expect("numeric basic", lambda: compare("1.2.3", "1.2.4"), -1)
expect("numeric equal", lambda: compare("1.2.3", "1.2.3"), 0)
expect("numeric greater", lambda: compare("2.0.0", "1.9.9"), 1)
expect("numeric not lexical", lambda: compare("1.10.0", "1.9.0"), 1)
expect("prerelease < release", lambda: compare("1.0.0-rc.1", "1.0.0"), -1)
expect("release > prerelease", lambda: compare("1.0.0", "1.0.0-rc.1"), 1)
expect("prerelease numeric order", lambda: compare("1.0.0-rc.2", "1.0.0-rc.10"), -1)
expect("prerelease equal", lambda: compare("1.0.0-rc.1", "1.0.0-rc.1"), 0)
expect("numeric ident < alnum ident", lambda: compare("1.0.0-1", "1.0.0-alpha"), -1)
expect("prerelease fewer fields", lambda: compare("1.0.0-rc", "1.0.0-rc.1"), -1)

for bad in ("1.2", "1.2.x", "abc"):
    try:
        compare(bad, "1.0.0")
        fails.append(f"invalid {bad!r}: ValueError が送出されなかった")
    except ValueError:
        pass
    except Exception as e:  # noqa: BLE001
        fails.append(f"invalid {bad!r}: ValueError 以外が飛んだ: {type(e).__name__}")

if fails:
    print("FAIL")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("PASS: all 13 checks")
