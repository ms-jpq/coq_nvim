## How to interpret statistics

```viml
:COQstats
```

### Is this the actual response speed for each keystroke

No, these measure the response speed of the sources.

- Like good GUI programs, `coq.nvim` frees up the "UI Thread" as much as possible, and does work asynchronously.

- When the sources are calculating, you are free to type around already.

- There are also optimizations inplace so that many keystrokes do not trigger unnecessary requests to sources.

- There is a near constant (and minor) overhead for each keystroke, the overhead is only profiled by running `coq.nvim` in debug mode.


### Avg, Q0, 50, 90, 100?

- Avg: self explanatory

- Q0: min

- Q50: 50% of results are better / worse than this

- Q90: 90% of results are better / worse than this

- Q100: max



### What does each column mean?

#### Interrupted

`coq.nvim` uses collaborative multitasking, and will cancel incomplete completion requests, if they are unnecessary.

Ideally, all sources should have similar interrupted statistics, which would imply all sources are similarly fast.

If some sources have many interrupted vis a vis the rest, it implies that those sources are slower than others.

#### Inserted

Simple count of how many insertions are from this source.

#### Duration

This is a misleading statistic for several reasons.



, the price `coq.nvim` pays for being collaboratively scheduled is that sources are executed interleavingly.



This means that one slow source can slow down all sources, with the exception being `LSP`, whose results is mostly calculated by other processes.

