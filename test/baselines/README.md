# Regression baselines

Recorded output of the headless hardware suites, one file per suite:

- `testbench.txt` — `bin/testbench` over the non-interactive PAL VICII
  tests in `vendor/VICE-testprogs/testbench/c64-testlist.in`. One
  tab-separated record per test, in testlist order: `id<TAB>PASS`, or
  `id<TAB>FAIL<TAB>detail` where detail is the `$D7FF` exit code and, for
  screenshot tests, the number of mismatched pixels.
- `testbench-cia.txt`, `testbench-interrupts.txt`, `testbench-irqdma.txt`,
  `testbench-cpu.txt` — the same runner over the testlist's `CIA/`,
  `interrupts/` and `CPU/` subtrees, one suite per subsystem so a change
  can be checked against the subtree it can actually move.
  `interrupts/irqdma` is a suite of its own because it accounts for nearly
  all of that subtree's runtime; `testbench-interrupts` is the rest. All
  four are `exitcode` tests: no reference screenshots, so detail is only
  the `$D7FF` code. Two testlist
  options decide what that code has to be — `expect:error` wants a
  non-zero code and `expect:timeout` wants no report at all, and a row that
  misses either way records `want=error` / `want=timeout` alongside the
  code it did get.
- `lorenz.txt` — `bin/lorenz` running the Wolfgang Lorenz suite off
  `Lorenz.d81`. The suite chains itself by LOADing one test after another,
  and those LOADs split the CHROUT transcript into one segment per test;
  each becomes the same tab-separated record, keyed by the loaded name,
  with detail holding whatever the test printed beyond its own name and
  `- ok`. A dump long enough to bury the row is cut to a digest. The
  closing `(suite)` row records how the chain ended, so a run that stops
  early is a changed verdict rather than a pile of missing rows. The full
  transcript is written to `tmp/lorenz/transcript.txt`, not tracked here.
- `sid.txt` — `bin/sidtests` over the SID testprogs in
  `vendor/VICE-testprogs/SID` that report through `$D7FF`. Same
  tab-separated record as the testbench, in the runner's test order:
  `name<TAB>PASS`, or `name<TAB>FAIL<TAB>detail` where detail is the
  `$D7FF` exit code, or `timeout` when the test never reported.
- `sid-8580.txt` — the same runner with `--sid 8580`, which builds the
  machine with an 8580 and runs the programs the testlist tags `sid-new`
  instead of the fixed 6581 list, each against its own testlist cycle
  budget. Same record format.

Every suite still fails tests. The baselines record those failures as they
stand, so the guard is the comparison, not the pass count.

    rake regression                     # run the push-to-main set, diff against these files
    rake regression:testbench           # one suite
    rake regression:testbench-cia       # an opt-in suite
    rake regression:record:testbench    # accept a reviewed diff
    rake regression:record              # re-record the push-to-main set

    rake "regression:record:testbench[spriteenable]"      # only the rows a filter matched
    rake "regression:record:testbench[sprite0,gfxfetch]"  # several filters, matched as a union
    rake "regression:record:lorenz[adcb]"                 # one test of the Lorenz chain
    rake "regression:record:lorenz[sein,adcb]"            # a stretch of it, first to last

Quote the task name: zsh treats the brackets as a glob.

A filtered re-record runs only the matching programs and splices their rows
into the existing baseline; every other row keeps the verdict it had, and
baseline order — which is what the `id#2` occurrence keys are derived from
— is preserved. A row the run gained is inserted beside the row it followed
in the run. Nothing is ever removed, so a test the vendored suite dropped
survives a partial record and is reported as `gone` by the next comparison;
clearing it out is a whole-suite record.

Filters are id substrings matched inside the suite's own subtree, so a
filter cannot reach rows belonging to another baseline, and one that
matches no test at all aborts before anything runs rather than recording an
empty no-op.

`lorenz` chains itself, one LOAD after the next, so its partial form takes
a stretch of the chain, not a set of filters: `[first]` or
`[first,last]`, both named as rows of `lorenz.txt`. The run resumes at the
row before `first` (`bin/lorenz --resume`), because a test loaded by hand
carries the READY prompt and the typed LOAD in its segment, and that
segment is thrown away. It stops as soon as the chain loads the test after
`last` (`--stop-after`), and the segment the stop cut short is left out too. Only
the rows from `first` to `last` are spliced in. The `(suite)` row records
how a whole chain ended, and a partial record never touches it. A name that
is not a row of the baseline, or a range given back to front, aborts before
anything runs. If the chain breaks before it reaches `last`, the rows it did
reach are recorded with a warning. `rake regression:lorenz` still runs only
the whole chain; a range record already reports what it changed before it
writes.

The testbench runs forks over four shards by default — each test boots its
own machine, so they are independent — and merges the per-test records back
into testlist order. `SHARDS=8 rake regression:testbench` or
`ruby --yjit bin/testbench --shards 8 ...` overrides it, capped by the core
count. The default is deliberately well short of the cores available, since
several workspaces share the machine.

Two subtrees of the testlist are deliberately left out. `CPU/decimalmode`
is 41 exhaustive ADC/SBC sweeps that `rake test` already covers per-opcode
against SingleStepTests' bus-level traces, for a worst case near nine
hours. Every row carrying `cia-new` asks for the 6526A, whose timer and
shift register differ from the 6526 badline models; the testlist lists the
same 71 programs again under `cia-old`, and those are the ones that run.

`testbench`, `lorenz` and `sid` are the push-to-main set, run when a push
to `main` touches `lib/`, the runners, the baselines or the Rakefile —
never on a pull request, and never on a schedule. The `testbench-*` suites
are opt-in: pick them by name from the Actions tab, or run the rake task by
hand. `sid-8580` is opt-in too, and so far it runs only as a rake task.

An `exitcode` test ends when it writes `$D7FF`, so the testlist's cycle
count is a timeout rather than a runtime — measure, do not assume. Wall
clock on an M-series laptop, against the worst case the budgets allow. The
serial column is the sum of the per-test times from the same run, which is
what the suite cost before it was sharded:

| suite | rows | worst case | serial | 4 shards |
| --- | --- | --- | --- | --- |
| `testbench` | 200 | 173 min | 46 min | 15 min |
| `testbench-cia` | 121 | 163 min | 39 min | 11 min |
| `testbench-interrupts` | 13 | 4 min | 2 min | 1 min |
| `testbench-irqdma` | 16 | 170 min | 129 min | 37 min |
| `testbench-cpu` | 72 | 49 min | 31 min | 11 min |

`bin/lorenz` is not sharded: the suite chains itself, one LOAD after the
next, so there is nothing to split. It is by far the slowest suite whole,
at about two and a half hours on CI. `bin/sidtests` is not sharded either,
and takes about three and a half minutes here and five on CI. `sid-8580`
runs 65 programs, 48 of them the `wb_testsuite` writeback checks, and takes
26 minutes here (20 of CPU, on a loaded machine), which keeps it out of the
push-to-main set.

`interrupts/irqdma` is 16 programs that measure DMA against interrupts over
~450M cycles each and use nearly all of it whether they pass or fail, which
is why it is a suite of its own: what is left of `interrupts/` runs in
about a minute. CIA and CPU come in at a quarter to two thirds of their
worst case, so the budgets there really are timeouts.

Machine variance is ±15%, and these numbers were measured with two other
workspaces running the testbench at the same time, so a quiet machine will
do better.

Rows are compared by test id, not line by line, and only an id present on
both sides can fail the run:

- **changed** — same test, different verdict or detail. This is the guard.
  `PASS -> FAIL` is a regression, the reverse is a fix, and a changed
  `diff=NNNpx` is a screenshot that moved without changing verdict.
- **new** — the vendored suite gained a test. Reported, not failed: badline
  is no worse for it, even when the new row is a `FAIL`. Re-recording is
  what pins it, and from then on any change to that row fails.
- **gone** — the vendored suite lost a test. Reported, not failed.

Every run prints that summary, and on CI writes it to the job summary as
well. `FAIL<TAB>timeout` in `sid.txt` is a test that never wrote `$D7FF`
within its cycle budget, not one that reported a failure code. Ids that
`c64-testlist.in` lists twice are keyed by occurrence (`id#2`).

Re-record only after deciding the new output is correct, and say why in the
commit message.
