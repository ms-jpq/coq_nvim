# Performance

## Humans are slow

Humans are much slower than computers, therefore when we think about performance, we not only need to think about the cost to compute.

Below a certain threshold, **the cost to humans**, ie. reading and decision time will dominate most human computer interactions.

Therefore `coq.nvim` put a high degree of emphasis on providing not only fast completion times, but also [high quality fuzzy search](https://github.com/ms-jpq/coq_nvim/tree/coq/docs/FUZZY.md)

The fuzzy algorithms focus on **tolerance for typographical errors**, because humans are also error prone.

## Throughput vs latency

**Perceived performance** has much more to do with responsiveness rather than overall time elapsed.

At every level of `coq.nvim`, the design is to explicitly trade better throughput for better latency.

This is the same design decision behind many "fast" garbage collectors.

In broad strokes, this means making `coq.nvim` **concurrent**, which introduces costs to throughput, but enables **other optimizations** detailed below.

## SQLite

`coq.nvim` spins up over half a dozen independent SQLite VMs.

Not only are `sqlite3` VMs fast af due to `C`, and `btrees`, and countless hours of optimizations.

They also provide **even futher speed ups**, these will be elaborated futher in later parts of this document.

## Parallelism

There is this persistent myth that _cpython programs_ cannot take advantage of threading for non-io tasks.

In fact, _cpython code_ cannot run in parallel due to the [`GIL`](https://docs.python.org/3/c-api/init.html), but _c code_ can!

Assuming that they use the `Py_BEGIN_ALLOW_THREADS`, `Py_END_ALLOW_THREADS` macro, which releases the `GIL`.

**`sqlite3`** is one of those special stdlibs using these two macros, hence it is exploited to provide compute.

## Concurrency

`coq.nvim` takes advantage of concurrency via two main avenues:

1. Threading, for io and sqlite3

2. Coroutines, wherever possible

### Threading

Interestingly, `coq.nvim` actually **performs better**, when cpython is tuned to **switch threads more often**.

This is the opposite of many toy parallelism examples, whereby adding threads to a numerical problem slows down computation.

That is because `coq.nvim` is not just performing numerical compute.

When mixing io and compute, cpython introduces a deliberate and significant overhead to GIL acquisition.

Through GIL tuning, `coq.nvim` is able to mostly ignore this cost, but man, none of this is at all obvious.

### Coroutines

Coroutines are used ubiquitously in `coq.nvim`. Unlike pthreads, coroutines are scheduled collaboratively instead of preemptively.

In other words, instead of the runtime (ie. cpython, OS), `coq.nvim` **performs its own task scheduling**.

What it means is that `coq.nvim` has total control over both **when and _if_** tasks are scheduled.

Notably, **`sqlite3` VMs can be manually preempted**, and therefore we can schedule them like coroutines.

## Task scheduling

`coq.nvim` probably has the most **advanced task scheduler** out of any completion engine, not just for vim.

### Do nothing

By definition, the **fastest thing to do is to do nothing**.

Half the battle is figuring out what tasks can be optimizated away to nil.

#### Flow control

In a naive network with limited capacity, if the rate of ingress exceeds the capacity of egress, the network will eventually enter a doom spiral, where the incoming traffic piling up in congestion. This phenomenon is refered to as [bufferbloat](https://en.wikipedia.org/wiki/Bufferbloat)

For `coq.nvim`, this issue is solved akin to how the linux packet queue [`tc-cake`](https://man7.org/linux/man-pages/man8/tc-cake.8.html) works on a basic level for TCP traffic sharping.

Dropping from the front of the queue: That's it!

Since TCP already ensures packet ordering on a protocol level, this is totally safe to do!

Likewise, for `coq.nvim`, user events that have guaranteed ordering are basically treated the same way.

#### Cancel culture

If something is outdated, we cancel it.

_Manual preemption_ of not just coroutines but also `sqlite3`, takes place on each keystroke.

In fact, in `coq.nvim`: before any new tasks can be scheduled, all previous tasks must be interrupted.

### Background Processing

There is a certain down time between after completion results are shown to users, and the next keystroke.

`coq.nvim` takes advantage of this by processing additional rows of data into the `sqlite3` cache.

Naturally, these background tasks are also interruptable.

### Deadline optimization

`coq.nvim` can as fast as possible, but the `LSP` servers can still take forever to respond.

Normally, this is handled by a deadline, where If the `LSP` servers do not respond in time, other completion sources will be shown after a timeout.

Actually this is a lie, the timeout is only in effect if other sources find matches, if no matches are found before the deadline. Each source is polled for completion incrementally until they are all done, or some matches are found from one of the sources.

