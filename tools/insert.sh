#!/bin/sh
# SPDX-FileCopyrightText: 2026 Marat Zimnurov <zimtir@mail.ru>
# SPDX-License-Identifier: BSD-2-Clause
#
# СВЕРКА ВСТАВКИ ОКНА С ЖИВЫМ ОКОННЫМ МЕНЕДЖЕРОМ.
#
# `tools/insert.flang` — план: он печатает то же, что печатает
# `layout-probe layout ... insert=`, и сверяет два потока байт. Звать его прямо
# нельзя: план зовёт `../cwm` от каталога своего файла, а двоичного оконного
# менеджера в этом дереве нет и быть не должно — он собирается у хозяина и
# требует X11. Этот скрипт собирает временное дерево нужной формы:
#
#   $work/flang/*.flang     модули (план тянет ../flang/ribbon.flang)
#   $work/tools/insert.flang план
#   $work/cwm                оконный менеджер хозяина
#
# Рабочее дерево не трогается ни разу.
#
# Запуск:  DIGITWM=/путь/к/клону sh tools/insert.sh
#          CWM=/путь/к/cwm       sh tools/insert.sh
# Выход:   0 — все сценарии сошлись знак в знак; 1 — назван сценарий и первая
#          разошедшаяся строка; 3 — нечем сверять.
#
# ИМЕНА ПЕРЕМЕННЫХ ЛАТИНИЦЕЙ: ни dash, ни bash не принимают кириллицу в именах.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

err() { printf '%s\n' "$*" >&2; }

if [ -z "${FLANG:-}" ]; then
  if [ -n "${FLANG_HOME:-}" ]; then FLANG=$FLANG_HOME/bootstrap/flang; else FLANG=flang; fi
fi
export FLANG
command -v "$FLANG" >/dev/null 2>&1 || { err "компилятора flang нет: «$FLANG»"; exit 3; }

# Оконный менеджер — ВНЕШНЕЕ УСЛОВИЕ, и молчаливого пропуска здесь нет:
# пропущенная сверка это пропуск, а не успех.
if [ -z "${CWM:-}" ]; then
  if [ -n "${DIGITWM:-}" ]; then CWM=$DIGITWM/cwm; else CWM=; fi
fi
if [ -z "$CWM" ] || [ ! -x "$CWM" ]; then
  err "нечем сверять: нужен собранный двоичный digitwm."
  err ""
  err "  git clone https://github.com/digitable-lol/digitwm && make -C digitwm"
  err "  DIGITWM=путь/к/digitwm sh tools/insert.sh"
  err ""
  err "Прямо указать двоичный: CWM=путь/к/cwm sh tools/insert.sh"
  exit 3
fi

# Он обязан уметь layout-probe: старый двоичный ответил бы «неизвестная
# команда», и сверка сказала бы «расхождение» вместо «не с чем сверять».
if ! "$CWM" -C "layout-probe layout viewport=100x100 columns=1" >/dev/null 2>&1; then
  err "«$CWM» не понимает layout-probe — это не тот двоичный или он слишком стар"
  exit 3
fi

work=
cleanup() { if [ -n "$work" ]; then rm -rf "$work"; fi; }
trap cleanup EXIT INT TERM
work=$(mktemp -d "${TMPDIR:-/tmp}/flang-ribbon-insert.XXXXXXXX")

mkdir -p "$work/flang" "$work/tools"
cp "$ROOT"/flang/*.flang "$work/flang/"
cp "$ROOT/tools/insert.flang" "$work/tools/"
cp "$CWM" "$work/cwm"

echo "оконный менеджер: $CWM"
exec "$FLANG" io "$work/tools/insert.flang"
