# Badline

A cycle-accurate Commodore 64 emulator in Ruby. `README.md` covers usage,
supported media and what is emulated, and `CONTRIBUTING.md` covers setup.
This file covers how to work on the code.

## Orientation

`lib/badline/` holds one file per chip or subsystem, and namespaced groups
live in subdirectories:

- **Machine**: `computer.rb` clocks everything once per cycle (`cycle!`:
  VIC, both CIAs, SID and the datasette, then the CPU unless the VIC holds
  BA low). `address_bus.rb` handles banking and page-table dispatch, and
  `banked_ram.rb` and `banked_ram/` the +60K and +256K boards that bank in
  extra RAM through `$D100`
- **CPU**: `cpu.rb`, `instruction.rb` and `instruction_set/`, plus
  `interrupts.rb`
- **VIC-II**: `vic.rb` and `vic/`, covering the sequencer, sprites, graphics
  modes, border and register timing
- **CIA**: `cia.rb` and `cia/` (timers, serial), plus `time_of_day.rb`
- **REU**: `reu.rb` and `reu/`, the RAM Expansion Unit's registers and
  its DMA, which `Computer#cycle!` clocks in place of the CPU while it
  holds the bus
- **SID**: `sid.rb` and `sid/`. `audio/` plays and renders tunes for
  `badline-ruby --headless` and `--audio-out`
- **Media and host I/O**: `storage/` (disk, tape and cartridge image
  formats), `cartridge/` (mappers), `kernal_trap/` (the LOAD/SAVE and IEC
  traps, and `kernal_trap/dos/`, the virtual DOS that stands in for a
  drive), `media.rb` (attach and autostart),
  `datasette.rb`, and `input/` (the mouse and paddles)
- **Front end**: `frontend/`, the SDL window both builds run (app loop,
  screen, pacer, sound, controls, gamepads, snapshots), in Spinel's
  subset, over the one binding in `sdl.rb` (`ffi.rb` implements it on
  CRuby)
- **Native**: `native/` holds the native `badline`, the core and the
  front end compiled with Spinel (`rake native:build`, `native/README.md`).
  `spinel/` holds the Spinel test harnesses

Timing-critical code lives in `cpu`, `interrupts`, `vic`, `cia` and `sid` and
in the order `Computer#cycle!` clocks them. Changes there move the test
suites below. `frontend/` changes move none of them.

Namespaced groups live in `lib/badline/<namespace>/`, with a sibling
`lib/badline/<namespace>.rb` that requires the members, directly or through
other members. `lib/badline.rb`
requires only the namespace file.

### Oracles

| Oracle | Runner | Covers |
| --- | --- | --- |
| rspec (`spec/`) | `bundle exec rspec` | Unit behaviour, all of `lib/` |
| SingleStepTests 65x02 | `rake test` (100 sampled cases per opcode) | CPU, per-cycle bus traces |
| SingleStepTests z80 | `rake test` (the first 100 cases per opcode, `Z80_SAMPLE=all` for all 1,604,000) | `Z80`: registers, flags, ports and the bus pins on every T-state |
| Wolfgang Lorenz suite | `bin/lorenz` | CPU, CIA, interrupts |
| VICE testbench | `bin/testbench <subtree>` | `VICII/`, `CIA/`, `interrupts/`, `CPU/`, cartridges with `--carts`, the true 1541 drive with `--drive`, the VIC-20 with `--vic20`, the C128 in C64 mode with `--c128c64`, in C128 mode with `--c128`, and its Z80 with `--c128-z80` |
| VICE SID testprogs | `bin/sidtests` | SID |
| Drive scenarios | `bin/drive_scenarios` | The true 1541 running the DOS ROM: save, format, the error channel, idle, write protect and autostart |
| CIA offline grids | `bundle exec rspec --tag slow spec/badline/cia` | CIA timers and shift register, against a bare CIA in about 2 min |

The CIA offline grids replay Lorenz's `cia1ta` and `cia1tb` sweeps (about
8 s) and the `cia-sdr-icr` loop for every timer A latch (about 2 min),
checked against each test's own results. On the Lorenz chain, a failing
timer test takes about 25 minutes.

`bin/benchmark` measures emulation speed after boot, and `bin/profile` shows
where that time goes. `test/baselines/README.md`
documents the baseline format, the suites and how rows are compared.

`bin/machine_diff <scenario|media> --against <rev>` checks that a change
leaves emulation alone. It runs the scenario on this tree and on `<rev>`'s
`lib/` side by side, digests each chip every million cycles (the CPU, RAM,
VIC, CIAs and SID, the VIC-20's VIAs and sound, the C128's VDC, MMU and
Z80), and names the first component that differs. It builds a C64 unless
`--family vic20` or `--family c128` (with `--mode c64|c128`) says
otherwise. Use it for refactors and speed work.

## Driving the emulator headlessly

`exe/badline-ruby <media>` opens the SDL window, which is no use for checking
work. Drive a `Badline::Computer` from Ruby instead, as the `bin/` runners do:

```ruby
computer = Badline::Computer.new
Badline::Media.attach(computer, path)  # PRG, disk, tape, CRT or directory; autostarts
computer.on_init { computer.type_text("print 6*7\r") }  # after boot (~2.5M cycles)
3_500_000.times { computer.cycle! }
computer.address_bus.peek(0x0400)      # screen RAM starts at $0400
```

- `computer.capture_output` traps CHROUT and records what the machine prints
- `computer.install_debug_register { |code| ... }` receives the `$D7FF`
  exit code that testprogs report through (`$00` pass, `$ff` fail)
- To test a BASIC snippet, convert it with `petcat -w2 -o out.prg in.txt`

## Working in parallel

Several sessions work in this repo at once. Each one has its own git
worktree and owns a different set of files.

- **One branch per unit of work**, cut from a freshly fetched `origin/main`,
  in a worktree under `.claude/worktrees/` (gitignored). A lane can keep
  its worktree between tasks: when `git status --short` is clean, start
  the next unit with `git fetch && git switch -c <branch> origin/main`
- **Edit only the files your task names.** Other sessions own the rest, and
  edits outside your set collide with theirs. If you need a change
  elsewhere, report it as a follow-up and don't make it
- The external suites under `vendor/` are gitignored, so a new worktree has
  only `vendor/.gitkeep`. From the worktree root, symlink the main
  checkout's suites into it:
  `for d in 65x02 z80-sample VICE-testprogs; do ln -sfn ../../../../vendor/$d vendor/$d; done`.
  The main checkout also has `vendor/OneLoad64-Games-Collection-v5`, which
  `rake vendor:checkout` doesn't fetch. Link it the same way only for
  `.sid` or media work. Don't re-run `rake vendor:checkout` there, and
  don't write into `vendor/`
- The roadmap is `Plan.local.md` in the main checkout. It is untracked and
  not in the public repo. When a planner session assigned your task, the
  planner owns that file: read it and don't edit it. Send the planner your
  results instead: what changed, suite scores before and after, and anything
  worth recording (pinned rules, follow-ups)
- **Stop only your own processes, by PID.** Never kill by name or
  pattern (`pkill -f`, `killall`, `pgrep … | kill`): other worktrees
  run the same commands, and a pattern stops their runs too. Kill `$!`
  for a job you backgrounded, or a PID you noted when you started it.
  If you have to look one up, match on your worktree's absolute path
  and check the result before you kill anything
- `bin/testbench` passes TERM and INT on to its shards, and the
  `rake regression:*` tasks pass them on to the runner, so killing the
  PID you started stops the whole run. An interrupted run exits
  non-zero and writes no results or baseline
- A background task that ends with exit code 144 got SIGTERM, most likely
  from another session's pattern kill, not a timeout. There is no
  run-length limit

## Testing and baselines

- `rake vendor:checkout` fetches SingleStepTests 65x02, the Z80 sample
  and VICE-testprogs into `vendor/`
- `bundle exec rspec`: line coverage is about 97%. `spec/spec_helper.rb`
  fails a whole-suite run (every spec file, no filters) below 90%, while
  single-file and filtered runs skip the floor. `:slow` specs are excluded
  by default: run them with `bundle exec rspec --tag slow`
- `bundle exec parallel_rspec` is the whole run, `:slow` specs included,
  in a process per core, held to the same 90% over the merged coverage.
  CI runs it as two jobs, the plain examples (with the floor) and the
  `:slow` ones. Agents run only the spec files they touch, with
  plain `bundle exec rspec`, and leave whole runs to CI
- Keep each plain example to a few hundred ms. A million cycles of a C64 or
  a C128 cost 3 to 5 s of CPU, and about three times that under coverage,
  so an example that boots a machine or runs more than about a million
  cycles goes under `:slow`
- Don't boot per example. Restore a machine from a State taken once
  (`spec/support/taken_once.rb`), and share one machine between examples
  that only read it. Assert on the cheapest oracle that proves the point: a
  register or a RAM byte over a booted screen, a bare chip over a whole
  machine, and the fewest cycles that reach the state
- Before opening a pull request, run `bundle exec rspec --profile 10` (with
  `--tag slow` for `:slow` ones) on the spec files you added or changed,
  and hold them to that budget
- `rake test`: SingleStepTests, plus the Minitest tests for the regression
  runners in `test/`. Run it for any CPU change

The headless suites are expensive. `bin/testbench` forks over 4 shards by
default. `SHARDS=N rake regression:<suite>` or `bin/testbench --shards N`
overrides that, capped by the core count, but keep the default, because
other worktrees share the machine. Whole runs at 4 shards on an M-series
laptop take 15 min for `testbench` (`VICII/`), 11 for `testbench-cia`, 1 for
`testbench-interrupts`, 37 for `testbench-irqdma`, 11 for
`testbench-cpu`, 2 for `testbench-carts`, about 25 for `testbench-expansions`, under 1 for `testbench-vic20` and about 30 for `testbench-c128c64`. `sid` takes about 12 min. `lorenz` chains itself and takes
about 2.5 h on CI whole. `rake regression:lorenz-1` to `lorenz-4` run it as
four stretches of about 40 min each, and they can run side by side.
`test/baselines/README.md` has the full table. A killed `bin/testbench` run
leaves its finished rows in `<results>.progress`, and running the same
command again with `--resume` carries on from them.

**Never run a full suite to check your work or to record it.** A full run
repeats CI on your machine, several times over when worktrees overlap, and
the rows your change can't reach tell you nothing about it.

- Iterate on a subset: `ruby --yjit bin/testbench <filter>` (an id
  substring such as `VICII/spritegap`, and `--list` shows the ids),
  `ruby --yjit bin/sidtests <filter>`, or
  `ruby --yjit bin/lorenz [image] [start_test] [max_cycles]` (resumes the
  chain at a named test, and `--stop-after NAME` ends it once that test is
  done). These take seconds to minutes
- A pull request's CI is the verdict. It runs every suite on the Spinel
  build, compared row by row against
  `test/baselines/`, and every job is a required check. A row that moved
  fails it. A pull request that changes only docs, or only a release's
  version bump, skips the specs and suites; pushes to main always run
  them. Re-record only those rows, in the same change:
  `rake "regression:record:<suite>[filter,...]"` (quote it, because zsh
  globs the brackets). It runs only the matching tests on CRuby and
  splices their rows into the baseline, and every other row keeps its
  verdict. CI runs the same rows on Spinel, so the two have to agree.
  `lorenz` chains itself, so it takes a stretch of the chain instead:
  `rake "regression:record:lorenz[first,last]"` resumes just ahead of
  `first`, stops after `last` and leaves the `(suite)` row alone.
  `[first,(suite)]` runs on to the end of the chain and records the
  `(suite)` row too. Explain every moved row in the pull request. Never
  re-record just to make a diff go away
- For a change whose reach you can't bound to a set of filters, such as
  reordering `Computer#cycle!` or changing the LOAD trap every suite loads
  through, push and let CI run the suites
- The Regression workflow runs the suites on CRuby, started by hand from
  the Actions tab, for a person checking that CRuby and Spinel agree.
  Agents don't start it

Pick the filters from the suites your change can move: VIC → `testbench`,
plus `testbench-vicii-new` (`bin/testbench --vicii-new`, the 8565) for
anything the VIC model reaches, and `testbench-ntsc` (`bin/testbench --ntsc`,
the 6567R8 and 6567R56A) and `testbench-drean` (`bin/testbench --drean`,
the 6572) for anything a region's timing reaches;
CPU, interrupts or timing → the matching `testbench-*` suite, plus
`rake test` for CPU; CIA → the slow CIA specs first, then the matching
`testbench-cia` rows, plus `testbench-cia-new` (`bin/testbench --cia-new`,
the 6526A) for anything the interrupt register or the CIA model reaches; cartridge mappers, banking or power-on state →
`testbench-carts`, plus `testbench-expansions` for banking; GEO-RAM, +60K,
+256K, the REU or the VIC's BA line the REU follows → `testbench-expansions`; the 1541 drive, VIA or IEC bus →
`testbench-drive` (`bin/testbench --drive`) and `drive-scenarios` (`bin/drive_scenarios <filter>`), plus `testbench-vic20` for the VIA; the VIC-20 (`vic20/`) →
`testbench-vic20` (`bin/testbench --vic20`); the C128 (`c128.rb`, `c128/`), or
the VIC-IIe, CPU or PLA code it shares with the C64 → `testbench-c128c64`
(`bin/testbench --c128c64`); the C128's Z80, MMU or hand-over → `testbench-c128-z80` (`bin/testbench --c128-z80`) and `testbench-c128`; SID → `sid`, plus `sid-8580` for anything the 8580
model reaches (`bin/sidtests --sid 8580`). Leave the Lorenz chain to CI,
unless your code has a rule in `doc/pinned-behaviour.md` that names Lorenz
tests: the interrupt polling, CPU port and CIA timer rules. Run just the
tests that rule names, one at a time, with
`ruby --yjit bin/lorenz --resume <test> --stop-after <test>`. A stretch
resumes on a fresh machine, so its cuts in `test/support/suites.rb` have to stay before
`trap1`, where the tests start carrying state from one to the next. Both Lorenz
and testbench load through the LOAD trap and type through the keyboard
buffer, so storage, IEC and keyboard changes can move them too. A broken
trap stalls the Lorenz chain.

`ruby --yjit bin/benchmark` measures post-boot speed. Absolute numbers
depend on the machine and its load: parallel worktrees running suites can
cost 20% or more, and wall-clock variance is ±15% even when idle. For an
A/B, run `ruby --yjit bin/profile <idle|text|game|synth> --compare <sha>`.
It pins the base to a commit, because another worktree's fetch can move
`origin/main` mid-comparison. It also times in process CPU time, which holds
about ±3% under load. Without `--compare`, `bin/profile` samples with
stackprof and splits self time by subsystem. It drops stackprof's GC
pseudo-frames, which report lazy-sweep samples as GC time. `--ceiling` shows
how much faster the machine would run if each chip cost nothing.

### Pinned behaviour

[`doc/pinned-behaviour.md`](doc/pinned-behaviour.md) holds timing rules for
the CPU, VIC, CIA and SID. Each was derived empirically against a named
test, and the specs that guard one say `Pinned by <test>` in a comment. When
you change code a pinned rule governs, re-derive the rule against its test
and update the doc if the rule moves. A green suite alone isn't enough,
because the suite can stay green while the rule breaks.

## Rubocop

The Metrics limits in `.rubocop.yml` are house limits, set with headroom
above the largest class, module and method in the tree. A change that needs
more should raise the limit in the same pull request and say why, rather
than split a class or shorten an unrelated method to fit.

## Issues and pull requests

Before filing an issue or opening a pull request, read CONTRIBUTING.md and follow it. Use the exact headings from its skeletons. Report only what you observed or verified, and don't include hypotheses about causes. Open an issue before writing non-trivial code; only changes with one obvious fix (typos, broken links, clear-cut fixes) go straight to a pull request.

### Working from issues

Open issues are agreed work. An agent told to pick issues works this way:

- Pick an open issue without the `in-progress` label whose dependencies
  (named in its body) have merged. Add the label and a comment saying you've
  taken it before you start
- Work in a worktree from `origin/main` as described under *Working in
  parallel*. The issue's text is your brief. If it turns out wrong or
  blocked, comment on the issue and stop rather than widening the scope
- Open one pull request per issue with `Closes #N` in its body, and run
  only the rows your change can reach. Picking an issue is permission to
  commit, push and open that pull request
- Never merge, and never enable auto-merge. The planner session reviews
  every pull request, answers through PR reviews, and merges
- Fix review findings on the same branch. If you drop an issue, remove
  the label and say why in a comment

## Git

- Hunks are staged by hand during review, so a partially staged file is
  deliberate. Use `git diff HEAD` to see everything
- Commit messages use Conventional Commits (`feat:`, `fix:`, `chore:`, …).
  release-please derives version bumps and the changelog from the prefixes
- No `Co-Authored-By` or `Claude-Session` trailers, even where `git log`
  shows them
- Open pull requests against `main`, from a branch cut from `origin/main`
  (see above): `gh pr create --base main`
