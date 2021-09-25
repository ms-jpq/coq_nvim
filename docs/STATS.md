## How to interpret statistics

```viml
:COQstats
```
![statistics.img](https://raw.githubusercontent.com/ms-jpq/coq.artifacts/artifacts/preview/stats.gif)

### Is this the actual response speed for each keystroke

No, these measure the response speed of the sources.

- Like good GUI programs, `coq.nvim` frees up the "UI Thread" as much as possible, and does work asynchronously.

- When the sources are calculating, you are free to type around already.

- There are also optimizations in-place so that many keystrokes do not trigger unnecessary requests to sources.

- There is a near constant (and minor) overhead for each keystroke, the overhead is only profiled by running `coq.nvim` in debug mode.

### Q0, 50, 95, 100?

Mean `min`, `median`, `1 in 20`, `max`, respectively.

Without assuming any statistical distribution:

**`Q50` is a more robust measure than `avg`**, and `Q95` is a decent measure of a common `bad` value.

### What does each column mean?

#### Interrupted

`coq.nvim` uses collaborative multitasking, and will cancel incomplete completion requests, if they become unnecessary.

Ideally, all sources should have similar interrupted statistics, which would imply all sources are similarly fast.

If some sources have many interrupted vis a vis the rest, it implies that those sources are slower than others.

#### Inserted

Simple count of how many insertions are from this source.

#### Duration

This is a misleading statistic for several reasons.

The price `coq.nvim` pays for being collaboratively scheduled is that sources are executed concurrently.

This means that one slow source can slow down all sources, with the exception being `LSP`, and `T9`, whose results are mostly calculated by other processes.

This also means that the time spans are **not additive**. Say five sources each take 40ms to complete, the total execution time is 40ms, not 200ms.

The overall duration is `min(timeout, max(<durations>)) + <constant overhead>`.
