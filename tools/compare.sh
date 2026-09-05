#!/bin/sh
# SPDX-FileCopyrightText: 2026 Marat Zimnurov <zimtir@mail.ru>
# SPDX-License-Identifier: BSD-2-Clause
#
# СВЕРКА С ЭТАЛОНОМ: перенос доказывается прогоном, а не чтением.
#
# Эталон — `ribbon.c` из `digitable-lol/digitwm`, десять функций
# `ribbon_policy_*`. Здесь они собираются РОВНО ТАК ЖЕ, как их собирает сам
# эталон в `tools/no-x-build.sh`: выкусываются из `ribbon.c` в отдельную
# единицу трансляции против заглушки, без единого заголовка X11, и у
# получившегося объектника обязано быть ровно одно неопределённое имя — `Conf`.
# Если выкусилось не десять функций или всплыло лишнее имя, скрипт падает
# здесь: значит, эталон перестал быть чистой арифметикой, и сверять уже нечего.
#
# Дальше рядом собирается НАПЕЧАТАННОЕ из flang (`flang emit --target c`), и
# обе реализации гоняются на большом множестве входов. Ответы пишутся двумя
# потоками в два файла и сверяются `cmp` — БАЙТ В БАЙТ, а не «по смыслу».
#
# Прогон идёт ОДНАЖДЫ и требует сети (клон эталона). На каждый толчок ходят
# примеры внутри модулей: ответы эталона вшиты в них числами, и `flang test`
# гоняет их без сети и без эталона вовсе.
#
# Запуск:  sh tools/compare.sh
# Выход:   0 — расхождений ноль; 1 — расхождение или сломанный эталон.
#
# Переменные:
#   FLANG        путь к компилятору (иначе $FLANG_HOME/bootstrap/flang, иначе PATH)
#   DIGITWM      клон эталона как КЭШ: ribbon.c берётся оттуда, только если там
#                лежит пришпиленный коммит; иначе — по сети (см. пункт 1)
#   TMPDIR       где держать черновик (по умолчанию /tmp)
#
# ИМЕНА ПЕРЕМЕННЫХ ЛАТИНИЦЕЙ: ни dash, ни bash не принимают кириллицу в именах.

set -eu

# Коммит эталона, с которым сверялись. Пин — не украшение: `main` у эталона
# двигается, и «сверено с main» ничего не значило бы через день.
PIN=bfd5d85ef0417c38ff24ab0224844696b06fab06
PIN_RIBBON_SHA256=2a12726ccd8296fb1ea6f6ec3ba9df28f32ca59983e8ea24bb1aa4e1768768eb

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC=${CC:-cc}

err() { printf '%s\n' "$*" >&2; }

if [ -z "${FLANG:-}" ]; then
  if [ -n "${FLANG_HOME:-}" ]; then FLANG=$FLANG_HOME/bootstrap/flang; else FLANG=flang; fi
fi
command -v "$FLANG" >/dev/null 2>&1 || { err "компилятора flang нет: «$FLANG»"; exit 3; }

work=
cleanup() { if [ -n "$work" ]; then rm -rf "$work"; fi; }
trap cleanup EXIT INT TERM
work=$(mktemp -d "${TMPDIR:-/tmp}/flang-ribbon-compare.XXXXXXXX")

# ── 1. Эталон ───────────────────────────────────────────────────────────────
# Эталон здесь ВСЕГДА на пришпиленном коммите. `$DIGITWM` — не источник эталона,
# а КЭШ клона: из него берётся `ribbon.c` ровно тогда, когда там лежит пин, и
# никогда иначе; нет пина — эталон приходит по сети.
#
# ПОЧЕМУ НЕ «ЧТО ЛЕЖИТ В $DIGITWM, ТО И ЭТАЛОН». Ту же переменную ставит и тот,
# кому нужен не эталон, а собранный `cwm` (`tools/insert.sh`, восьмой
# отрицательный контроль), и клон у него по делу на master. Так ствол и
# покраснел 2026-09-05 (прогон 33967669223): шаг конвейера завёл
# `DIGITWM=/tmp/digitwm` с master-клоном, сверка уткнулась в чужой отпечаток
# `ribbon.c` и покраснела НЕ расхождением — а седьмой отрицательный контроль
# ждёт от неё именно расхождения и справедливо ей не поверил. Пин здесь
# сильнее переменной среды, и повторить это уже нечем.
taken=
if [ -n "${DIGITWM:-}" ]; then
  if [ -f "$DIGITWM/ribbon.c" ] &&
     [ "$(sha256sum "$DIGITWM/ribbon.c" | awk '{print $1}')" = "$PIN_RIBBON_SHA256" ]; then
    cp "$DIGITWM/ribbon.c" "$work/ribbon.c"
    taken="\$DIGITWM ($DIGITWM) — там пин"
  elif git -C "$DIGITWM" cat-file -e "$PIN:ribbon.c" 2>/dev/null; then
    git -C "$DIGITWM" show "$PIN:ribbon.c" > "$work/ribbon.c"
    taken="клон \$DIGITWM ($DIGITWM), коммит $PIN"
  else
    echo "в \$DIGITWM ($DIGITWM) пина нет — эталон беру по сети, а не оттуда"
  fi
fi
if [ -z "$taken" ]; then
  git clone -q --filter=blob:none --no-checkout \
      https://github.com/digitable-lol/digitwm.git "$work/digitwm"
  ( cd "$work/digitwm" && git checkout -q "$PIN" -- ribbon.c )
  cp "$work/digitwm/ribbon.c" "$work/ribbon.c"
  taken="digitable-lol/digitwm, коммит $PIN"
fi
echo "эталон: $taken"

have=$(sha256sum "$work/ribbon.c" | awk '{print $1}')
if [ "$have" != "$PIN_RIBBON_SHA256" ]; then
  err "ribbon.c не тот, с которым сверялись:"
  err "  ждали  $PIN_RIBBON_SHA256"
  err "  видим  $have"
  err "Взят он был отсюда: $taken"
  err "Эталон изменился. Перегоните сверку, обновите примеры в модулях и пин здесь."
  exit 1
fi
echo "  ribbon.c sha256 $have — тот самый"

# ── 2. Десять политик отдельной единицей трансляции ─────────────────────────
# Дословно приём эталона (`tools/no-x-build.sh`, проход 4): выкусываем функции
# `ribbon_policy_*` вместе со строкой типа над именем.
cat > "$work/shim.h" <<'EOF'
#ifndef SHIM_H
#define SHIM_H
#define MIN(x, y) ((x) < (y) ? (x) : (y))
#define MAX(x, y) ((x) > (y) ? (x) : (y))
#define RIBBON_NPRESET		4
#define RIBBON_PLACE_COLUMN	0
#define RIBBON_PLACE_STACK	1
#define RIBBON_PLACE_FLOAT	2
#define RIBBON_PLACE_FULL	3
#define RIBBON_RULE_NONE	0
#define RIBBON_RULE_STACK	1
#define RIBBON_RULE_FLOAT	2
struct conf_shim { int ribbonwidth[RIBBON_NPRESET]; };
extern struct conf_shim Conf;
int ribbon_policy_offset(int, int, int, int, int, int);
int ribbon_policy_voffset(int, int, int, int, int, int);
int ribbon_policy_width(int, int, int, int);
int ribbon_policy_height(int, int, int, int, int);
int ribbon_policy_insert(int, int, int, int, int, int);
int ribbon_policy_close(int, int, int, int);
int ribbon_policy_output(int, int, int);
int ribbon_policy_span(int, int, int, int);
int ribbon_policy_reserve(int, int, int, int, int);
int ribbon_policy_pair(int, int, int, int);
#endif
EOF

echo '#include "shim.h"' > "$work/policy.c"
awk '
/^ribbon_policy_[a-z]*\(/ { emit = 1; print prev }
emit { print }
/^\}/ { emit = 0 }
{ prev = $0 }
' "$work/ribbon.c" >> "$work/policy.c"

nfn=$(grep -c '^ribbon_policy_[a-z]*(' "$work/policy.c")
[ "$nfn" -eq 10 ] || { err "выкушено $nfn политик вместо десяти — у эталона изменился набор"; exit 1; }

( cd "$work" && $CC -std=c99 -Wall -Wextra -Werror -O2 -c policy.c -o policy.o )
undef=$(nm -u "$work/policy.o" | awk '{print $NF}' | LC_ALL=C sort | tr '\n' ' ')
undef=${undef% }
[ "$undef" = "Conf" ] || { err "эталон перестал быть чистой арифметикой; неопределённые имена: $undef"; exit 1; }
echo "  десять политик собраны отдельно; неопределённых имён: Conf — и больше ничего"

# ── 3. Напечатанное из flang ────────────────────────────────────────────────
mkdir -p "$work/build"
for f in "$ROOT"/flang/*.flang; do
  m=$(basename "$f" .flang)
  "$FLANG" emit "$f" --target c --out "$work/emit-$m" >"$work/emit.log" 2>&1 || { err "печать в C отказала: $m"; cat "$work/emit.log" >&2; exit 1; }
  cp "$work/emit-$m/$m.c" "$work/emit-$m/$m.h" "$work/build/"
done
# Рантайм у всех четырёх один и тот же с точностью до комментария и
# `FL_MAX_ARGS`; берём тот, у которого доводов больше всех.
best=0; bestdir=
for d in "$work"/emit-*; do
  n=$(awk '$1 == "#define" && $2 == "FL_MAX_ARGS" && $3 ~ /^[0-9]+$/ { print $3; exit }' "$d/flang_runtime.h")
  if [ "${n:-0}" -gt "$best" ]; then best=$n; bestdir=$d; fi
done
cp "$bestdir/flang_runtime.c" "$bestdir/flang_runtime.h" "$work/build/"
echo "напечатано в C: 4 модуля; общий рантайм FL_MAX_ARGS=$best"

cp "$work/shim.h" "$work/policy.o" "$work/build/"

# ── 4. Прогонщик: обе реализации на одном множестве входов ──────────────────
# Он ЗДЕСЬ, а не файлом в дереве, нарочно: библиотека — это flang, и
# рукописного C в ней нет ни строки. Прогонщик — оснастка, живёт ровно столько,
# сколько идёт сверка. Тот же приём, что у эталона в `tools/no-x-build.sh`.
cat > "$work/build/driver.c" <<'EOF'
/* SPDX-FileCopyrightText: 2026 Marat Zimnurov <zimtir@mail.ru> */
/* SPDX-License-Identifier: BSD-2-Clause */
/*
 * Сверщик: слева десять политик эталона, справа напечатанное из flang.
 * Каждый вход печатается двумя строками в два потока; строки обязаны
 * совпасть побайтно. Сверяется дважды: здесь на лету и снаружи — `cmp`.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "shim.h"
#include "viewport.h"
#include "geometry.h"
#include "placement.h"
#include "strut.h"

struct conf_shim Conf;

static fl_arena arena;
static fl_ctx ctx;
static FILE *fa, *fb;
static long long total, bad;
static long long pair_total, pair_bad;

static void
render(char *buf, size_t n, fl_status st, fl_value v, const fl_error *e)
{
	double d;

	if (st != FL_OK) {
		snprintf(buf, n, "БЕДА %s", e->code ? e->code : "?");
		return;
	}
	if (v.tag != FL_NUMBER) {
		snprintf(buf, n, "НЕ ЧИСЛО (метка %d)", (int)v.tag);
		return;
	}
	d = v.as.number;
	if (d == floor(d) && d >= -2147483648.0 && d <= 2147483647.0)
		snprintf(buf, n, "%d", (int)d);
	else
		snprintf(buf, n, "%.17g", d);
}

static void
one(const char *label, int ref, fl_status st, fl_value got, const fl_error *e)
{
	char mine[64], theirs[128];

	snprintf(mine, sizeof mine, "%d", ref);
	render(theirs, sizeof theirs, st, got, e);

	fprintf(fa, "%s = %s\n", label, mine);
	fprintf(fb, "%s = %s\n", label, theirs);

	total++;
	if (strcmp(mine, theirs) != 0) {
		bad++;
		if (bad <= 20)
			fprintf(stderr, "РАСХОЖДЕНИЕ  %s: эталон %s, flang %s\n",
			    label, mine, theirs);
	}
}

static void
fresh(void)
{
	fl_arena_reset(&arena);
	fl_ctx_init(&ctx, &arena);
}

#define N(a) ((int)(sizeof(a) / sizeof((a)[0])))

int
main(int argc, char **argv)
{
	fl_value r;
	fl_error e;
	fl_status st;
	char lab[192];
	int i0, i1, i2, i3, i4, i5;

	if (argc != 3) {
		fprintf(stderr, "нужно: driver <файл эталона> <файл flang>\n");
		return 2;
	}
	fa = fopen(argv[1], "w");
	fb = fopen(argv[2], "w");
	if (fa == NULL || fb == NULL) {
		perror("fopen");
		return 2;
	}
	fl_arena_init(&arena);
	fl_ctx_init(&ctx, &arena);

	/* 1. Смещение поперёк ленты. */
	{
	static const int vw[] = { 0, 1, 100, 800, 1280, 1281 };
	static const int cl[] = { -3000, -1000, -8, -1, 0, 1, 7, 640, 1300, 2560, 4000, 5000 };
	static const int cw[] = { 0, 1, 8, 120, 640, 1280, 2000 };
	static const int of[] = { -3000, -1000, -40, 0, 7, 640, 1280, 3000 };
	static const int gp[] = { 0, 1, 8, 1000 };
	static const int ln[] = { 0, 900, 2560, 5000 };
	for (i0 = 0; i0 < N(vw); i0++)
	for (i1 = 0; i1 < N(cl); i1++)
	for (i2 = 0; i2 < N(cw); i2++)
	for (i3 = 0; i3 < N(of); i3++)
	for (i4 = 0; i4 < N(gp); i4++)
	for (i5 = 0; i5 < N(ln); i5++) {
		int ref = ribbon_policy_offset(vw[i0], cl[i1], cw[i2], of[i3], gp[i4], ln[i5]);
		snprintf(lab, sizeof lab, "offset %d %d %d %d %d %d",
		    vw[i0], cl[i1], cw[i2], of[i3], gp[i4], ln[i5]);
		fresh();
		st = viewport_smeschenie(&ctx, fl_number(vw[i0]), fl_number(cl[i1]),
		    fl_number(cw[i2]), fl_number(of[i3]), fl_number(gp[i4]),
		    fl_number(ln[i5]), &r, &e);
		one(lab, ref, st, r, &e);
	}
	}

	/* 2. Смещение вниз по стопке. */
	{
	static const int vh[] = { 0, 1, 60, 400, 800, 1200 };
	static const int wy[] = { -2000, -60, -1, 0, 1, 300, 900, 4000 };
	static const int wh[] = { 0, 1, 60, 260, 800, 1500, 4000 };
	static const int of[] = { -500, -1, 0, 11, 552, 2000 };
	static const int gp[] = { 0, 8, 64, 4000 };
	static const int cv[] = { 0, 811, 1352, 4000 };
	for (i0 = 0; i0 < N(vh); i0++)
	for (i1 = 0; i1 < N(wy); i1++)
	for (i2 = 0; i2 < N(wh); i2++)
	for (i3 = 0; i3 < N(of); i3++)
	for (i4 = 0; i4 < N(gp); i4++)
	for (i5 = 0; i5 < N(cv); i5++) {
		int ref = ribbon_policy_voffset(vh[i0], wy[i1], wh[i2], of[i3], gp[i4], cv[i5]);
		snprintf(lab, sizeof lab, "voffset %d %d %d %d %d %d",
		    vh[i0], wy[i1], wh[i2], of[i3], gp[i4], cv[i5]);
		fresh();
		st = viewport_smeschenie_po_stopke(&ctx, fl_number(vh[i0]), fl_number(wy[i1]),
		    fl_number(wh[i2]), fl_number(of[i3]), fl_number(gp[i4]),
		    fl_number(cv[i5]), &r, &e);
		one(lab, ref, st, r, &e);
	}
	}

	/* 3. Смещение после смены размера окна просмотра. */
	{
	static const int vs[] = { -1000, -8, -1, 0, 1, 2, 7, 8, 60, 100, 119, 120, 121,
	    400, 640, 800, 801, 1280, 1281, 1600, 2000, 2560, 2561, 4000, 9000 };
	for (i0 = 0; i0 < N(vs); i0++)
	for (i1 = 0; i1 < N(vs); i1++)
	for (i2 = 0; i2 < N(vs); i2++) {
		int ref = ribbon_policy_output(vs[i0], vs[i1], vs[i2]);
		snprintf(lab, sizeof lab, "output %d %d %d", vs[i0], vs[i1], vs[i2]);
		fresh();
		st = viewport_smeschenie_posle_smeny_okna(&ctx, fl_number(vs[i0]),
		    fl_number(vs[i1]), fl_number(vs[i2]), &r, &e);
		one(lab, ref, st, r, &e);
	}
	}

	/* 4. Ширина колонки по номеру пресета — вместе с таблицей долей. */
	{
	static const int vw[] = { 0, 1, 8, 100, 119, 120, 121, 800, 1280, 2560 };
	static const int ps[] = { -5, -1, 0, 1, 2, 3, 4, 10 };
	static const int gp[] = { 0, 1, 8, 40, 2000 };
	static const int mw[] = { 0, 1, 120, 400, 3000 };
	static const int tb[][4] = {
		{ 33, 50, 67, 100 },
		{ 100, 67, 50, 33 },
		{ 0, 1, 99, 101 },
		{ -20, 200, 50, 50 },
		{ 25, 25, 25, 25 }
	};
	for (i0 = 0; i0 < N(vw); i0++)
	for (i1 = 0; i1 < N(ps); i1++)
	for (i2 = 0; i2 < N(gp); i2++)
	for (i3 = 0; i3 < N(mw); i3++)
	for (i4 = 0; i4 < N(tb); i4++) {
		int ref;
		Conf.ribbonwidth[0] = tb[i4][0];
		Conf.ribbonwidth[1] = tb[i4][1];
		Conf.ribbonwidth[2] = tb[i4][2];
		Conf.ribbonwidth[3] = tb[i4][3];
		ref = ribbon_policy_width(vw[i0], ps[i1], gp[i2], mw[i3]);
		snprintf(lab, sizeof lab, "width %d %d %d %d [%d %d %d %d]",
		    vw[i0], ps[i1], gp[i2], mw[i3],
		    tb[i4][0], tb[i4][1], tb[i4][2], tb[i4][3]);
		fresh();
		st = geometry_shirina_kolonki_po_presetu(&ctx, fl_number(vw[i0]),
		    fl_number(ps[i1]), fl_number(gp[i2]), fl_number(mw[i3]),
		    fl_number(tb[i4][0]), fl_number(tb[i4][1]), fl_number(tb[i4][2]),
		    fl_number(tb[i4][3]), &r, &e);
		one(lab, ref, st, r, &e);
	}
	}

	/* 5. Ширина колонки по самой доле: все четыре ячейки таблицы равны, а
	 * значит пресет ничего не выбирает и меряется одна арифметика. */
	{
	static const int vw[] = { -1000, -8, 0, 1, 8, 40, 100, 119, 120, 121, 200,
	    300, 400, 640, 800, 1000, 1280, 1600, 2560, 4000 };
	static const int pc[] = { -100, -50, -1, 0, 1, 2, 10, 25, 33, 34, 49, 50,
	    51, 66, 67, 75, 99, 100, 101, 150, 200, 999, 3, 7 };
	static const int gp[] = { -8, 0, 1, 8, 40, 2000 };
	static const int mw[] = { -10, 0, 1, 60, 120, 400, 3000 };
	for (i0 = 0; i0 < N(vw); i0++)
	for (i1 = 0; i1 < N(pc); i1++)
	for (i2 = 0; i2 < N(gp); i2++)
	for (i3 = 0; i3 < N(mw); i3++) {
		int ref;
		Conf.ribbonwidth[0] = pc[i1];
		Conf.ribbonwidth[1] = pc[i1];
		Conf.ribbonwidth[2] = pc[i1];
		Conf.ribbonwidth[3] = pc[i1];
		ref = ribbon_policy_width(vw[i0], 0, gp[i2], mw[i3]);
		snprintf(lab, sizeof lab, "widthpct %d %d %d %d",
		    vw[i0], pc[i1], gp[i2], mw[i3]);
		fresh();
		st = geometry_shirina_kolonki(&ctx, fl_number(vw[i0]), fl_number(pc[i1]),
		    fl_number(gp[i2]), fl_number(mw[i3]), &r, &e);
		one(lab, ref, st, r, &e);
	}
	}

	/* 6. Высота окна в колонке. */
	{
	static const int vh[] = { -100, 0, 1, 40, 59, 60, 61, 100, 400, 800, 801, 1200 };
	static const int nw[] = { -3, -1, 0, 1, 2, 3, 4, 5, 6, 10, 11, 12, 13, 20, 33, 50 };
	static const int ix[] = { -2, -1, 0, 1, 2, 3, 4, 5, 9, 10, 11, 12, 19, 32, 49, 60 };
	static const int gp[] = { 0, 1, 8, 40, 500 };
	static const int mh[] = { 0, 1, 60, 100, 900 };
	for (i0 = 0; i0 < N(vh); i0++)
	for (i1 = 0; i1 < N(nw); i1++)
	for (i2 = 0; i2 < N(ix); i2++)
	for (i3 = 0; i3 < N(gp); i3++)
	for (i4 = 0; i4 < N(mh); i4++) {
		int ref = ribbon_policy_height(vh[i0], nw[i1], ix[i2], gp[i3], mh[i4]);
		snprintf(lab, sizeof lab, "height %d %d %d %d %d",
		    vh[i0], nw[i1], ix[i2], gp[i3], mh[i4]);
		fresh();
		st = geometry_vysota_okna(&ctx, fl_number(vh[i0]), fl_number(nw[i1]),
		    fl_number(ix[i2]), fl_number(gp[i3]), fl_number(mh[i4]), &r, &e);
		one(lab, ref, st, r, &e);
	}
	}

	/* 7. Куда класть окно. Признаки гоняются не только по 0 и 1: у эталона
	 * правдой считается любое ненулевое. */
	{
	static const int fl[] = { -1, 0, 1, 2, 7 };
	static const int ru[] = { -1, 0, 1, 2, 3, 7 };
	int a, b, c, d, f;
	for (a = 0; a < N(fl); a++)
	for (b = 0; b < N(fl); b++)
	for (c = 0; c < N(fl); c++)
	for (d = 0; d < N(fl); d++)
	for (f = 0; f < N(fl); f++)
	for (i0 = 0; i0 < N(ru); i0++) {
		int ref = ribbon_policy_insert(fl[a], fl[b], fl[c], fl[d], fl[f], ru[i0]);
		snprintf(lab, sizeof lab, "insert %d %d %d %d %d %d",
		    fl[a], fl[b], fl[c], fl[d], fl[f], ru[i0]);
		fresh();
		st = placement_kuda_polozhit_okno(&ctx, fl_number(fl[a]), fl_number(fl[b]),
		    fl_number(fl[c]), fl_number(fl[d]), fl_number(fl[f]),
		    fl_number(ru[i0]), &r, &e);
		one(lab, ref, st, r, &e);
	}
	}

	/* 8. Фокус после закрытия. */
	{
	static const int ix[] = { -5, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11,
	    12, 15, 20, 33, 50, 100 };
	static const int nc[] = { -3, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 20, 50, 101 };
	static const int fg[] = { -1, 0, 1, 2 };
	for (i0 = 0; i0 < N(ix); i0++)
	for (i1 = 0; i1 < N(nc); i1++)
	for (i2 = 0; i2 < N(fg); i2++)
	for (i3 = 0; i3 < N(fg); i3++) {
		int ref = ribbon_policy_close(ix[i0], nc[i1], fg[i2], fg[i3]);
		snprintf(lab, sizeof lab, "close %d %d %d %d",
		    ix[i0], nc[i1], fg[i2], fg[i3]);
		fresh();
		st = placement_fokus_posle_zakrytiya(&ctx, fl_number(ix[i0]), fl_number(nc[i1]),
		    fl_number(fg[i2]), fl_number(fg[i3]), &r, &e);
		one(lab, ref, st, r, &e);
	}
	}

	/* 9. Встречаются ли полоса панели и область. */
	{
	static const int sp[] = { -100, -1, 0, 1, 2, 40, 49, 50, 51, 99, 100, 101,
	    150, 199, 200, 300, 800, 1600, 2000, 4000 };
	static const int po[] = { -100, -1, 0, 1, 2, 40, 49, 50, 51, 99, 100, 101,
	    150, 199, 200, 300, 800, 1600, 2000, 4000 };
	static const int ln[] = { -3, -1, 0, 1, 2, 3, 40, 50, 100, 101, 200, 800,
	    1600, 4000, 5, 7 };
	for (i0 = 0; i0 < N(sp); i0++)
	for (i1 = 0; i1 < N(sp); i1++)
	for (i2 = 0; i2 < N(po); i2++)
	for (i3 = 0; i3 < N(ln); i3++) {
		int ref = ribbon_policy_span(sp[i0], sp[i1], po[i2], ln[i3]);
		snprintf(lab, sizeof lab, "span %d %d %d %d",
		    sp[i0], sp[i1], po[i2], ln[i3]);
		fresh();
		st = strut_polosa_vstrechaet_oblast(&ctx, fl_number(sp[i0]), fl_number(sp[i1]),
		    fl_number(po[i2]), fl_number(ln[i3]), &r, &e);
		one(lab, ref, st, r, &e);
	}
	}

	/* 10. Сколько панель отнимает у одного края. */
	{
	static const int sr[] = { -100, -1, 0, 1, 2, 28, 40, 60, 100, 400, 800, 801,
	    900, 1000, 2000, 4000 };
	static const int sc[] = { -10, 0, 1, 40, 100, 400, 800, 801, 1200, 1600, 4000, 7 };
	static const int po[] = { -100, -1, 0, 1, 8, 28, 40, 100, 400, 800, 1200, 2000, 3 };
	static const int ln[] = { -5, -1, 0, 1, 8, 28, 40, 100, 400, 720, 800, 1600, 4000 };
	static const int fr[] = { -1, 0, 1, 2 };
	for (i0 = 0; i0 < N(sr); i0++)
	for (i1 = 0; i1 < N(sc); i1++)
	for (i2 = 0; i2 < N(po); i2++)
	for (i3 = 0; i3 < N(ln); i3++)
	for (i4 = 0; i4 < N(fr); i4++) {
		int ref = ribbon_policy_reserve(sr[i0], sc[i1], po[i2], ln[i3], fr[i4]);
		snprintf(lab, sizeof lab, "reserve %d %d %d %d %d",
		    sr[i0], sc[i1], po[i2], ln[i3], fr[i4]);
		fresh();
		st = strut_skolko_otnyat(&ctx, fl_number(sr[i0]), fl_number(sc[i1]),
		    fl_number(po[i2]), fl_number(ln[i3]), fl_number(fr[i4]), &r, &e);
		one(lab, ref, st, r, &e);
	}
	}

	/* 11. Что остаётся паре панелей друг напротив друга. */
	{
	static const int nf[] = { -100, -5, -1, 0, 1, 2, 8, 20, 28, 39, 40, 41, 50,
	    60, 100, 200, 400, 800, 1600, 4000 };
	static const int ln[] = { -100, -5, -1, 0, 1, 2, 20, 39, 40, 41, 56, 100,
	    400, 800, 1600, 4000 };
	static const int wf[] = { -1, 0, 1, 2 };
	for (i0 = 0; i0 < N(nf); i0++)
	for (i1 = 0; i1 < N(nf); i1++)
	for (i2 = 0; i2 < N(ln); i2++)
	for (i3 = 0; i3 < N(wf); i3++) {
		int ref = ribbon_policy_pair(nf[i0], nf[i1], ln[i2], wf[i3]);
		snprintf(lab, sizeof lab, "pair %d %d %d %d",
		    nf[i0], nf[i1], ln[i2], wf[i3]);
		fresh();
		st = strut_dolya_pary(&ctx, fl_number(nf[i0]), fl_number(nf[i1]),
		    fl_number(ln[i2]), fl_number(wf[i3]), &r, &e);
		one(lab, ref, st, r, &e);
	}
	}

	/* 12. «Пара вместе» — единственная функция без счётчика в эталоне.
	 * Она складывает обе доли пары и несёт теорему, которую порознь ни одна
	 * половина высказать не может. Сверять не с чем, поэтому проверяется
	 * собой: постусловие пересчитывается в напечатанном коде, и требуется,
	 * чтобы оно не сработало НИ РАЗУ. */
	{
	static const int nf[] = { -100, -5, -1, 0, 1, 2, 8, 20, 28, 39, 40, 41, 50,
	    60, 100, 200, 400, 800 };
	static const int ln[] = { -100, -5, -1, 0, 1, 2, 20, 39, 40, 41, 56, 100,
	    400, 800 };
	for (i0 = 0; i0 < N(nf); i0++)
	for (i1 = 0; i1 < N(nf); i1++)
	for (i2 = 0; i2 < N(ln); i2++) {
		fresh();
		st = strut_para_vmeste(&ctx, fl_number(nf[i0]), fl_number(nf[i1]),
		    fl_number(ln[i2]), &r, &e);
		pair_total++;
		if (st != FL_OK) {
			pair_bad++;
			if (pair_bad <= 5)
				fprintf(stderr, "ТЕОРЕМА ПАРЫ НЕ ДЕРЖИТ  %d %d %d: %s\n",
				    nf[i0], nf[i1], ln[i2], e.code ? e.code : "?");
		}
	}
	}

	fl_arena_release(&arena);
	if (fclose(fa) != 0 || fclose(fb) != 0) {
		perror("fclose");
		return 2;
	}
	printf("%lld %lld %lld %lld\n", total, bad, pair_total, pair_bad);
	return (bad == 0 && pair_bad == 0) ? 0 : 1;
}
EOF

( cd "$work/build" && $CC -std=c99 -Wall -Wextra -Werror -pedantic -O2 \
    -o driver driver.c viewport.c geometry.c placement.c strut.c \
    flang_runtime.c policy.o -lm -lpthread )
echo "прогонщик собран"

# ── 5. Прогон ───────────────────────────────────────────────────────────────
set +e
out=$("$work/build/driver" "$work/ref.txt" "$work/flang.txt" 2>"$work/diffs.txt")
code=$?
set -e
total=$(echo "$out" | awk '{print $1}')
bad=$(echo "$out" | awk '{print $2}')
pair_total=$(echo "$out" | awk '{print $3}')
pair_bad=$(echo "$out" | awk '{print $4}')

echo
echo "сверено входов: $total"
echo "расхождений:    $bad"
echo "теорема пары («Пара вместе», счётчика в эталоне нет): проверена на $pair_total входах, не сработала $pair_bad раз"

if [ "$code" != "0" ] || [ "${bad:-1}" != "0" ] || [ "${pair_bad:-1}" != "0" ]; then
  err "СВЕРКА НЕ СОШЛАСЬ. Первые расхождения:"
  head -20 "$work/diffs.txt" >&2
  exit 1
fi

# Второй способ, независимый от арифметики самого прогонщика: два потока
# ответов сравниваются побайтно посторонней программой.
if ! cmp -s "$work/ref.txt" "$work/flang.txt"; then
  err "потоки ответов разошлись побайтно, хотя прогонщик насчитал ноль:"
  diff "$work/ref.txt" "$work/flang.txt" | head -20 >&2
  exit 1
fi
lines=$(wc -l < "$work/ref.txt")
bytes=$(wc -c < "$work/ref.txt")
echo "потоки ответов совпали побайтно: строк $lines, байт $bytes (cmp)"

# Отрицательный контроль СВЕРКИ: если бы ответы расходились, `cmp` обязан это
# увидеть. Портим копию одного потока и требуем, чтобы сверка покраснела.
sed '3s/= \(-\{0,1\}[0-9]*\)$/= 999999/' "$work/flang.txt" > "$work/spoilt.txt"
if cmp -s "$work/ref.txt" "$work/spoilt.txt"; then
  err "отрицательный контроль не сработал: порченый поток признан совпавшим"
  exit 1
fi
echo "отрицательный контроль: порченый поток отвергается — сверка умеет краснеть"

echo
echo "Перенос совпадает с эталоном на всех $total входах. Расхождений ноль."

# ── 6. То же самое, но напечатанное в Go ────────────────────────────────────
# «Печатается в Go» стоит ровно столько, сколько за ним проверено. Здесь
# напечатанный Go отвечает на ТЕ ЖЕ входы, и его ответы сверяются с ответами
# ЭТАЛОНА — тем же `cmp`, тем же потоком байтов. Go нет — сказано вслух, а не
# пропущено молча.
if ! command -v go >/dev/null 2>&1; then
  echo
  echo "Go на машине нет: печать в Go не сверена. Это ПРОПУСК, а не успех."
  exit 0
fi

echo
gomods=0
for f in "$ROOT"/flang/*.flang; do
  m=$(basename "$f" .flang)
  "$FLANG" emit "$f" --target go --out "$work/go-$m" >"$work/emit.log" 2>&1 || {
    err "печать в Go отказала: $m"; cat "$work/emit.log" >&2; exit 1; }
  # У Go путь файла — имя пакета; у всех модулей оно одно и то же
  # («flangprogram»), и четыре модуля рядом не собрались бы. Приём взят у
  # `flang-tui`: имя модуля делается своим.
  grep -rl flangprogram "$work/go-$m" | while read -r x; do
    sed -i.bak "s|flangprogram|flang$m|g" "$x" && rm -f "$x.bak"
  done
  # `-buildvcs=false` — не украшение: собирается напечатанное во временном
  # каталоге, никакого репозитория при нём нет, а go всё равно зовёт `git` и
  # падает «error obtaining VCS status: exit status 128» на машинах, где git в
  # /tmp отвечает 128. Отпечаток VCS в оснастке сверки не нужен вовсе.
  ( cd "$work/go-$m" && go build -buildvcs=false -o "$work/gocli-$m" ./cli )
  gomods=$((gomods + 1))
done
echo "напечатано в Go модулей: $gomods, прогонщики собраны (сверяются четыре: у"
echo "  «Ribbon» счётчика в эталоне нет — его сверяет ./ярлык вставка)"

# Из потока эталона делаем запросы к напечатанному Go: имя функции flang плюс
# доводы числами. Порядок строк сохраняется в order.txt, чтобы потом собрать
# ответы обратно ровно в том же порядке.
awk -v work="$work" '
function reqfile(mod) { return work "/req." mod }
{
  eq = index($0, " = ")
  label = substr($0, 1, eq - 1)
  n = split(label, part, " ")
  kind = part[1]
  if (kind == "offset")        { mod = "viewport";  fn = "Смещение" }
  else if (kind == "voffset")  { mod = "viewport";  fn = "Смещение по стопке" }
  else if (kind == "output")   { mod = "viewport";  fn = "Смещение после смены окна" }
  else if (kind == "width")    { mod = "geometry";  fn = "Ширина колонки по пресету" }
  else if (kind == "widthpct") { mod = "geometry";  fn = "Ширина колонки" }
  else if (kind == "height")   { mod = "geometry";  fn = "Высота окна" }
  else if (kind == "insert")   { mod = "placement"; fn = "Куда положить окно" }
  else if (kind == "close")    { mod = "placement"; fn = "Фокус после закрытия" }
  else if (kind == "span")     { mod = "strut";     fn = "Полоса встречает область" }
  else if (kind == "reserve")  { mod = "strut";     fn = "Сколько отнять" }
  else if (kind == "pair")     { mod = "strut";     fn = "Доля пары" }
  else { print "неизвестная политика в потоке: " kind > "/dev/stderr"; exit 1 }

  args = ""
  for (i = 2; i <= n; i++) {
    v = part[i]
    gsub(/[\[\]]/, "", v)
    if (v == "") continue
    args = args (args == "" ? "" : ",") "{\"n\":\"" v "\"}"
  }
  print "{\"fn\":\"" fn "\",\"args\":[" args "]}" >> reqfile(mod)
  print mod " " label > (work "/order.txt")
}
' "$work/ref.txt"

for m in viewport geometry placement strut; do
  [ -f "$work/req.$m" ] || { err "для модуля $m не собрано ни одного запроса"; exit 1; }
  "$work/gocli-$m" < "$work/req.$m" > "$work/ans.$m"
done

awk -v work="$work" '
{
  mod = $1
  label = substr($0, index($0, " ") + 1)
  file = work "/ans." mod
  if ((getline line < file) <= 0) { print "ответы Go кончились раньше входов" > "/dev/stderr"; exit 1 }
  if (match(line, /"n":"[^"]*"/)) {
    got = substr(line, RSTART + 5, RLENGTH - 6)
  } else if (match(line, /"code":"[^"]*"/)) {
    got = "БЕДА " substr(line, RSTART + 8, RLENGTH - 9)
  } else {
    got = "НЕ ЧИСЛО"
  }
  print label " = " got
}
' "$work/order.txt" > "$work/go.txt"

if ! cmp -s "$work/ref.txt" "$work/go.txt"; then
  err "напечатанное в Go разошлось с эталоном:"
  diff "$work/ref.txt" "$work/go.txt" | head -20 >&2
  exit 1
fi
golines=$(wc -l < "$work/go.txt")
echo "напечатанное в Go совпало с эталоном побайтно: строк $golines (cmp)"

# Отрицательный контроль и для этой ветки.
sed '5s/= \(-\{0,1\}[0-9]*\)$/= 999999/' "$work/go.txt" > "$work/go-spoilt.txt"
if cmp -s "$work/ref.txt" "$work/go-spoilt.txt"; then
  err "отрицательный контроль ветки Go не сработал"
  exit 1
fi
echo "отрицательный контроль ветки Go: порченый поток отвергается"

echo
echo "Три реализации одной арифметики — эталон на C, напечатанное из flang в C"
echo "и напечатанное из flang в Go — дали один и тот же поток байт на $total входах."
