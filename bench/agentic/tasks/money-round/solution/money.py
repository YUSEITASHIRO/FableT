"""参照解答(エージェントには見せない)。"""

from decimal import ROUND_HALF_UP, Decimal


def split_bill(total_yen, people):
    """合計がちょうど total_yen になるよう分割する。端数は先頭から負担。"""
    if people <= 0:
        raise ValueError(f"people は 1 以上でなければならない: {people}")
    if total_yen < 0:
        raise ValueError(f"total_yen は 0 以上でなければならない: {total_yen}")

    base, remainder = divmod(total_yen, people)
    return [base + 1 if i < remainder else base for i in range(people)]


def apply_tax(amount_yen, tax_rate):
    """税込み額を四捨五入(0.5 は切り上げ)した整数で返す。"""
    amount = Decimal(str(amount_yen)) * (Decimal("1") + Decimal(str(tax_rate)))
    return int(amount.quantize(Decimal("1"), rounding=ROUND_HALF_UP))
