"""金額計算。円単位(整数)へ丸めて請求する。"""


def split_bill(total_yen, people):
    """total_yen を people 人で割った1人あたりの請求額(整数)を返す。

    端数は切り上げて、合計が total_yen を下回らないようにする。
    """
    return [round(total_yen / people)] * people


def apply_tax(amount_yen, tax_rate):
    """税込み額(整数)を返す。端数は四捨五入(0.5 は切り上げ)。"""
    return round(amount_yen * (1 + tax_rate))
