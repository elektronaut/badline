# Regression baselines

Recorded output of the headless hardware suites, one file per suite:

- `testbench.txt` — `bin/testbench` over the non-interactive PAL VICII
  tests in `vendor/VICE-testprogs/testbench/c64-testlist.in`. One
  tab-separated record per test, in testlist order: `id<TAB>PASS`, or
  `id<TAB>FAIL<TAB>detail` where detail is the `$D7FF` exit code and, for
  screenshot tests, the number of mismatched pixels.
- `testbench-cia.txt`, `testbench-interrupts.txt`, `testbench-cpu.txt` —
  the same runner over the testlist's `CIA/`, `interrupts/` and `CPU/`
  subtrees, one suite per subsystem so a change can be checked against the
  subtree it can actually move. All three are `exitcode` tests: no
  reference screenshots, so detail is only the `$D7FF` code. Two testlist
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

Every suite still fails tests. The baselines record those failures as they
stand, so the guard is the comparison, not the pass count.

    rake regression                     # run the push-to-main set, diff against these files
    rake regression:testbench           # one suite
    rake regression:testbench-cia       # an opt-in suite
    rake regression:record:testbench    # accept a reviewed diff
    rake regression:record              # re-record the push-to-main set

Two subtrees of the testlist are deliberately left out. `CPU/decimalmode`
is 41 exhaustive ADC/SBC sweeps that `rake test` already covers per-opcode
against SingleStepTests' bus-level traces, for a worst case near nine
hours. Every row carrying `cia-new` asks for the 6526A, whose timer and
shift register differ from the 6526 badline models; the testlist lists the
same 71 programs again under `cia-old`, and those are the ones that run.

A recording run is unattended compute measured in hours — roughly three
quarters of an hour for the testbench and about as long for Lorenz; the SID
suite is the odd one out at about four minutes. Those three are the
push-to-main set, run when a push to `main` touches `lib/`, the runners,
the baselines or the Rakefile — never on a pull request, and never on a
schedule.

The `testbench-*` suites are opt-in: pick them by name from the Actions
tab, or run the rake task by hand. An `exitcode` test ends when it writes
`$D7FF`, so the testlist's cycle count is a timeout rather than a runtime —
measure, do not assume. Measured wall clock on an M-series laptop, against
the worst case the budgets allow:

| suite | rows | worst case | measured |
| --- | --- | --- | --- |
| `testbench-cia` | 121 | 163 min | 35 min |
| `testbench-interrupts` | 29 | 174 min | 126 min |
| `testbench-cpu` | 72 | 49 min | 31 min |

`interrupts/irqdma` is 124 of those 126 minutes: 16 programs that measure
DMA against interrupts over ~450M cycles each and use nearly all of it
whether they pass or fail. CIA and CPU come in at a fifth to two thirds of
their worst case, so the budgets there really are timeouts.

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
