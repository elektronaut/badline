# Badline C64 Emulator

## Project Overview
Badline is a Commodore 64 emulator written in Ruby, implementing cycle-accurate timing and hardware behavior.

## Running C64 Programs

### Loading PRG and P00 files
Load C64 program files directly (.p00 headers are detected and stripped):

```bash
exe/badline program.prg
```

The emulator boots, injects the program into RAM, and — for BASIC programs
loading at `$0801` — types `RUN` automatically. ML programs at other
addresses are injected without starting.

### Mounting a directory as device 8
Pass a directory to serve its .prg, .p00 and .t64 files through the KERNAL
LOAD trap (.p00 files match on their embedded original filename; .t64
archives expand into one entry per archived file, by its embedded name):

```bash
exe/badline ./prgs/
```

Then load files by name from BASIC — `LOAD"NAME",8,1` (case-insensitive,
`*` and `?` wildcards supported). `SAVE"NAME",8` works too, writing
`name.prg` back into the directory (disk images stay read-only). CBM
drive prefixes are accepted and stripped (`LOAD"0:NAME",8`,
`SAVE"@0:NAME",8`).

### Running disk images
Pass a .d64, .d71 or .d81 image to mount it as device 8 and autostart the
first program:

```bash
exe/badline game.d64                 # LOAD"*",8,1 + RUN automatically
exe/badline game.d64 --no-autostart  # boot to READY. instead
```

Files also open by name (`OPEN 2,8,2,"NAME"` + `GET#`), and the DOS command
channel serves `U1` block reads, `B-P` and `I` on channel 15, so block-access
loaders work. Fast loaders that upload drive code (`M-W`/`M-E`) do not — there
is no drive CPU.

### Running cartridges
Pass a .crt image to attach it to the expansion port; the cartridge boots on
reset:

```bash
exe/badline game.crt
```

Supported hardware types: standard 8K/16K/Ultimax (type 0), Ocean (5) and
Magic Desk (19). Other mapper types raise an error.

### Creating BASIC Programs

#### Using petcat (Recommended)
1. Create a BASIC text file:
```basic
10 print "hello world"
20 for i=0 to 15
30 poke 53280,i
40 for j=1 to 100:next j
50 next i
60 end
```

2. Convert to PRG format:
```bash
petcat -w2 -o myprogram.prg myprogram.txt
```

3. Run in emulator:
```bash
exe/badline myprogram.prg
```

## Code Quality Guidelines
- Namespaced class groups (e.g. `Storage`, `KernalTrap`) live in
  `lib/badline/<namespace>/`, with a sibling `lib/badline/<namespace>.rb`
  that requires the members; `lib/badline.rb` requires only the namespace file
- Follow existing Ruby conventions and Rubocop rules
- Maintain cycle-accurate timing precision
- Keep comprehensive test coverage above 90%

## Working in a parallel worktree
Several sessions usually run against this repo at once, each in its own git
worktree under `.claude/worktrees/`, each owning a different set of files.
Stay inside the files your task names — if you need a change outside them,
raise it as a follow-up instead of making it.

- Create a worktree per unit of work, branched from `origin/main`
- `vendor/` is gitignored, so a fresh worktree has none. Symlink the main
  checkout's copy (`ln -s ../../../vendor vendor` from the worktree root)
  rather than running `rake vendor:checkout` again, and don't write into it
- The roadmap lives in `Plan.local.md` in the main checkout, untracked. When
  a planner session assigned your task, it owns that file: read it, don't
  edit it, and send the planner your results instead — what changed, scores
  before and after, and anything worth recording (pinned rules, follow-ups)

## Testing and baselines
- `rake vendor:checkout` — fetch the external suites into `vendor/` (gitignored)
- `bundle exec rspec` — keep line coverage above 90%
- `rake test` — SingleStepTests, 100 sampled runs per opcode

The headless suites are expensive — testbench ~60 min, lorenz ~85 min — and CI
runs both on every push to `main`. Do not run them in full to check your work:
that duplicates CI on your own machine, and with several worktrees active it
duplicates it several times over.

- Develop against a subset instead: `ruby --yjit bin/testbench <filter>` or
  `ruby --yjit bin/lorenz <image> <start_test>`. Seconds to minutes
- `rake regression:sid` is ~4 minutes — cheap enough to run whole
- Run a full `rake regression:<suite>` **only** when re-recording that
  baseline, which is the one job that genuinely needs the whole run. Pick the
  suite your change can actually move: VIC → testbench; CPU, interrupts, CIA or
  timing → lorenz; SID → sid. Note that both harnesses load through the LOAD
  trap and type through the keyboard buffer, so storage, IEC and keyboard
  changes can move lorenz too — a broken trap stalls the whole chain. GUI-only
  changes move nothing
- `ruby --yjit bin/benchmark` — emulation speed post-boot (~713k cycles/s,
  0.72x PAL real time). Machine variance is ±15%
- A behaviour change that moves a suite score gets its baseline re-recorded
  (`rake regression:record:<suite>`) alongside the change, with the moved rows
  explained. Never re-record just to make a diff go away
- The plan's **Pinned behaviour** section holds rules derived empirically, each
  against a named test. Changing that code means re-deriving the rule against
  its test, not merely keeping the suite green

## Git
- Use Conventional Commits (`feat:`, `fix:`, `chore:`, etc.) — releases are
  cut by release-please, which derives version bumps from commit prefixes
- No `Co-Authored-By` or `Claude-Session` trailers, whatever `git log` shows
- Do not stage, commit, push or open a PR unless the task you were given says
  so in as many words. Finish the work, report what changed, and stop — leaving
  the tree dirty is the expected end state. Hunks get staged by hand during
  review, so a partially staged file is deliberate; use `git diff HEAD` to see
  everything
- Only when a task does ask for a PR: branch from `origin/main` first, then
  `gh pr create --base main`
