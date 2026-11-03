-- Limitador por "cubeta de fichas". Lógica pura: el llamador indica la hora actual.
local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(perSecond, burst)
    return setmetatable({
        PerSecond = perSecond,
        Burst = burst or perSecond,
        Buckets = {},
    }, RateLimiter)
end

function RateLimiter:Allow(key, now)
    local bucket = self.Buckets[key]
    if not bucket then
        bucket = {Tokens = self.Burst, Time = now}
        self.Buckets[key] = bucket
    end

    bucket.Tokens = math.min(self.Burst, bucket.Tokens + (now - bucket.Time) * self.PerSecond)
    bucket.Time = now

    if bucket.Tokens < 1 then
        return false
    end

    bucket.Tokens -= 1
    return true
end

function RateLimiter:Forget(key)
    self.Buckets[key] = nil
end

return RateLimiter
