"""依存関係の解決。"""


def resolve_order(deps):
    """{ノード: [依存しているノード, ...]} を受け取り、依存を先に置いた順序を返す。"""
    order = []
    visited = set()

    def visit(node):
        if node in visited:
            return
        visited.add(node)
        for dep in deps.get(node, []):
            visit(dep)
        order.append(node)

    for node in deps:
        visit(node)

    return order
