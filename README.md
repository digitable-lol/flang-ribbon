<!-- SPDX-FileCopyrightText: 2026 Marat Zimnurov <zimtir@mail.ru> -->
<!-- SPDX-License-Identifier: BSD-2-Clause -->

# flang-ribbon — window-ribbon arithmetic in flang

[По-русски](README.ru.md)

A library of pure, total functions: **which windows and what geometry → where
each of them goes**. No call into a window system, no read, no write. X11, the
Accessibility API, the event loop, config parsing — all of that stays with the
host; numbers come in, numbers go out.

It is *emitted* to **C** and to **Go**, so it travels inside somebody else's
binary — no language runtime, no Node, no interpreter.

The reference behaviour is [digitwm](https://github.com/digitable-lol/digitwm),
`ribbon.c`, the ten `ribbon_policy_*` functions. The transfer was checked
against it **by running both**, over **526,871** inputs: **0 discrepancies** —
and not merely equal numbers, but three byte-identical answer streams at once
(the reference in C, flang emitted to C, flang emitted to Go).

**There is no second language in this tree.** Not Go, not Python, not
JavaScript, and no hand-written C either — and no `Makefile`: the entry point is
`./ярлык` over a list that is itself a flang program.

The source is written in flang, whose surface is Russian. File names are
English, module names are English, the prose inside is Russian — that is the
language's own convention. Two names are Cyrillic on purpose, `ярлык` and
`ярлыки.flang`, taken from the language's own tree: `./ярлык проверка` is what a
person types, not an internal name.

---

## What is here

A ribbon is an endless row of columns, each column an ordered stack of windows.
Row and stacks together make a canvas, and the screen is a viewport sliding over
it on both axes. Two invariants drive everything else:

* inserting a window never alters the geometry of a window already on the
  ribbon — neighbours are pushed along, never squeezed;
* after any event the focused column lies wholly inside the viewport
  horizontally, and the focused window of it lies wholly inside it vertically.

The scalar decisions behind those invariants — how far to scroll, how wide a
column is, how tall a window in it is, where a new window goes, what gets focus
after a close — are four modules of this library.

**The invariants themselves are the fifth.** A scalar cannot state them: it takes
a few numbers, returns one, and a promise on it speaks about the result of ONE
call. Both invariants above speak about the RELATION OF TWO STATES of the ribbon
— before a window is inserted and after — and until `flang/ribbon.flang` there
was no such subject as "a ribbon" in this tree at all. There is now: a ribbon is
a value (a row of columns, the index of the focused one, two offsets),
`«Вставить окно»` is a function from ribbon to ribbon, and both invariants stand
on it as two `обеспечивает`.

### Five modules, 60 functions

| File | Module | What it decides | Reference in `ribbon.c` |
|---|---|---|---|
| `flang/viewport.flang` | «Viewport» | viewport offset across the ribbon and down a stack; clamping the offset after the screen changes size | `ribbon_policy_offset`, `ribbon_policy_voffset`, `ribbon_policy_output` |
| `flang/geometry.flang` | «Geometry» | column width from a share and from a preset, window height in a stack, C99 integer division | `ribbon_policy_width`, `ribbon_policy_height` |
| `flang/placement.flang` | «Placement» | where a newly mapped window goes, what gets focus after a close, the names of places and rules | `ribbon_policy_insert`, `ribbon_policy_close` |
| `flang/strut.flang` | «Strut» | whether a strut and a region meet at all, how much a panel takes off an edge, what two facing panels are left with | `ribbon_policy_span`, `ribbon_policy_reserve`, `ribbon_policy_pair` |
| `flang/ribbon.flang` | «Ribbon» | the ribbon as a value: measuring the row and the stacks, scrolling on both axes, inserting a window, and **both invariants** | `ribbon_measure`, `ribbon_scroll`, `ribbon_focus_extent`, `ribbon_insert` |

1,713 lines of flang (1,186 without comments and blanks) are emitted into 5,969
lines of C (`.c` plus `.h`, shared runtime excluded) and 5,610 lines of Go.

**«Ribbon» is a model, not a transfer, and those are different things.** The four
modules above stand in place of their `ribbon_policy_*` one for one: what is
emitted from them digitwm CALLS. Nobody calls `«Вставить окно»`: the host's
`ribbon_insert()` moves pointers around queues, while here it is written down
what happens to the numbers. Hence it is checked differently — by diffing whole
ribbons (`./ярлык вставка`), not by substitution.

## What backs that up

### 1. A run against the reference — 526,871 inputs, 0 discrepancies

```sh
./ярлык сверка
```

`tools/compare.sh` does five things in a row, and any of them can fail the run:

1. clones digitwm at a **pinned** commit `bfd5d85` and checks the sha256 of
   `ribbon.c` — a reference that has drifted must not be diffed against;
2. **carves** the ten `ribbon_policy_*` out of `ribbon.c` into a translation
   unit of their own — by the very method digitwm itself uses in
   `tools/no-x-build.sh` — and demands that there be exactly ten of them and
   that the object file have **exactly one** undefined symbol: `Conf`;
3. emits the four modules to C and builds them alongside;
4. runs both implementations over 526,871 inputs, writes the answers as **two
   streams into two files** and diffs them with `cmp` — byte for byte, not "by
   meaning";
5. emits the same modules to Go, runs the emitted Go over the same inputs, and
   diffs its answers against the **reference** — `cmp` again.

Result of the run on 2 September 2026:

```
сверено входов: 526871
расхождений:    0
теорема пары («Пара вместе», счётчика в эталоне нет): проверена на 4536 входах, не сработала 0 раз
потоки ответов совпали побайтно: строк 526871, байт 14458160 (cmp)
напечатанное в Go совпало с эталоном побайтно: строк 526871 (cmp)
```

The inputs are not random: they sit on boundaries and around them — zeros, ones,
negatives, inverted spans, presets past the end of the table, flags valued `−1`,
`2`, `7` (the reference treats any non-zero as true, and that is checked rather
than assumed).

One function has no counterpart in the reference at all: `«Пара вместе»` adds up
both halves of a pair and carries a theorem neither half can state on its own —
two panels together never take more of a region than it has. There is nothing to
diff it against, so it is checked by itself, inside the same run: the postcondition
is re-evaluated in the emitted code (the ledger honestly calls it a grid, not a
proof), and over 4,536 inputs it never fired.

### 2. The reference's answers live as examples inside the modules

The diff runs **once** and needs the network. The examples run **on every
push**:

```sh
./ярлык проверка
```

`flang test` evaluates **199** examples inside the modules and another 141 in the
guard, the ribbon-diff plan and the shortcut table. Their numbers are the reference's answers at the
boundaries, taken from that same run.

**What an example does not catch:** it pins a value, but it will not notice if
digitwm itself changes. Whoever edits a checked function re-runs `./ярлык
сверка` and updates the numbers here.

### 3. A proof ledger — printed, not implied

```sh
./ярлык ведомость
```

`flang check --proof` for every module. It says what carries each promise:
termination of all 60 functions is "proved by composition"; of 31 assertions the
kernel proves 6, while the remaining 25 are carried by **a grid of the examples**
— and the ledger says so in plain words: "no violations were looked for; this is
not a proof". Which is true, and is written that way so that nobody mistakes a
grid for a theorem.
**Not a single `|` above a checking command.** The pipeline's shell is `bash -e`
without `pipefail`, so `flang check --proof "$m" | tail -8` returns the exit
code of `tail`, i.e. always zero. In two neighbouring repositories the "proof
ledger" step could not go red for half a year because of exactly that. It is not
here, and the negative control below shows that very trap live.

### 4. A negative control for every check

```sh
./ярлык наоборот
```

A check nothing can break is indistinguishable from a missing one.
`tools/negative.sh` breaks a **copy** of the tree nineteen times and demands red
each time:

| What is broken | What must go red |
|---|---|
| an example's answer `668` → `669` | `flang test` |
| a number replaced by a string | `flang check` |
| `обеспечивает … результат больше 1000000` | the example run |
| a broken module | `flang check --proof` — **and it is shown that the same command through `\| tail -8` returns 0** |
| a broken module | `flang emit` — with not a single file written |
| a planted copyleft file, `.py`, `.c` | the licence guard (three times) |
| the gap arithmetic off by one | `tools/compare.sh` — naming the discrepancies |
| **C's answer** shifted by one — seven mutants, one per kind of output line | `./ярлык вставка` — naming the scenario and the line |
| an invariant tightened into a falsehood | the walk over 896 ribbons — by the postcondition, named |

The working tree is never touched: `git status` is empty afterwards.

### 5. The ribbon before and after insertion — against the live window manager

```sh
DIGITWM=/path/to/clone ./ярлык вставка
```

The run against the reference (1) diffs NUMBERS: policy by policy, numbers in,
one number out. Here a WHOLE RIBBON is diffed, and twice over: the state before
a window is inserted and the state after. The answer comes from
`ribbon_insert()` — the very call the MapRequest handler makes — through
`cwm -C "layout-probe …"`, with no display opened and no window touched.

**Two byte streams are diffed, not field by field.** The spec PRINTS exactly the
text `layout-probe` prints, and the texts are compared whole: a hand-written list
of fields would stay silent about a field left out of it. Twenty scenarios, zero
discrepancies.

### 6. The grid on which both invariants are recomputed

```sh
./ярлык сетка
```

The ledger honestly calls both invariants a grid, not a theorem. Then the grid
must have a size: `tools/grid.flang` walks **896 ribbons** — settings × column
rows × focus indices × stale offsets on both axes × two insertion places — and
calls `«Вставить окно»` on each. The postcondition is recomputed on every return;
one that fires brings the run down. None fired.

**What the grid does not prove:** it is finite. An invariant true on all these
ribbons may be false on one that is not in it.

## How to use it

### From C

```sh
flang emit flang/geometry.flang --target c --out out-c/geometry
make -C out-c/geometry            # libgeometry.a
```

All ten policies map one to one, save one: `ribbon_policy_width` reads its share
from the global `Conf.ribbonwidth[preset]`, and there is no configuration here.
The table of four shares is passed as arguments, leaving the host a wrapper:

```c
#include "geometry.h"

int
ribbon_policy_width(int vw, int preset, int gap, int minw)
{
	fl_arena	 arena;
	fl_ctx		 ctx;
	fl_value	 r;
	fl_error	 e;
	int		 w = minw;

	fl_arena_init(&arena);
	fl_ctx_init(&ctx, &arena);
	if (geometry_shirina_kolonki_po_presetu(&ctx,
	    fl_number(vw), fl_number(preset), fl_number(gap), fl_number(minw),
	    fl_number(Conf.ribbonwidth[0]), fl_number(Conf.ribbonwidth[1]),
	    fl_number(Conf.ribbonwidth[2]), fl_number(Conf.ribbonwidth[3]),
	    &r, &e) == FL_OK)
		w = (int)r.as.number;
	fl_arena_release(&arena);
	return (w);
}
```

The other nine are a direct substitution: `viewport_smeschenie` for
`ribbon_policy_offset`, `strut_dolya_pary` for `ribbon_policy_pair`, and so on.

### From Go

```sh
flang emit flang/strut.flang --target go --out out-go/strut
```

```go
ctx := flang.NewContext()
v, err := flang.DolyaPary(ctx, rt.Number(28), rt.Number(28), rt.Number(40), rt.Number(1))
// v.Num == 12
```

## What stayed with the host, and why

`ribbon.c` is 1,542 lines. **297** of them were transferred: lines 78–374, the
ten `ribbon_policy_*` with their comments. The remaining 1,245 lines are forty
functions, and not one of them is arithmetic:

* **list walking and memory** — `ribbon_col_new`, `ribbon_col_free`,
  `ribbon_col_at`, `ribbon_col_index`, `ribbon_col_count`, `ribbon_col_add`,
  `ribbon_col_del`, `ribbon_measure`, `ribbon_place`, `ribbon_insert`,
  `ribbon_stack_reorder`, `ribbon_col_reorder`. That is `TAILQ_*`, `malloc` and
  `free` — 65 lines of those alone. These functions **call** the policies in a
  loop, but what they decide is not "how much", it is "for whom";
* **the window system** — `ribbon_sync_one`, `ribbon_activate`, `ribbon_warp`,
  `ribbon_screen_init`, `ribbon_screen_relayout`, `ribbon_screen_update`,
  `ribbon_client_insert`, `ribbon_client_remove`, `ribbon_client_focus`,
  `ribbon_focus_col`, `ribbon_focus_win`, `ribbon_move_client`,
  `ribbon_move_win`, `ribbon_swap_col`, `ribbon_width`, `ribbon_center`,
  `ribbon_float_toggle`, `ribbon_group_update`, `ribbon_col_visible`,
  `ribbon_col_onribbon`, `ribbon_win_away`, `ribbon_focus_extent`,
  `ribbon_new`, `ribbon_free`, `ribbon_find`, `ribbon_current`,
  `ribbon_scroll`, `ribbon_sync`. They call the `wsi.h` contract — and that is
  **eleven** names, counted by `nm -u ribbon.o` rather than by grepping the
  text (grep says twenty, because `ribbon_client_insert` contains
  `client_insert` as a substring):

      client_current  client_geom_current  client_hide  client_ptr_save
      client_ptr_warp client_raise         client_resize
      client_set_active client_show        region_pointer  wsi_settle

  Beyond those the object file needs `Conf`, `conf_ribbonrule_match`,
  `xcalloc`, `xstrdup`, `free` and `strcmp` — configuration and memory,
  the host's as well.

**Not one line of those 1,245 was brought here, and that is not carelessness.**
A library that knows about `client_show` stops being a library and becomes half
a window manager. Wiring this arithmetic back into digitwm is separate work; it
is not here.

Note what is *absent* from the remainder: `ribbon.c` already compiles in full
against a 24-line stub instead of the X11 headers, and `nm -u ribbon.o` demands
not a single X11 name. digitwm drew the seam between arithmetic and the world;
here it was only cut along.

## One finding along the way

The first run gave **606 discrepancies out of 526,871**, all on `width`. What
lied was not the arithmetic but the **postcondition**.

flang's numbers are IEEE-754, and it has two zeros. `«Ширина колонки»` with a
viewport of 0, a gap of 0 and a negative share computes `(0 − 0) × −20`, which in
IEEE is exactly `−0`. The postcondition "quotient and remainder rebuild the
dividend" was written without normalisation, scalar equality tells `+0` and `−0`
apart — and the emitted program answered `FLANG_PROPERTY` where the reference
calmly answered zero. Both sides had the same *value* all along; what differed
was the ability to hand it over.

The cure is `плюс 0`, a trick taken from the language's own
`flang/stdlib/numbers.flang`. The analysis is written into the header of
`«Деление нацело»`, and the input itself is an example inside `«Ширина колонки»`.

This is exactly why the check is a run and not a reading: that is not something
you can read your way to.

## Shortcuts instead of a Makefile

```sh
./ярлык              # the whole list
./ярлык всё          # check, ledger, emit, licences, negative controls, diff
```

| Shortcut | What for |
|---|---|
| `проверка` | parsing, types, totality and examples: modules, guard, diff plan, shortcuts |
| `ведомость` | what carries each promise: proved, grid of N, or merely declared |
| `печать` | emit to Go and C and build both: `gofmt`, `go vet`, `go build`, `cc` |
| `сверка` | the run against digitwm: byte for byte, C and Go, needs the network |
| `лицензии` | the licence guard: SPDX, copyleft, foreign languages |
| `наоборот` | negative control: every check is broken and must go red |
| `вставка` | the ribbon before and after insertion against the live `cwm`, byte for byte; needs `DIGITWM` |
| `сетка` | both invariants recomputed on 896 ribbons; half a minute |
| `чисто` | remove what was emitted |
| `всё` | the whole run in order; `вставка` last — it needs a foreign binary |

The `ярлык` shell holds no list of commands at all: it asks the binary and runs
the answer. The list is `ярлыки.flang`, a program — type-checked, with examples,
and the count of shortcuts is carried by a postcondition.

A new check is added as a **shortcut**, not as a line in the pipeline: a check
you cannot repeat at home with one command is not considered a check here.

## What it takes to build

The flang compiler is one binary that needs only `cc`:

```sh
git clone --depth 1 https://github.com/digitable-lol/flang.git
make -C flang/bootstrap
export FLANG=$PWD/flang/bootstrap/flang
```

`./ярлык печать` also needs Go (only for `gofmt`/`go vet`/`go build` over the
emitted code; there is not a line of hand-written Go in the tree). `./ярлык
сверка` needs `git`, the network and `cc`.

## Licence

**BSD-2-Clause**, copyright Marat Zimnurov <zimtir@mail.ru>. The verbatim text is
in [`LICENSE`](LICENSE); [`LICENSE-RU.md`](LICENSE-RU.md) explains it in plain
Russian.

Where the arithmetic comes from, under what licence it lives there, and how
cwm's ISC heritage figures in it — see [`NOTICE`](NOTICE). In short: `ribbon.c`
is digitwm's own file rather than cwm heritage, so there is no ISC-licensed code
here at all; and the reference's header carries two licence statements at once,
which `NOTICE` names rather than glosses over.
