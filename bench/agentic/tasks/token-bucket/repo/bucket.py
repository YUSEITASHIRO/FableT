"""トークンバケットによるレート制限。"""


class TokenBucket:
    """capacity 個まで貯まり、毎秒 rate 個ずつ補充されるバケット。"""

    def __init__(self, capacity, rate, now=0.0):
        self.capacity = capacity
        self.rate = rate
        self.tokens = capacity
        self.updated_at = now

    def allow(self, now, cost=1):
        """今 cost 個消費してよいか。よければ True を返し、実際に消費する。"""
        elapsed = now - self.updated_at
        self.tokens = self.tokens + elapsed * self.rate
        self.updated_at = now

        if self.tokens >= cost:
            self.tokens -= cost
            return True
        return False
