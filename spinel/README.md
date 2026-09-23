# Spinel harness

[Spinel](https://github.com/matz/spinel) compiles a subset of Ruby ahead of
time to C. `lib/badline/` stays inside that subset, which
`spec/spinel_subset_spec.rb` enforces, so the emulator core builds with
Spinel unchanged. The programs here drive that build and check it against
CRuby.

- `boot.rb` boots the machine headless and types `print 6*7`, or attaches
  and autostarts a media file. It prints a `Badline::Checkpoint` every
  million cycles, then the screen, the cycle and instruction counts and
  the registers.
- `cpu_tests.rb` runs SingleStepTests cases against the CPU and checks
  registers, cycle counts, the bus trace and RAM.
- `convert.rb` samples the SingleStepTests JSON into the line format
  `cpu_tests.rb` reads, since the Spinel build has no JSON library. It runs
  on CRuby only.
- `sig/` holds RBS seeds for types Spinel can't infer on its own.
- `check.rb` backs the rake tasks below.

## Building

Build Spinel from source (`make deps && make`), then point `SPINEL` at the
compiler if it isn't on `PATH`:

```sh
SPINEL=~/src/spinel/bin/spinel rake spinel:build
```

That compiles `boot` and `cpu_tests` into `tmp/spinel/`. `SPINEL_CC`
passes a C compiler command through `--cc`. For instance
`SPINEL_CC="cc -DSP_RBS_CHECK"` checks the RBS seeds at runtime.

To build one harness by hand:

```sh
spinel -I lib --no-line-map --rbs spinel/sig spinel/boot.rb -o tmp/spinel/boot
tmp/spinel/boot [cycles] [timed_from] [media]
```

## Checking against CRuby

```sh
rake spinel:check
rake "spinel:check[vendor/OneLoad64-Games-Collection-v5/IK+.crt]"
rake "spinel:check[path/to/game.crt,40000000]"
```

`spinel:check` builds both harnesses, then runs each compiled binary and
the same harness on CRuby. It fails unless the outputs match: every
checkpoint, the screen, the counts and the registers for the boot, and
every SingleStepTests verdict. Without media it boots for 6M cycles. With
media it runs 23M cycles unless given a count. The first run converts 100
SingleStepTests cases per opcode into `tmp/spinel/cases.txt`, so it needs
`vendor/65x02` (`rake vendor:65x02`).

The checkpoint lines are the ones `bin/machine_diff` prints, so it can
name the first component that differs. Save the compiled build's
lines and run the same scenario against them on CRuby:

```sh
tmp/spinel/boot | grep " cpu=" > tmp/spinel/boot.txt
bin/machine_diff type --cycles 6000000 --against tmp/spinel/boot.txt
tmp/spinel/boot 23000000 3000000 game.crt | grep " cpu=" > tmp/spinel/game.txt
bin/machine_diff game.crt --cycles 23000000 --against tmp/spinel/game.txt
```

Both harnesses print timings. They show where the time goes but aren't a
benchmark, so use `bin/benchmark` and `bin/profile` for CRuby speed.
