-- Give up a claim whose job will not run again here: it went to the DLQ.
--
-- Keeping the key would turn the replay away for the rest of the window. A key
-- marked done is never released -- that work happened.
--
-- KEYS[1]  dedup key
-- ARGV[1]  owner (job id)
-- returns  1 if released, 0 otherwise

if redis.call('GET', KEYS[1]) ~= 'run:' .. ARGV[1] then
    return 0
end
redis.call('DEL', KEYS[1])
return 1
