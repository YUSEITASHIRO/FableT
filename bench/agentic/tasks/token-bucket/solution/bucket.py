"""参照解答(エージェントには見せない)。"""


class TokenBucket:
    def __init__(self, capacity, rate, now=0.0):
        self.capacity = capacity
        self.rate = rate
        self.tokens = float(capacity)
        self.updated_at = now

    def allow(self, now, cost=1):
        if cost > self.capacity:
            raise ValueError(f"cost({cost}) が capacity({self.capacity}) を超えている")

        elapsed = now - self.updated_at
        if elapsed > 0:
            self.tokens = min(self.capacity, self.tokens + elapsed * self.rate)
        self.updated_at = max(self.updated_at, now)

        if self.tokens >= cost:
            self.tokens -= cost
            return True
        return False
