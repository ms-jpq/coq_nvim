# Performance

My objective from the beginning was to write something that can keep up with **every keystroke**, and generate _good results_ within **tens of milliseconds**.

And quite a bit of optimization has gone into making `coq.nvim` in accordance with that goal.

## Responsiveness

### Moving heavy lifting off of UI thread

self explanatory

### Incremental completion

On the python end, this is done via collaborative multi-tasking similar to [React's new concurrent mode](https://reactjs.org/docs/concurrent-mode-intro.html).

Instead of projecting the entirety of the result-set, rows are computed incrementally, in an interruptible fashion.

More interestingly, on the SQLite end:

`coq.nvim` launches half a dozen independent in memory SQLite virtual machines in their own threads.

This is done in part because it allows the SQLite VMs to each progress without having to block on unrelated operations.

### Soft Deadlines

At the end of day, I can make `coq.nvim` as fast as possible, but the `LSP` servers can still take forever to respond.

Normally, this is handled by a deadline, where If the `LSP` servers do not respond in time, other completion sources will be shown after a timeout.

Actually this is a lie, the timeout is only in effect if other sources find matches, if no matches are found before the deadline. Each source is polled for completion incrementally until they are all done, or some matches are found from one of the sources.

## Speed

In general, there are two ways to make a program faster.

### Pick a faster language

The storage & query engine in `coq.nvim` is written in SQL.

SQLite comes natively with python, and it is about as battle tested as anything out there.

### Write code that does less work

This is the interesting part. We all know the _**data structures and algorithms**_ spiel. This is in part handled by SQLite.

But that is not enough!

#### Flow Control

In a naive network with limited capacity, if the rate of ingress exceeds the capacity of egress, the network will eventually enter a doom spiral, where the incoming traffic piling up in congestion.

For `coq.nvim`, this issue is solved akin to how the linux packet queue [`tc-cake`](https://man7.org/linux/man-pages/man8/tc-cake.8.html) works on a basic level for TCP traffic sharping.

Dropping from the front of the queue: That's it!

Since TCP already ensures packet ordering on a protocol level, this is totally safe to do!

Likewise, for `coq.nvim`, user events that have guaranteed ordering are basically treated the same way.

#### Cancel Culture

If something is outdated, we cancel it.

For every keystroke, `coq.nvim` will require 10s of ms worth of work. What happens if you hold down the keyboard? With flow control, you might assume that time it takes is (10s of ms) \* 2.

Wrong.

It is actually (minor overhead of cancellation + 10s of ms). The heavy lifting code of `coq.nvim` is executed collaboratively, via generator functions. Basically at every implicit or explicit `yield` in the codebase, `coq.nvim` will be able to interrupt unnecessary work.

It goes further than that.

Not only does work in python get cancelled, the same thing is done for SQLite too. Each SQLite VM have its own lock protecting the critical operations, and outside of those locked sections, interrupts are fired into the VMs and terminate execution.

## Background Processing

Even after the results are shown to the user, work can still be done!

As a consequence of being able to resume and interrupt most parts of the data pipeline, it then becomes possible to process and shove unused results into the cache, so on the next keystroke, more results are instantly available.
