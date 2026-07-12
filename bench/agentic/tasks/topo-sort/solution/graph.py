"""参照解答(エージェントには見せない)。"""


class CycleError(ValueError):
    """循環依存があるため順序を決められない。"""


def resolve_order(deps):
    """依存を先に置いた順序を返す。循環があれば CycleError。"""
    order = []
    done = set()
    in_progress = set()

    def visit(node):
        if node in done:
            return
        if node in in_progress:
            raise CycleError(f"循環依存: {node}")
        in_progress.add(node)
        for dep in deps.get(node, []):
            visit(dep)
        in_progress.discard(node)
        done.add(node)
        order.append(node)

    for node in deps:
        visit(node)

    return order
