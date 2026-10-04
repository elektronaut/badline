# The SID player

The [README](../README.md#playing-and-rendering-sid-tunes) shows how to
start it. This page covers the player in detail.

```sh
badline sid ~/C64Music/MUSICIANS/H/Hubbard_Rob               # play every tune below a directory
badline sid tune.sid other.sid                               # play a queue of tunes
badline --headless tune.sid                             # play, length from HVSC
badline --headless -s 3 tune.sid                        # play the third subtune
badline --headless --all-subtunes tune.sid              # play on through every subtune
badline --seconds 180 tune.sid --audio-out out.aiff
badline -s 3 --rate 48000 tune.sid --audio-out out.wav
badline --headless --sid 8580 tune.sid
badline --filter-chunk 1 tune.sid --audio-out out.wav   # exact filter, slower
```

## The queue

`badline sid FILE|DIR...` plays a queue of tunes in the SID player's
window, in the order given, and a directory adds every `.sid` tune below
it in path order. `badline sid --headless` plays the queue in the
terminal instead. `badline sid` on its own opens the window with an
empty queue. Dropping `.sid` files or folders on the window adds them
to the end of the queue, and an empty queue starts playing them. A file
that isn't a tune is skipped.

`badline tune.sid` plays the tune in the SID player too, unless an
option of the emulator's window, such as `--ntsc` or `--reu`, asks for
the machine: then a tune for one SID runs on the emulated C64, started
through a small driver after boot.

`--subtune` (or `-s`) picks the first tune's subtune, counting from 1 as
HVSC does, and defaults to the tune's own start subtune. Each tune plays
that one subtune, and when it ends the player goes on to the next tune,
stopping after the last. `a`, or `--all-subtunes`, turns on playing all
subtunes, so that a subtune that ends goes on to the tune's next
subtune, and a tune stepped to starts on its first subtune.

`--sid auto`, the default, fits each of a tune's SIDs the model its
header names. A tune written for 2 or 3 SIDs plays on as many, at the
addresses its header gives, in stereo: SID 1 on the left, SID 2 on the
right and SID 3 in the centre. A tune on one SID plays the same on both
channels.

Playback asks the device for 44.1 kHz and takes whatever rate it
offers, unless `--rate` says otherwise. Ctrl-C stops it. The emulator
window's own options, `--no-autostart`, `--writable`, `--sound`,
`--true-drive`, `--reu`, `--ntsc` and `--verbose`, don't apply.

## The window

The window is worked with the mouse. Its header shows the tune's name,
author and release, the tune the subtune covers at the moment when
HVSC's STIL credits one, following the times STIL gives, and buttons
that switch between three views and between the tune's own SID model,
the 6581 and the 8580, which changes the chips playing on the spot. Its
footer shows the time played on a bar you can click to seek, and buttons
that pause, step between tunes and between a tune's subtunes, and turn
shuffle, looping and all subtunes on and off.

- The visualizer shows each voice's note, and how far off it is in
  cents, over a scope of the voice's output, and the mixed output below
  them. A tune on more than one SID gets a row of voices for each SID,
  and the mix splits into its left and right.
- The SID view shows one SID at a time, and for a tune on more than one,
  a row of SID 1, 2 and 3 buttons at its top picks which. It shows each
  voice's output, its control bits, pulse width, envelope settings, and
  the envelope's level and stage, and the filter's modes, cutoff,
  resonance, volume and its response on the chip playing.
- The INFO view shows the tune's STIL entry and the subtune's, with a
  scroll bar, the mouse wheel or the up and down keys for the long ones.

The terminal's keys work in the window too, along with Tab to switch
views and `c` to step through the SID models.

## The terminal

Played on a terminal, `--headless` and `sid` show each tune's name,
author and release as it starts, then the tune's place in the queue, the
subtune number and the time played against the subtune's length.
`--headless` queues just the one tune.

→ and ← step to the tune's next and previous subtune, stopping at its
first and last. `n` and `p` step to the next and previous tune. `s`
turns shuffle on and off, which plays the queue's tunes in a random
order, and `l` turns looping on and off, so that the end of the queue
goes on to its start. `,` and `.` seek 10 seconds back and forward
within the subtune. As a subtune plays, the player saves its state every
10 seconds. A seek back runs silently from the latest of those saved
states at or before the point asked for, or from the subtune's start
before the first. A seek forward runs on silently from where the
subtune is, or from a saved state further on, when an earlier seek back
left one there. The saved states last until the tune or subtune
changes. Space pauses and `q` quits. The status line shows which
modes are on, and they last until the player quits.

`--no-tui`, or output that isn't a terminal, gives plain progress output
instead and plays through the queue without the keys.

## Rendering

`--audio-out` renders one subtune to a 16-bit stereo PCM file. The
file's extension picks the format, `.wav` or `.aiff`.

## Lengths and STIL

A `.sid` file doesn't store its length, so the player looks the tune up
by MD5 in HVSC's `Songlengths.md5`. It finds the database through
`--songlengths`, in a `DOCUMENTS` directory in any of the tune's parent
directories (the layout of an HVSC collection), or under
`$HVSC_BASE/DOCUMENTS`. Without a database or `--seconds` it runs for 60
seconds, but a subtune that falls silent for 5 seconds before then ends
there, when played and when rendered alike. Silent means the output
holds within 16 steps of one level, since a 6581 idles at a DC offset
rather than at zero. A subtune with a known length plays to its length
whatever it sounds like.

A tune in an HVSC collection also gets its entry in HVSC's `STIL.txt`,
found the same way: comments, covers, and subtune names and composers.
The tune's own fields follow its header, and each subtune's print as it
starts.

## Speed

`badline` plays PSID and RSID tunes in real time. In `badline-ruby`,
PSID tunes run on a CPU and RAM with only the SID clocked, at about
twice real time, so they play smoothly, but RSID tunes set up their own
interrupts, so they boot a full C64 first and run at about half real
time. They render fine but stutter when played, and `badline-ruby` says
so when it falls behind. Both builds run the same code, so they render
the same file sample for sample. See
[native/README.md](../native/README.md#without-the-window).

The filter steps four cycles at a time; `--filter-chunk 1` steps it
every cycle, which is exact and takes about twice as long.
