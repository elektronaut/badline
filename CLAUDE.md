# Badline

A cycle-accurate Commodore 64 emulator in Ruby. `README.md` covers usage,
supported media and what is emulated, and `CONTRIBUTING.md` covers setup.
This file covers how to work on the code.

## Orientation

`lib/badline/` holds one file per chip or subsystem, and namespaced groups
live in subdirectories:

- **Machine**: `computer.rb` clocks everything once per cycle (`cycle!`:
  VIC, both CIAs, SID and the datasette, then the CPU unless the VIC holds
  BA low). `address_bus.rb` handles banking and page-table dispatch
- **CPU**: `cpu.rb`, `instruction.rb` and `instruction_set/`, plus
  `interrupts.rb`
- **VIC-II**: `vic.rb` and `vic/`, covering the sequencer, sprites, graphics
  modes, border and register timing
- **CIA**: `cia.rb` and `cia/` (timers, serial), plus `time_of_day.rb`
- **SID**: `sid.rb` and `sid/`. `audio/` plays and renders tunes for
  `exe/badline-sid`
- **Media and host I/O**: `storage/` (disk, tape and cartridge image
  formats), `cartridge/` (mappers), `kernal_trap/` (the LOAD/SAVE and IEC
  traps that stand in for a drive), `media.rb` (attach and autostart),
  `datasette.rb`, and `gui/` and `input/` (SDL front end, controllers)

Timing-critical code lives in `cpu`, `interrupts`, `vic`, `cia` and `sid` and
in the order `Computer#cycle!` clocks them. Changes there move the test
suites below. `gui/` changes move none of them.

Namespaced groups live in `lib/badline/<namespace>/`, with a sibling
`lib/badline/<namespace>.rb` that requires the members. `lib/badline.rb`
requires only the namespace file.

### Oracles

| Oracle | Runner | Covers |
| --- | --- | --- |
| rspec (`spec/`) | `bundle exec rspec` | Unit behaviour, all of `lib/` |
| SingleStepTests 65x02 | `rake test` (100 sampled cases per opcode) | CPU, per-cycle bus traces |
| Wolfgang Lorenz suite | `bin/lorenz` | CPU, CIA, interrupts |
| VICE testbench | `bin/testbench <subtree>` | `VICII/`, `CIA/`, `interrupts/`, `CPU/`, and cartridges with `--carts` |
| VICE SID testprogs | `bin/sidtests` | SID |
| CIA offline grids | `bundle exec rspec --tag slow spec/badline/cia` | CIA timers and shift register, against a bare CIA in about 2 min |

The CIA offline grids replay Lorenz's `cia1ta` and `cia1tb` sweeps (about
8 s) and the `cia-sdr-icr` loop for every timer A latch (about 2 min),
checked against each test's own results. On the Lorenz chain, a failing
timer test takes about 25 minutes.

`bin/benchmark` measures emulation speed after boot, and `bin/profile` shows
where that time goes. `test/baselines/README.md`
documents the baseline format, the suites and how rows are compared.

## Driving the emulator headlessly

`exe/badline <media>` opens the SDL window, which is no use for checking
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
  `for d in 65x02 VICE-testprogs; do ln -sfn ../../../../vendor/$d vendor/$d; done`.
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

- `rake vendor:checkout` fetches SingleStepTests and VICE-testprogs into
  `vendor/`
- `bundle exec rspec`: line coverage is about 95%. `spec/spec_helper.rb`
  fails a whole-suite run (every spec file, no filters) below 90%, while
  single-file and filtered runs skip the floor. `:slow` specs are excluded
  by default: run them with `bundle exec rspec --tag slow`
- `rake test`: SingleStepTests. Run it for any CPU change

The headless suites are expensive. `bin/testbench` forks over 4 shards by
default. `SHARDS=N rake regression:<suite>` or `bin/testbench --shards N`
overrides that, capped by the core count, but keep the default, because
other worktrees share the machine. Whole runs at 4 shards on an M-series
laptop take 15 min for `testbench` (`VICII/`), 11 for `testbench-cia`, 1 for
`testbench-interrupts`, 37 for `testbench-irqdma`, 11 for
`testbench-cpu` and 2 for `testbench-carts`. `sid` takes about 12 min. `lorenz` chains itself and takes
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
- When your change moves rows, re-record only those rows, in the same
  change: `rake "regression:record:<suite>[filter,...]"` (quote it, because
  zsh globs the brackets). It runs only the matching tests and splices
  their rows into the baseline, and every other row keeps its verdict.
  `lorenz` chains itself, so it takes a stretch of the chain instead:
  `rake "regression:record:lorenz[first,last]"` resumes just ahead of
  `first`, stops after `last` and leaves the `(suite)` row alone.
  `[first,(suite)]` runs on to the end of the chain and records the
  `(suite)` row too. Cover every test your change can reach, and explain
  every moved row. Never re-record just to make a diff go away
- CI's nightly run owns the whole-suite verdict. The Regression workflow
  runs `testbench`, `lorenz` and `sid` against `main` each night, and skips
  the night when nothing relevant has changed since the last successful
  nightly run. It also runs from the Actions tab on demand. It never runs
  on push or on pull requests, so one verdict can cover a day's merges.
  The `testbench-*` and `sid-8580` suites run from the Actions tab on
  demand
- The one exception is a change whose reach you can't bound to a set of
  filters, such as reordering `Computer#cycle!` or changing the LOAD trap
  every suite loads through. Ask before running a full suite for it, and
  don't start one on your own judgement

Pick the filters from the suites your change can move: VIC → `testbench`;
CPU, interrupts or timing → the matching `testbench-*` suite, plus
`rake test` for CPU; CIA → the slow CIA specs first, then the matching
`testbench-cia` rows; cartridge mappers, banking or power-on state →
`testbench-carts`; SID → `sid`, plus `sid-8580` for anything the 8580
model reaches (`bin/sidtests --sid 8580`). Lorenz isn't a per-change check:
its full chain runs nightly, and the planner assigns any row it moves. The
exception is code whose rule in `doc/pinned-behaviour.md` names Lorenz
tests: the interrupt polling, CPU port and CIA timer rules. Run just the
tests that rule names, one at a time, with
`ruby --yjit bin/lorenz --resume <test> --stop-after <test>`. A stretch
resumes on a fresh machine, so its cuts in the Rakefile have to stay before
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

## Git

- **Don't stage, commit, push or open a PR** unless your task says so in
  those words. Wanting a PR, a finished feature or green CI doesn't count
  as permission. Finish the work, report what changed, and stop. A dirty
  tree is the expected end state
- Hunks are staged by hand during review, so a partially staged file is
  deliberate. Use `git diff HEAD` to see everything
- Commit messages use Conventional Commits (`feat:`, `fix:`, `chore:`, …).
  release-please derives version bumps and the changelog from the prefixes
- No `Co-Authored-By` or `Claude-Session` trailers, even where `git log`
  shows them
- When a task explicitly asks for a PR, the branch is already from
  `origin/main` (see above). Open it with `gh pr create --base main`
