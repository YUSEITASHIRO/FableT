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
    from slug import slugify, unique_slug
except Exception as e:  # noqa: BLE001
    print(f"FAIL: import できない: {type(e).__name__}: {e}")
    sys.exit(1)

expect("punctuation", lambda: slugify("Hello, World!"), "hello-world")
expect("trim and collapse", lambda: slugify("  --Hello--  World  "), "hello-world")
expect("already slug", lambda: slugify("hello-world"), "hello-world")
expect("digits kept", lambda: slugify("Top 10 Tips"), "top-10-tips")

for bad in ("!!!", "   ", ""):
    try:
        slugify(bad)
        fails.append(f"empty result {bad!r}: ValueError が送出されなかった")
    except ValueError:
        pass
    except Exception as e:  # noqa: BLE001
        fails.append(f"empty result {bad!r}: ValueError 以外が飛んだ: {type(e).__name__}")

expect("no collision", lambda: unique_slug("hi", set()), "hi")
expect("one collision", lambda: unique_slug("hi", {"hi"}), "hi-2")
expect("two collisions", lambda: unique_slug("hi", {"hi", "hi-2"}), "hi-3")
expect("many collisions", lambda: unique_slug("hi", {"hi", "hi-2", "hi-3", "hi-4"}), "hi-5")
expect("collision after slugify", lambda: unique_slug("Hi!", {"hi"}), "hi-2")

existing = {"hi"}
unique_slug("hi", existing)
if existing != {"hi"}:
    fails.append(f"existing が書き換えられた: {existing!r}")

if fails:
    print("FAIL")
    for f in fails:
        print("  -", f)
    sys.exit(1)
print("PASS: all checks")
