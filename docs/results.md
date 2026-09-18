# Results and deduplication

The snippets on this page assume:

```python
from uuid import UUID

from smallage import CollectingEnqueuer
from smallage.litestar import TaskRegistry

registry = TaskRegistry()


@registry.task
async def reindex(doc_id: UUID) -> None: ...


@registry.task
async def charge(invoice_id: UUID) -> None: ...


registry.bind({}, enqueuer=CollectingEnqueuer())
```

## Results are asked for

Most work is enqueued and forgotten. Keeping an outcome for every job would be a
key and a TTL spent on nobody, so a result is opt-in per job:

```python
job_id = await reindex.enqueue(doc_id=doc_id, result_ttl_ms=300_000)
```

`enqueue` returns the job id whether or not a result was requested — that is
what an outcome is looked up by.

<!-- docs-test: skip -- a result store is configured by the plugin at startup -->
```python
result = await registry.result(job_id)
if result is not None and result.ok:
    ...
```

Waiting blocks rather than polls. The outcome is written to a key with a token
pushed to a list beside it; a waiter that wakes puts the token back, so several
waiters on one job all get it:

```python
result = await store.wait(job_id, timeout_s=30)
```

`wait` returns `None` on timeout.

## Failures are recorded too

A job that exhausts its retries records the failure before it is buried.
Otherwise a caller waiting on a job that will never finish blocks until its own
timeout and learns nothing about why. A job that is merely being retried records
nothing — it is not over, and the waiter should keep waiting.

```python
result = await store.wait(job_id, timeout_s=30)
if result and not result.ok:
    log.error("job failed: %s", result.error)
```

Only `bytes` travel as a result value. Anything richer is the application's own
encoding decision.

## Deduplication

Delivery is at-least-once and no protocol change makes it otherwise, so an
application that must not repeat a side effect needs a gate it controls:

```python
await charge.enqueue(invoice_id=invoice_id, dedup=f"charge:{invoice_id}")
```

The worker claims the key immediately before calling the handler. The check sits
there because that is the only point a duplicate can still be stopped — by the
time a worker has the job, both copies are already in the stream.

The key has two states, and its owner is the job id:

- **claimed** while the job is being attempted. The same job passes its own
  claim, so a retry after a failure, or a reclaim after its worker died, runs as
  it should. A different job with the same key is skipped and acknowledged, not
  failed.
- **done** once the handler has returned. Nothing passes it, including the job
  that wrote it: a worker that finished and died before its ack brings the same
  job id back, and that copy is skipped.

A job that ends in the dead letter queue releases its claim, so replaying it is
not turned away for the rest of the window. The one gap left is a worker dying
between the handler returning and the key being marked done: that job runs
again. Narrowing it further takes a transaction shared with the side effect,
which only the application has.

The window is `WorkerConfig.dedup_ttl_ms`, one day by default. Choose it to
cover the longest period over which a repeat would be wrong, not the longest a
job takes.
