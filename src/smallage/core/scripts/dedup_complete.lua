-- Mark a deduplicated job done.
--
-- Only our own claim is overwritten. An absent key means the claim lapsed while
-- the handler ran; the work still happened, so it is recorded. A key held by
-- another owner is theirs and is left alone.
--
-- KEYS[1]  dedup key
-- ARGV[1]  owner (job id)
-- ARGV[2]  ttl, ms
-- returns  1 if marked, 0 if the key belongs to someone else

local held = redis.call('GET', KEYS[1])
if held and held ~= 'run:' .. ARGV[1] then
    return 0
end
redis.call('SET', KEYS[1], 'done:' .. ARGV[1], 'PX', ARGV[2])
return 1
