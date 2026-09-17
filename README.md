[![Build](https://github.com/elektronaut/badline/actions/workflows/build.yml/badge.svg)](https://github.com/elektronaut/badline/actions/workflows/build.yml)
[![Gem Version](https://img.shields.io/gem/v/badline.svg)](https://rubygems.org/gems/badline)

# Badline

Badline is a Commodore 64 emulator in written in Ruby. It is cycle accurate,
utilizing Fibers to emulate cycles.

Currently the memory map and 6510 CPU is working.

## Building with Spinel

The emulator core compiles ahead of time with
[Spinel](https://github.com/matz/spinel), which is roughly 2.8x faster than
CRuby with YJIT on the same workload:

```sh
spinel -I lib bin/headless -o badline-headless
BADLINE_ROMS=lib/badline/roms ./badline-headless 3000000
```

A compiled binary has no source tree beside it, so `BADLINE_ROMS` points at
the ROM directory; under CRuby the ROMs are found relative to the source as
before.

The SDL front end (`exe/badline`) is CRuby-only: `ruby-sdl2` is a C extension,
and Spinel would need FFI bindings instead. `bin/benchmark` is CRuby-only too,
because Spinel's bundled `optparse` is a smaller subset than the real one.

## TODO

- VIC-II emulation
- CIA 1/2
- C1541 emulation
- SID emulation?

## License

Copyright 2016 Inge Jørgensen

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
