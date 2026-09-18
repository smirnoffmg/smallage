-- Take the right to run a deduplicated job, or find it already taken.
--
-- A key moves through two states: `run:<owner>` while the job is being attempted,
-- `done:<owner>` once a handler has returned. The owner is the job id, so a
-- retry or a reclaim of the same job passes its own `run` claim, and nothing
-- passes `done` -- not even the job that wrote it, which is exactly the copy a
-- lost ack brings back.
--
-- KEYS[1]  dedup key
-- ARGV[1]  owner (job id)
-- ARGV[2]  ttl, ms
-- returns  1 if the caller may run the job, 0 otherwise

local held = redis.call('GET', KEYS[1])
if not held then
    redis.call('SET', KEYS[1], 'run:' .. ARGV[1], 'PX', ARGV[2])
    return 1
end
if held == 'run:' .. ARGV[1] then
    -- Retries can outlast the window; the claim must not lapse between them.
    redis.call('PEXPIRE', KEYS[1], ARGV[2])
    return 1
end
return 0
