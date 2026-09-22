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
- **SID**: `sid.rb` and `sid/`. `audio/` renders tunes offline
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
| VICE testbench | `bin/testbench <subtree>` | `VICII/`, `CIA/`, `interrupts/`, `CPU/` |
| VICE SID testprogs | `bin/sidtests` | SID |

`bin/benchmark` measures emulation speed after boot. `test/baselines/README.md`
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

- **One worktree per unit of work**: create it under `.claude/worktrees/`
  (gitignored) on a new branch from a freshly fetched `origin/main`
- **Edit only the files your task names.** Other sessions own the rest, and
  edits outside your set collide with theirs. If you need a change
  elsewhere, report it as a follow-up and don't make it
- The external suites under `vendor/` are gitignored, so a new worktree has
  only `vendor/.gitkeep`. From the worktree root, symlink the main
  checkout's suites into it:
  `for d in 65x02 VICE-testprogs; do ln -s ../../../../vendor/$d vendor/$d; done`.
  Don't re-run `rake vendor:checkout` there, and don't write into `vendor/`
- The roadmap is `Plan.local.md` in the main checkout. It is untracked and
  not in the public repo. When a planner session assigned your task, the
  planner owns that file: read it and don't edit it. Send the planner your
  results instead: what changed, suite scores before and after, and anything
  worth recording (pinned rules, follow-ups)

## Testing and baselines

- `rake vendor:checkout` fetches SingleStepTests and VICE-testprogs into
  `vendor/`
- `bundle exec rspec`: line coverage is 97%. SimpleCov doesn't enforce a
  minimum, so check the report and don't let coverage fall below 90%
- `rake test`: SingleStepTests. Run it for any CPU change

The headless suites are expensive. Recent CI runs of the push-to-main set
took about 55 min for `testbench` (`VICII/`), 1.5–2.5 h for `lorenz` and
4 min for `sid`. The opt-in `testbench-cia`, `testbench-interrupts` and
`testbench-cpu` suites take 35, 126 and 31 min. The Regression workflow runs
the push-to-main set when a push to `main` touches `lib/`, the runners, the
baselines or the Rakefile. It never runs on pull requests, and a newer push
cancels a run in progress.

- **Don't run a full suite to check your work.** It repeats CI on your own
  machine, several times over when several worktrees do it at once
- Develop against a subset: `ruby --yjit bin/testbench <filter>` (an id
  substring such as `VICII/spritegap`, and `--list` shows the ids),
  `ruby --yjit bin/lorenz [image] [start_test]` (resumes the chain at a named
  test) or `ruby --yjit bin/sidtests <filter>`. These take seconds to minutes
- `rake regression:sid` takes about 4 minutes, which is cheap enough to run
  whole
- Run a full `rake regression:<suite>` **only** to re-record that suite's
  baseline. Pick the suite your change can move: VIC → `testbench`; CPU,
  CIA, interrupts or timing → `lorenz` and the matching `testbench-*`
  suite; SID → `sid`. Both Lorenz and testbench load through the LOAD trap
  and type through the keyboard buffer, so storage, IEC and keyboard changes
  can move them too. A broken trap stalls the Lorenz chain
- When a behaviour change moves a suite score, re-record that suite's
  baseline (`rake regression:record:<suite>`) in the same change and explain
  every moved row. Never re-record just to make a diff go away
- `ruby --yjit bin/benchmark` measures post-boot speed. Absolute numbers
  depend on the machine and its load: parallel worktrees running suites can
  cost 20% or more, and variance is ±15% even when idle. Compare against
  `origin/main` on the same machine, run back to back

### Pinned behaviour

The **Pinned behaviour** section of `Plan.local.md` holds timing rules for
the CPU, VIC, CIA and SID. Each was derived empirically against a named
test. Some are mirrored in specs with a `Pinned by <test>` comment. When
you change code a pinned rule governs, re-derive the rule against its test.
A green suite alone isn't enough, because the suite can stay green while
the rule breaks.

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
