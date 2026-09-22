# Regression baselines

Recorded output of the headless hardware suites, one file per runner:

- `testbench.txt` — `bin/testbench` over the non-interactive PAL VICII
  tests in `vendor/VICE-testprogs/testbench/c64-testlist.in`. One
  tab-separated record per test, in testlist order: `id<TAB>PASS`, or
  `id<TAB>FAIL<TAB>detail` where detail is the `$D7FF` exit code and, for
  screenshot tests, the number of mismatched pixels.
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

All three suites still fail tests. The baselines record those failures as
they stand, so the guard is the comparison, not the pass count.

    rake regression                     # run every suite, diff against these files
    rake regression:testbench           # one suite
    rake regression:record:testbench    # accept a reviewed diff
    rake regression:record              # re-record everything

A recording run is unattended compute measured in hours — roughly three
quarters of an hour for the testbench and about as long for Lorenz; the SID
suite is the odd one out at about four minutes. CI runs them only when a
push to `main` touches `lib/`, the runners, the baselines or the Rakefile,
plus on demand from the Actions tab — never on a pull request, and never on
a schedule.

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
