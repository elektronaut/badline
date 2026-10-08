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
- `testbench-ntsc.txt` — the same runner with `--ntsc`, over the rows the
  testlist tags `vicii-ntsc` or `vicii-ntscold`, from whichever subtree
  lists them (`VICII/`, `CIA/CIA-AcountsB`, `CIA/tod` and
  `CPU/Acid800`). Each runs on an NTSC machine with the VIC-II it asks
  for, the 6567R8 for `vicii-ntsc` and the 6567R56A for `vicii-ntscold`,
  and every other suite's rows run on PAL. A screenshot is VICE's NTSC
  view, 384x247 from raster line 28, running on past the last line into
  lines 0-11 of the next frame. It compares against the program's
  `-ntsc` or `-ntscold` reference where there is one and its generic one
  otherwise, as VICE's testbench does. A PAL-sized generic reference is
  compared, as VICE's `cmpscreens` compares it, on the rows the two views
  share, with the display window's top left corner lined up: (32, 35) on
  PAL, (32, 23) on NTSC. `modesplit.prg` is listed for both NTSC chips
  under one id, so the 6567R56A's row is `modesplit.prg#2`. A row with no
  reference at all records `no-ref`, which VICE's testbench fails the
  same way. It is a suite of its own because its programs are listed
  again for PAL, many under the same id, as `testbench-cia-new` is.
- `testbench-ntsc-vicii-new.txt` and `testbench-ntsc-cia-new.txt` — the
  NTSC rows that ask for the 8562 (`--ntsc --vicii-new`), which compare
  against the `-8562` reference where there is one, and the one that asks
  for 6526A CIAs (`--ntsc --cia-new`), kept apart from `testbench-ntsc`
  as `testbench-vicii-new` and `testbench-cia-new` are from the PAL
  suites. The 8562 runs on the 8565's model.
- `testbench-drean.txt` — the same runner with `--drean`, over the rows
  the testlist tags `vicii-drean`, each on a Drean C64, PAL-N with the
  6572. The testlist comments its one such row out, with a note that the
  testbenches don't support the Drean yet, and `--drean` reads it anyway:
  `split-tests/spritescan/spritescan_drean.prg`, which checks its sprite
  collisions against a dump from a real 6572. A screenshot would be
  cropped to the PAL view, since the 6572 draws PAL's 312 lines.
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
  `memory-expansions`, the `plus60k` and `plus256k` rows, and the
  `reu128k` to `reu16m` rows of `REU` and `memory-expansions`. Each boots
  with its expansion fitted, a 512K GEO-RAM, the +60K or +256K RAM
  expansion or an REU of the size the row asks for, then loads and runs
  its program like any other row. Rows that ask for Isepic, DQBB or
  RamCart drop out, and so does `C64/carts/rr-reu`, which wants an REU
  beside a cartridge. `REU/floatingbus/floating3b` is left out of the
  suite: it never reports, and running out its budget of 1.5 billion
  cycles took 37 minutes. `ruby --yjit bin/testbench --expansions
  REU/floatingbus/floating3b` still runs it alone. The FAIL rows, all
  `REU`:
  - `reutiming2/a3`, `a4`, `b4`, `b5`, `b6`, `c3`, `c4`, `d3` and `d4`
    have no reference screenshot (`no-ref`); the readme marks them FIXME.
  - `reutiming2/c`, `d` and `d2` (a transfer ending at the start of a bad
    line, and the same with sprite 7 on) differ from their references by
    6,403, 674 and 337 px. Their readme notes that x64sc fails them too.
  - `reutiming2/e`, `e3` to `e6`, `f3`, `f4`, `g3` and `g4`, the swaps
    without `-m2`, report `$ff`. Where their references differ from the
    `-m2` ones, captured on a breadbin, they read `$42` or a timer value
    where the `-m2` capture has another; badline follows the breadbin's
    (see [REU DMA](../../doc/pinned-behaviour.md#reu-dma)).
  - `reutiming2/g3-m2` and `g4-m2`, swaps with sprite 7 active, report
    `$ff`, and so do `e4-m2` and `e6-m2`, whose first difference from
    their reference is on a sprite line.
  - `badoublewrite` differs by 58,880 px.
  - `rmw-trigger/rmwtrigger-rom` and `rmwtrigger-ram` report `$ff`. The
    testlist marks both `warn:vicefail`.
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
  `C64/autostart/defaults/test.prg#2`, which its readme says has to
  be loaded from the disk by name, types `LOAD"TEST",8` and `RUN`
  instead of injecting its program, and the drive loads it from
  `test.d64`. `drive/1541-testsuite`'s two rows,
  at about twelve hours each, run only under `--1541-testsuite` and have
  no baseline. `drive/readtest` has no testlist row, so nothing runs it.
  All `exitcode` tests.
- `testbench-vic20.txt` — the same runner with `--vic20`, over the
  `exitcode` rows of `vendor/VICE-testprogs/testbench/vic20-testlist.in`,
  each on a PAL VIC-20 with the RAM its options ask for: none for
  `vic20-unexp` or no option, BLK1 for `vic20-8k`, and every block for
  `vic20-32k`, as xvic's `-memory all` fits them. The program goes to the
  start of BASIC, wherever it was saved from, as xvic's `-basicload` puts
  it, with BASIC's end pointers set as LOAD sets them, and `RUN` is typed
  once the machine has booted. A `mountcrt` row starts from power-on with
  the cartridge's ROM chips in their blocks. Tests report through `$910F`,
  and a failure keeps the 22-column text screen. The two rows that ask
  for a GEO-RAM drop out, and the screenshot rows wait for the VIC-I's
  video. On Spinel the rows run on `spinel/vic20_testbench.rb`, so the
  C64's harness doesn't carry the VIC-20. The FAIL rows, all `$ff`:
  - `VIC20/via_sr`: shift register modes `04`, `08`, `14` and `18` in all
    four variants (plain, `ifr`, `exp` and `iex`), and mode `10` in the
    plain and `exp` variants.
- `testbench-c128c64.txt` — the same runner with `--c128c64`, over a
  curated part of the x128c64 testlist: the rows of `c64-testlist.in`
  that VICE's Makefile keeps for x128 in C64 mode, with `cpuport.prg`
  swapped for `cpuport128.prg`. It takes the subtrees where a C128 in C64
  mode can differ from a C64C: `VICII/`, `CPU/`, `interrupts/`, `C64/`,
  `general/` and `selftest/`, less `CPU/decimalmode`, `interrupts/irqdma`
  and the Lorenz suite, bar its `cpuport128` row. Rows that ask for the
  6569, a memory expansion, a disk image or a cartridge without a mapper
  drop out. `Testbench::C128C64_DIRS` in `test/testbench_c128.rb` holds
  the rule. Each row runs on a `Badline::C128` powered on in C64 mode, as
  x128's `-go64` starts it, or with its cartridge in: a `c128dcr` for
  `cia-new`, a `c128` otherwise, and the NTSC board for `vicii-ntsc`. A
  screenshot row compares against the program's 8565 reference, or its
  8562 one on NTSC, where it has one, as a `vicii-new` row does on the
  C64. One suite holds both standards, so a program listed for PAL and
  NTSC keys its NTSC row `#2`. On Spinel the rows run on
  `spinel/c128_testbench.rb`, so the C64's harness doesn't carry the
  C128. A C64C, the 8565 or 8562 with the row's CIA, fails the same
  rows, bar two that read `$01` with bit 6 set, since the 8502's P6
  senses CAPS LOCK: `general/fuxxortest/ef2-inst4a` (`$75`) and
  `C64/carts/ef-eapi/test-eapi.crt` (`$77`). x128 fails both as well.
  The FAIL rows:
  - `$ff`: `C64/autostart/defaults/test.prg` (the injected half of a row
    the readme says to load from disk), `irq-ack-vicii`, `vsp-tester` and
    `vsp-tester-ntsc`, and the two above
  - screenshots: `fetchsplit` (16 px), `modesplit` on PAL (92 px) and
    NTSC (`#2`, 64 px), `vicii_reg_timing-ff` (7 px), and seven
    `videomode*_ntsc` rows
- `drive-scenarios.txt` — `bin/drive_scenarios` over the scenarios in
  `test/drive_scenarios.rb`: a C64 and a true 1541 running the DOS ROM,
  each run from power-on on fresh machines with the disk images in a
  scratch directory. A row per check, keyed `scenario/check`, `PASS` or
  `FAIL` with what the check found:
  - `save` SAVEs a program to a blank disk through the DOS, then NEWs,
    LOADs and LISTs it: no `ERROR` printed (`no-error`), the listing
    (`loads-back`), the file in the image byte for byte
    (`file-in-image`), and the image LOADed and LISTed through the traps
    (`trap-readable`).
  - `format` sends `N:` to an image of zeros, SAVEs a program and LOADs
    the directory: the error channel's `0, OK` (`no-error`), the listing
    with the new name and ID, the program and 663 blocks free
    (`lists-new-disk`), the name and ID in 18/0 (`name-and-id`), 680
    free blocks in the image's BAM (`bam-free`), and the program through
    the traps (`trap-readable`).
  - `read-only` SAVEs to a disk put in write-protected: the SAVE runs
    (`saves`) and the image file is unchanged (`image-unchanged`).
  - `autostart` attaches a disk with a true drive and autostarts its
    program (`loads-and-runs`).
  - `error-channel` reads the power-on message over the serial bus
    (`power-on-message`).
  - `idle` boots two drives side by side, one skipping its idle loop and
    one not, while the C64's lines move: the first sleeps through most of
    the loop (`sleeps`), and both hold the same state at each checkpoint
    (`matches-stepping`).
  Each scenario runs in a process of its own, up to four at once. The
  runner needs `dos1541.rom` in the ROM path.
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

    rake regression                     # run the main set, diff against these files
    rake regression:testbench           # one suite
    rake regression:testbench-cia       # an opt-in suite
    rake regression:record:testbench    # accept a reviewed diff
    rake regression:record              # re-record the main set

    rake "regression:record:testbench[spriteenable]"      # only the rows a filter matched
    rake "regression:record:testbench[sprite0,gfxfetch]"  # several filters, matched as a union
    rake "regression:record:lorenz[adcb]"                 # one test of the Lorenz chain
    rake "regression:record:lorenz[sein,adcb]"            # a stretch of it, first to last
    rake "regression:record:lorenz[aneb,(suite)]"         # from aneb to the end, (suite) row included

Quote the task name: zsh treats the brackets as a glob.

A filtered re-record runs only the matching programs and splices their rows
into the existing baseline; every other row keeps the verdict it had, and
baseline order is preserved. A row the run gained is inserted beside the
row it followed in the run. Nothing is ever removed, so a test the vendored
suite dropped survives a partial record and is reported as `gone` by the
next comparison; clearing it out is a whole-suite record.

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
8565 machine. Rows carrying `vicii-ntsc` or `vicii-ntscold` run only in
the `testbench-ntsc` suites, and rows carrying `vicii-drean`, the PAL-N
machine, only in `testbench-drean`.

`testbench`, `lorenz` and `sid` are the main set, which `rake regression`
runs. The `testbench-*` suites, `sid-8580` and `drive-scenarios` are
opt-in there: run them by name. CI (`.github/workflows/ci.yml`) runs every
suite on the Spinel build on every pull request and every push to `main`,
and fails on any changed row. The Regression workflow runs any suite but
`testbench-drive` on CRuby, started by hand from the Actions tab, to check
that CRuby and Spinel agree.

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
| `testbench-expansions` | 118 | — | 42 min | 25 min |
| `testbench-ntsc` | 112 | 10 min | 3.3 min | 1.0 min |
| `testbench-ntsc-vicii-new` | 8 | 0.5 min | 0.5 min | 0.1 min |
| `testbench-ntsc-cia-new` | 1 | 0.5 min | 0.2 min | 0.2 min |
| `testbench-drean` | 1 | 25 min | 1.7 min | 1.7 min |
| `testbench-vic20` | 72 | — | 1.2 min | 0.4 min |
| `testbench-c128c64` | 413 | — | 74 min | 30 min |

The `testbench-cia-new`, `testbench-vicii-new`, `testbench-general`,
`testbench-expansions` and three `testbench-ntsc` rows were measured on a
four-core cloud container, not the laptop, and on CRuby with YJIT,
`testbench-general` over two shards. The `testbench-ntsc` worst cases
are the rows' budgets at the throughput of `spritesteal_ntsc`, about 3.5M
cycles a second, not timed runs. The `testbench-drean` worst case is its
one row's budget, a billion cycles, at the 0.66M cycles a second that
row ran at, which reported after 66M.
`testbench-expansions`' GEO-RAM, +60K and +256K rows were measured there too, at 11 minutes
serial and 10 at four shards, `memory-expansions/c64-georam-emd.prg`
nearly all of it. Its REU rows were measured on the laptop, under load
from other runs: the 110 `REU` rows took 13 minutes serial and 4 at four
shards on a quieter run, and `memory-expansions/c64-reu-emd.prg` alone
took 18 minutes. The two `-emd` rows are what no sharding shortens, so
the suite takes about as long as the slower of them. The table's serial
and four-shard figures add the two runs, and the worst case wasn't
worked out.
`testbench-c128c64` was measured on the laptop at a load average of
about 25 from other workspaces' runs. The same rows on a C64C took 61
minutes serial and 21 at four shards there. Its slowest rows are
`CPU/ane` (about 100 s each), the `CPU/64doc` decimal rows and the
`branchquirk` and `cia-int` pairs.
`testbench-drive` was measured on that container too, without
`drive/format`: its other 37 rows took 88 minutes serial and 24 at four
shards. The 19 `viavarious` rows are 60 of those minutes, about three
each, since a second CPU runs alongside the machine.

`bin/lorenz` chains itself, one LOAD after the next, and is by far the
slowest suite whole: about two and a half hours on CI. It can also run as
four stretches side by side, `rake regression:lorenz-1` to `lorenz-4`, each
about a quarter of that.
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
of the main set. The 25 programs it shares with the 6581 list add two
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
within its cycle budget, not one that reported a failure code. A program
`c64-testlist.in` lists twice gets a row for each listing, and the runner
writes the second one's key as `id#2`. A key that appears twice in a
results file or a baseline is an error.

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
- `C64/autostart/defaults/test.prg` (`testbench-general`, exit `$ff`)
  compares the machine against a dump taken after `LOAD"TEST",8` and `RUN`
  on a real C64 with a real drive, down to zero page, CIA 1's timer B and
  CIA 2's port A. The harness injects the program instead of loading it.
  Injected, it reads CIA 1's timer B as `$ffff` where the dump has
  `$04ff`, and CIA 2's port A, read with every pin an output, as `$97`
  where the dump has `$c7`: no LOAD ran to leave them. Loaded with a
  typed `LOAD"TEST",8` through the LOAD trap instead, it passes, and so
  does its `testbench-drive` twin, loaded from `test.d64` through the
  true drive.
- The `testbench-ntsc` rows that record `no-ref` (27, all 6567R56A rows:
  `D011Test/disable-bad`, the `dentest` rows, `gfxfetch`, `screenpos`,
  `videomode/rmwtest` and `spritedma/d017-54` and `-57`) have no
  reference in the testprogs, neither `-ntscold` nor generic. VICE's
  testbench reports each of them as a missing reference.
- The `videomode` NTSC rows in `testbench-ntsc` and
  `testbench-ntsc-vicii-new`, all marked `comment:unsafe reference`.
  - In `-v`, `-w`, `-x` and `-y` the longest runs of differing pixels
    are multicolour text that the references paint in colours 1 and 2,
    where badline paints the program's `$d022` and `$d023`, 7 and 5, in
    the same pattern. That is the PAL `-w` reference's problem, above.
    The rest are a few pixels at mode-split edges.
  - `videomode1` and `videomode2` differ by whole character rows below the
    split lines, which the references leave in the background colour and
    badline draws as text. Their PAL references show those rows as text.
  - `-z` is 2 px on the 6567R8 and the 6567R56A, and 21 px on the 8562,
    at the edges of the mode splits.
- `VICII/split-tests/modesplit/modesplit.prg` (`testbench-ntsc`, 458 px)
  fails against its `-ntsc` reference, which its README says was matched
  against screenshots of a 6567R8 rather than taken from one. Most of the
  pixels are one pixel at x=293 on 45 rows of the screenshot, which the
  reference leaves black, and the first 8 pixels of the character after
  a split on rows 96-107, where the reference shows a different glyph. The PAL row
  passes, so these are left to a change that re-derives the pipeline
  rules against a 6567R8. `modesplit.prg#2` (the 6567R56A, 62 px) has no
  `-ntscold` reference and compares against the PAL one.
