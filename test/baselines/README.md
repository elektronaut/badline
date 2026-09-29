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
- `testbench-carts.txt` — the same runner with `--carts`, over the
  testlist's `mountcrt` rows from whichever subtree lists them
  (`C64/carts`, `C64/autostart`, `CPU/cpuport`, the testbench's own
  `selftest`). A row without a program of its own is keyed by its `.crt`,
  and starts from power-on with the cartridge attached instead of from the
  booted machine. It runs for the testlist budget alone, the way VICE runs
  it. A row that loads a program alongside its cartridge, as the freezer
  tests in `C64/carts/aracidtest`, `nordicpower` and `retroreplay` do, is
  keyed `prg+crt`: it boots from power-on with the cartridge in, then loads
  and runs the program like any other row, with the same boot allowance.
  A row is listed only when badline has a mapper for the cartridge's
  hardware type. Rows that want an REU beside the cartridge drop out too,
  since badline gives I/O 2 to the cartridge. `C64/carts/rr-freeze`
  is an analyzer that waits for someone to press the freeze button, so it
  isn't runnable either. Its
  screenshot rows compare like the others, except that `expect:error`
  wants a mismatch, as in VICE: the `selftest` fail row's reference says
  FAIL where the program draws nothing.
- `testbench-cia-new.txt` — the same runner with `--cia-new`, over the
  rows the testlist tags `cia-new`, from whichever subtree lists them, each
  run on a machine whose CIAs are 6526As. Every other suite's rows run on
  the 6526. This includes the `cia-new` rows of
  `general/Lorenz-2.15/src`, the 6526A half of the Lorenz CIA tests:
  their 6526 half runs in `lorenz`, and nothing chains the 6526A half.
  It is a suite of its own rather than rows added to `testbench-cia`,
  `testbench-interrupts` and `testbench-irqdma`, because those baselines
  are the 6526's, and many programs are listed for both chips under the
  same id (`CIA/dd0dtest/dd0dtest.prg`, the three `interrupts/irqdma`
  rows). Kept apart, each id keeps one key, one verdict and one machine
  per baseline, and a change to either chip's rules moves only its own
  suite. All `exitcode` tests.
- `testbench-vicii-new.txt` — the same runner with `--vicii-new`, over the
  rows the testlist tags `vicii-new`, each run on a machine whose VIC-II
  is an 8565. Every other suite's rows run on the 6569. A screenshot row
  compares against the program's `-8565` reference, as VICE's testbench
  does, and against its generic one where there is none. It is a suite of
  its own rather than rows added to `testbench` for the same reason as
  `testbench-cia-new`: all but `VICII/lp-trigger/test2new` are listed
  again under `vicii-old`, with the same id. Its FAIL rows are the ones
  [VIC-II 8565](../../doc/pinned-behaviour.md#vic-ii-8565) explains.
- `testbench-general.txt` — the same runner scoped to `C64/` and
  `general/`, over the testlist's machine-level rows outside the Lorenz
  suite: the power-on RAM pattern (`C64/raminitpattern`), BASIC's pointers
  after a load (`C64/autostart/basic`), the machine state after a load
  (`C64/autostart/defaults`), banking and open I/O (`C64/bankio`,
  `C64/openio`, `general/banking00`), the RAM under the CPU port
  (`general/ram0001`) and emu-fuxxor's checks (`general/fuxxortest`). All
  `exitcode` tests. `general/Lorenz-2.15` is left to `lorenz`, apart from
  its `cia-new` rows in `testbench-cia-new`. Two `fuxxortest` rows,
  `ef2-inst1` and `test-fuxxored`, upload code to the drive and run it
  there, which needs a true 1541, so `bin/testbench` doesn't list them.
- `testbench-expansions.txt` — the same runner with `--expansions`, over
  the rows that ask for a memory expansion badline emulates, from
  whichever subtree lists them: the `geo512k` rows of `GEO-RAM` and
  `memory-expansions`, and the `plus60k` and `plus256k` rows. Each boots
  with its expansion fitted, a 512K GEO-RAM or the +60K or +256K RAM
  expansion, then loads and runs its program like any other row. Rows
  that ask for an REU, Isepic, DQBB or RamCart drop out. All `exitcode`
  tests.
- `testbench-drive.txt` — the same runner with `--drive`, over the
  testlist's `drive/` rows, each run on a machine with a true 1541 on the
  serial bus and the row's `mountd64` or `mountg64` image in it. Nothing
  is mounted through the LOAD trap, so every disk access goes through
  the drive's DOS, which needs `dos1541.rom` in the ROM path. The drive
  writes back to the image, so each row gets a scratch copy of it, and
  `drive/format` formats its copy rather than the testprogs' own.
  `drive/writeprotect` is an `interactive` row, which the runner
  doesn't run. Rows of the other included subtrees that mount a `.d64`
  would run here too, and rows that mount a `.p64` drop out. The
  `rpm` and `scanner` programs run once on a `.d64` and once on a
  `.g64` under the same id, so the `.g64` row's key is the id with
  `#2`. `drive/skew/skew1` passes since the disk turns at 300 rpm and a
  `.d64` starts each track's sector 0 where `N:` would ([1541 disk
  mechanism](../../doc/pinned-behaviour.md#1541-disk-mechanism)), with
  the `scanner` error-map rows still passing.
  `drive/1541-testsuite`'s two rows,
  at about twelve hours each, run only under `--1541-testsuite` and have
  no baseline. `drive/readtest` has no testlist row, so nothing runs it.
  The Spinel build has no drive, so `rake spinel:testbench` leaves this
  suite out. All `exitcode` tests.
- `lorenz.txt` — `bin/lorenz` running the Wolfgang Lorenz suite off
  `Lorenz.d81`, which holds disks 1–3, and then off `Disk4.d64`: when the
  chain asks for `aneb`, the first test missing from the `.d81`, the runner
  swaps disk 4 in before the LOAD is served, as a user with the four disks
  would, and the chain runs on through the ANE and LXA tests to `finish`.
  The suite chains itself by LOADing one test after another,
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
  The list is the testlist's `exitcode` rows under `SID/` that are not
  tagged `sid-new`: the `sid-old` programs and those written for either
  chip, each against its own testlist cycle budget. Rows that mount a disk
  image are left out.
- `sid-8580.txt` — the same runner with `--sid 8580`, which builds the
  machine with an 8580 and runs the programs the testlist tags `sid-new`
  in place of the `sid-old` ones. The untagged programs, written for
  either chip, run on both. Same record format.

Some suites still fail tests. The baselines record those failures as they
stand, so the guard is the comparison, not the pass count.

    rake regression                     # run the nightly set, diff against these files
    rake regression:testbench           # one suite
    rake regression:testbench-cia       # an opt-in suite
    rake regression:record:testbench    # accept a reviewed diff
    rake regression:record              # re-record the nightly set

    rake "regression:record:testbench[spriteenable]"      # only the rows a filter matched
    rake "regression:record:testbench[sprite0,gfxfetch]"  # several filters, matched as a union
    rake "regression:record:lorenz[adcb]"                 # one test of the Lorenz chain
    rake "regression:record:lorenz[sein,adcb]"            # a stretch of it, first to last
    rake "regression:record:lorenz[aneb,(suite)]"         # from aneb to the end, (suite) row included

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
`[first,last]`, both named as rows of `lorenz.txt`, or `[first,(suite)]`
to run on from `first` to the end of the chain. The run resumes at the
row before `first` (`bin/lorenz --resume`), because a test loaded by hand
carries the READY prompt and the typed LOAD in its segment, and that
segment is thrown away. It stops as soon as the chain loads the test after
`last` (`--stop-after`), and the segment the stop cut short is left out too. Only
the rows from `first` to `last` are spliced in, and a row the baseline
does not have yet goes in beside the one it followed. The `(suite)` row
records how the chain ended, so only a `[first,(suite)]` record, which runs
to that end, re-records it. A name that
is not a row of the baseline, or a range given back to front, aborts before
anything runs. If the chain breaks before it reaches `last`, the rows it did
reach are recorded with a warning. `rake regression:lorenz` still runs only
the whole chain; a range record already reports what it changed before it
writes.

The testbench forks over four shards by default — each test gets its
own copy of the machine, so they are independent — and merges the per-test
records back into testlist order. `SHARDS=8 rake regression:testbench` or
`ruby --yjit bin/testbench --shards 8 ...` overrides it, capped by the core
count. The default is deliberately well short of the cores available, since
several workspaces share the machine.

Every test starts from the same 2.5M cycles of KERNAL boot, so each
`bin/testbench` shard, and `bin/sidtests` once per SID model, boots a
machine to that point once and forks a child per test from it
(`test/forked_boot.rb`). A `testbench-carts` shard forks its children
from a machine at power-on instead, never booted, and a child whose row
loads a program boots it with the cartridge attached. The child attaches the program on the cycle a
freshly booted machine would have loaded it, so its state matches the
old boot-per-test path cycle for cycle. The boot is paid once per shard
instead of once per test, which saves about six seconds a test: a
55-test subset went from 29 to 21 minutes of serial time, the 53 short
tests in it from 7 minutes to 1.3, and nine 6581 SID tests from 105
seconds to 61. The suite timings below were measured before this change,
so they overstate what a run costs now. A child that raises, dies
or runs past a wall-clock deadline well beyond its cycle budget gets a
`FAIL` row saying `crashed: …` or `hung: …`, and the next test forks
from the same clean boot. TERM or INT takes the running child down with
its shard.

Two subtrees of the testlist are deliberately left out. `CPU/decimalmode`
is 41 exhaustive ADC/SBC sweeps that `rake test` already covers per-opcode
against SingleStepTests' bus-level traces, for a worst case near nine
hours. Rows carrying `cia-new` ask for the 6526A, and run only in
`testbench-cia-new`, on a 6526A machine. Rows carrying `vicii-new` ask for
the 8565 in the same way, and run only in `testbench-vicii-new`, on an
8565 machine.

`testbench`, `lorenz` and `sid` are the nightly set. The Regression
workflow runs them on `main` every night, but skips the night when nothing
they run has changed since the last successful nightly run: `lib/`, the
runners, the baselines, `test/regression.rb`, the Rakefile or the workflow
itself. So a nightly verdict covers every merge since the one before, and
nothing runs on a push or a pull request. Any suite, nightly or opt-in, can
also be started by name from the Actions tab, and a run started there and
the nightly run never cancel each other. The `testbench-*` suites and
`sid-8580` are opt-in: run them from the Actions tab or as rake tasks.
`testbench-drive` runs only as a rake task, since the workflow doesn't
list it.
The separate Spinel workflow runs the Spinel suites on every pull request
that touches emulation, harness or build paths. Its jobs aren't required
checks yet, and the CRuby nightly run above goes on as before.

An `exitcode` test ends when it writes `$D7FF`, so the testlist's cycle
count is a timeout rather than a runtime — measure, do not assume. Wall
clock on an M-series laptop, against the worst case the budgets allow. The
serial column is the sum of the per-test times from the same run, which is
what the suite cost before it was sharded:

| suite | rows | worst case | serial | 4 shards |
| --- | --- | --- | --- | --- |
| `testbench` | 168 | 173 min | 46 min | 15 min |
| `testbench-cia` | 121 | 163 min | 39 min | 11 min |
| `testbench-interrupts` | 13 | 4 min | 2 min | 1 min |
| `testbench-irqdma` | 16 | 170 min | 129 min | 37 min |
| `testbench-cpu` | 72 | 49 min | 31 min | 11 min |
| `testbench-carts` | 64 | 11 min | 7 min | 2 min |
| `testbench-cia-new` | 93 | 145 min | 52 min | 16 min |
| `testbench-vicii-new` | 32 | 13 min | 0.5 min | 0.2 min |
| `testbench-general` | 18 | 4 min | 0.2 min | 0.1 min |
| `testbench-expansions` | 7 | 22 min | 11 min | 10 min |

The `testbench-cia-new`, `testbench-vicii-new`, `testbench-general` and
`testbench-expansions` rows were measured on a four-core cloud container,
not the laptop, and on CRuby with YJIT, `testbench-general` over two
shards.
`memory-expansions/c64-georam-emd.prg` is nearly all of
`testbench-expansions`, which no sharding shortens. Its worst case is
the rows' budgets at the throughput of that run, not a timed run.
`testbench-drive` was measured on that container too, without
`drive/format`: its other 37 rows took 88 minutes serial and 24 at four
shards. The 19 `viavarious` rows are 60 of those minutes, about three
each, since a second CPU runs alongside the machine.

`bin/lorenz` chains itself, one LOAD after the next, and is by far the
slowest suite whole: about two and a half hours on CI. It can also run as
four stretches side by side, `rake regression:lorenz-1` to `lorenz-4`, each
about a quarter of that, and each can be picked from the Actions tab too.
The Rakefile's `cuts` for `lorenz` end each stretch. A stretch resumes at
the previous cut on a fresh machine, stops after its own, and compares only
its rows, and the last one runs to the end of the chain and carries the
`(suite)` row. A stretch that stops short of its last test, or reports a
different set of rows from the baseline's range, fails. The cuts sit in the
CPU instruction tests, and every one has to stay before `trap1`: from there
on the tests carry state from one to the next, which a fresh machine would
lose. Disk 4 rides at the end of `lorenz-4`: its 37 tests run in about 140M
cycles, five minutes here, which is little more than the 90M-cycle hang at
`aneb` the chain used to end on. `rake regression:lorenz` still runs the
whole chain. `bin/sidtests` is not sharded either. Its 102 6581
programs take about eleven and a half minutes here, four and a half of
them in `waveforms-80-6581` and two in the `oscsample` pair. `sid-8580`
runs 88 programs, 48 of them the `wb_testsuite` writeback checks, and takes
about 29 minutes here (23 of CPU, on a loaded machine), which keeps it out
of the nightly set. The 25 programs it shares with the 6581 list add two
and a half of those minutes.

`interrupts/irqdma` is 16 programs that measure DMA against interrupts over
~450M cycles each and use nearly all of it whether they pass or fail, which
is why it is a suite of its own: what is left of `interrupts/` runs in
about a minute. CIA and CPU come in at a quarter to two thirds of their
worst case, so the budgets there really are timeouts.

Machine variance is ±15%, and these numbers were measured with two other
workspaces running the testbench at the same time, so a quiet machine will
do better.

`bin/testbench` appends each row to `<results>.progress` as its test
finishes, and writes the results file only once every row is in. A run that
is killed partway, by a signal or by a crash, writes no results, but the
progress file keeps the rows it finished, in the results format. The same
command with `--resume` runs only the tests missing from it. Without
`--resume`, a run discards any progress file an earlier run left behind.
The rake tasks pass `--resume` on when `RESUME=1` is set, so
`RESUME=1 rake regression:testbench` or a re-record carries on from a
killed run of the same task. `RESUME=1` fails for `lorenz` and `sid`,
whose runners keep no progress.

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

## Rows that stay failing

These testbench rows fail against references or checks that don't hold
for every chip of their model, or that depend on where the program
starts. They stay
recorded as `FAIL`, and a change that moves them is still a change to
explain.

- `VICII/videomode/videomode-v.prg`, `-w.prg` and `-x.prg` (6, 80 and
  10 px). All three are marked `comment:unsafe reference` in the
  testlist. Their readme says the split delays vary with the VIC and its
  temperature, and that a 6569R5 capture of `-x` matches the 8565
  reference instead of the 6569 one.
  - 79 of `-w`'s 80 px are one stretch of raster line 121, painted
    multicolour text. The 6569 reference paints it red and white, which
    aren't in the program's multicolour registers (`$d022` = 7,
    `$d023` = 5), and that PNG has no yellow or green anywhere. Its 8565
    reference and the 6569 references of `-v`, `-x` and `-y` use yellow
    and green. With those two colours put back on that line, `-w` differs
    by 1 px.
  - The pixels left over (6 in `-v`, 1 in `-w`, 10 in `-x`) are mode-split
    edges. Moving them trades against rules pinned by safer references
    (`modesplit`, `videomode-y`, `videomode-z`, `vicii_reg_timing`). See
    [VIC graphics pipeline](../../doc/pinned-behaviour.md#vic-graphics-pipeline).
- `interrupts/irq-ackn-bug/irq-ack-vicii.prg` (`testbench-interrupts`,
  exit `$ff`) fails from where the harness starts it, and x64sc fails from
  there too. The program enables the raster IRQ for line `$45`, then fills
  its sprite pattern with interrupts off. The harness reaches that setup
  (the `sei` at `$0a35`) at the end of raster line 60, so the IRQ latches
  during the fill and is taken at `cli` on line `$4a`. The double-IRQ
  sync then sets its second IRQ for line `$4b`, a bad line, and the first
  of the 48 samples (`sta` on the raster row) reads `-` where the
  reference says `*`. Every later sample runs from a frame where the sync
  holds.
  - x64sc's own autostart adds a random delay, so its start moves from run
    to run. In the published results x64sc passes 15 times out of 16,
    x64 fails all 11, and the Ultimate 64 passes 11 out of 12.
  - Parked in a loop and resumed at `$0a35` from the same raster position,
    x64sc exits `$ff` too. Over 91 start positions on raster lines 56 to
    64, badline and x64sc gave the same verdict at every one, 18 failures
    and 73 passes, with x64sc's cycle count one higher than badline's
    column. The failures are a run from line 58 to line 61 and single
    cycles on lines 56, 61, 62 and 63.
- `drive/inertia/drive-emu-check.prg` (`testbench-drive`, exit `$ff`)
  prints `00,EMU,00,00`, which its readme gives as every emulator's
  answer; a real 1541 says `OK`. It steps the head four half tracks in
  about 500 cycles each, which the model follows at once, and then finds
  the head two tracks away from the header it searches for. A real head
  can't follow steps that fast. Passing it takes a stepper that moves the
  head over time.
- `C64/autostart/defaults/test.prg` (`testbench-drive`, exit `$ff`) is
  the testlist's second row for the program, the one that mounts
  `test.d64`. It runs with the true drive and `test.d64` in it, but the
  harness injects the program as it does for the plain row, so nothing
  loads from the disk. It fails as its twin in `testbench-general` does
  (below), with the same dump apart from CIA 2's port A, which reads `$97`
  where the twin reads `$d7`. The test masks those two bits off. In both
  rows the four bytes at `$9ff4` that the reference wants to hold the
  loaded file's name, `TEST`, read `$00`.
- `VICII/split-tests/modesplit/modesplit.prg`,
  `VICII/vicii_timing/vicii_reg_timing-ff.prg` and
  `VICII/split-tests/fetchsplit/fetchsplit.prg` (`testbench-vicii-new`,
  92, 7 and 154 px) fail against their `-8565` references. No emulator in
  the testbench results passes all three on the 8565: Denise and x64sc
  fail every one, Hoxs64 passes `modesplit` and z64k `fetchsplit`, each
  against the `8565early` reference, and none passes `vicii_reg_timing-ff`.
  - `modesplit` and `vicii_reg_timing-ff` differ only at the pixel 0 of a
    group that leaves ECM or BMM, where the references disagree with each
    other and with the videomode rows about the same move. The
    `vicii_reg_timing` pair is marked `comment:unsafe reference`. See
    [VIC-II 8565](../../doc/pinned-behaviour.md#vic-ii-8565).
  - `fetchsplit` is marked `comment:unsafe reference`, and its readme says
    the 8565 artefacts vary from chip to chip. Its 154 px are whole glyph
    lines in the first character after a `$dd00` bank switch, where the
    reference shows the other bank's character. The output matches the
    6569 reference there.
- `C64/raminitpattern/cyberloadtest.prg`, `darkstarbbstest.prg` and
  `platoontest.prg` (`testbench-general`, exit `$ff`) check the pattern
  RAM powers on with, and badline powers RAM on at `$00`. All three pass
  on VICE's default pattern (`$00,$00,$ff,$ff,$ff,$ff,$00,$00`, inverted
  every `$4000` bytes). That pattern is a change to the power-on state of
  every suite's machine, so it is left to a change of its own.
- `C64/autostart/defaults/test.prg` (`testbench-general`, exit `$ff`)
  compares the machine against a dump taken after `LOAD"TEST",8` and `RUN`
  on a real C64 with a real drive, down to zero page, CIA 1's timer B and
  CIA 2's port A. The harness injects the program instead of loading it.
  Loaded with a typed `LOAD"TEST",8` through the LOAD trap instead, it
  exits `$ff` as well.
