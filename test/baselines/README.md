# Regression baselines

Recorded output of the two headless hardware suites, one file per runner:

- `testbench.txt` — `bin/testbench` over the non-interactive PAL VICII
  tests in `vendor/VICE-testprogs/testbench/c64-testlist.in`. One
  tab-separated record per test, in testlist order: `id<TAB>PASS`, or
  `id<TAB>FAIL<TAB>detail` where detail is the `$D7FF` exit code and, for
  screenshot tests, the number of mismatched pixels.
- `lorenz.txt` — the CHROUT transcript of `bin/lorenz` running the
  Wolfgang Lorenz suite off `Lorenz.d81`, from the boot banner to the
  `aneb - load error!` that ends the chain on this image.

Both suites still fail tests. The baselines record those failures as they
stand, so the guard is the diff, not the pass count.

    rake regression                     # run both suites, diff against these files
    rake regression:testbench           # one suite
    rake regression:record:testbench    # accept a reviewed diff
    rake regression:record              # re-record everything

A recording run is unattended compute measured in hours — roughly three
quarters of an hour for the testbench, two for Lorenz (the failing `cia1ta`
family grinds through thousands of keypress halts). CI runs them only when
a push to `main` touches `lib/`, the runners, the baselines or the Rakefile,
plus on demand from the Actions tab — never on a pull request, and never on
a schedule.

Reading a diff:

- `-…PASS` / `+…FAIL` is a regression; the reverse is a fix.
- A changed `diff=NNNpx` means a screenshot moved without changing verdict.
- Lines missing from the current run mean the suite stopped early — a hang
  or a timeout, not a passing test.

Re-record only after deciding the new output is correct, and say why in the
commit message.
