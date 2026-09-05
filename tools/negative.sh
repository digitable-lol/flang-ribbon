#!/bin/sh
# SPDX-FileCopyrightText: 2026 Marat Zimnurov <zimtir@mail.ru>
# SPDX-License-Identifier: BSD-2-Clause
#
# ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ: проверка, которую нечем уронить, не отличима от
# отсутствующей.
#
# На каждую проверку дерева здесь ломается ровно то, что она обязана поймать,
# и требуется КРАСНОЕ. Ломается всегда КОПИЯ: рабочее дерево не трогается
# ни разу, и `git status` после прогона обязан остаться пустым.
#
# Девять контролей:
#   1. примеры внутри модулей — подменённый ответ роняет `flang test`;
#   2. типы — чужой тип роняет `flang check`;
#   3. постусловие — заведомо ложное `обеспечивает` роняет прогон примеров;
#   4. ведомость — сломанный модуль роняет `flang check --proof`, И ПРИТОМ
#      показано, что тот же самый прогон через `| tail -8` отдал бы НОЛЬ;
#   5. печать — сломанный модуль роняет `flang emit` и не пишет ни файла;
#   6. лицензионный сторож — подложенные копилефт и чужой язык роняют его,
#      и он читает РОВНО столько файлов, сколько их в дереве;
#   7. сверка — перевранная арифметика роняет прогон против эталона;
#   8. вставка — ПОРТИТСЯ ОТВЕТ C, и сверка лент обязана заметить и назвать
#      строку; отдельной порчей проверяется, что сверяется и состояние ПОСЛЕ
#      вставки, а не одно начальное;
#   9. сетка — заведомо ложное обещание ленты роняет обход 896 лент.
#
# Запуск:  sh tools/negative.sh
# Выход:   0 — каждая проверка покраснела как надо; 1 — какая-то не смогла.
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

work=
cleanup() { if [ -n "$work" ]; then rm -rf "$work"; fi; }
trap cleanup EXIT INT TERM
work=$(mktemp -d "${TMPDIR:-/tmp}/flang-ribbon-negative.XXXXXXXX")

passed=0
fail() { err "ОТРИЦАТЕЛЬНЫЙ КОНТРОЛЬ НЕ СРАБОТАЛ: $*"; exit 1; }
ok() { passed=$((passed + 1)); printf '  %s\n' "$*"; }

# Выполнить и вернуть код, не роняя скрипт.
code_of() {
  set +e
  "$@" >"$work/out.txt" 2>&1
  c=$?
  set -e
  return $c
}

echo "отрицательный контроль: ломаем копию, требуем красного"
echo

# ── 1. Примеры внутри модулей ───────────────────────────────────────────────
mkdir -p "$work/case1"
sed 's/^    ожидается 668$/    ожидается 669/' "$ROOT/flang/viewport.flang" > "$work/case1/viewport.flang"
cmp -s "$ROOT/flang/viewport.flang" "$work/case1/viewport.flang" &&
  fail "порча примера ничего не изменила — поменялся текст модуля"
if code_of "$FLANG" test "$work/case1/viewport.flang"; then
  fail "подменённый ответ примера прошёл «flang test»"
fi
grep -q "не прошло 1" "$work/out.txt" ||
  err "  (предупреждение: «flang test» покраснел, но не назвал один непрошедший пример)"
ok "1. примеры: подменённый ответ роняет «flang test»"

# ── 2. Типы ─────────────────────────────────────────────────────────────────
mkdir -p "$work/case2"
sed 's/^  если сверху меньше 0 то 0 иначе сверху$/  если сверху меньше 0 то "ноль" иначе сверху/' \
    "$ROOT/flang/viewport.flang" > "$work/case2/viewport.flang"
cmp -s "$ROOT/flang/viewport.flang" "$work/case2/viewport.flang" &&
  fail "порча типа ничего не изменила"
if code_of "$FLANG" check "$work/case2/viewport.flang"; then
  fail "строка вместо числа прошла «flang check»"
fi
ok "2. типы: строка вместо числа роняет «flang check»"

# ── 3. Постусловие ──────────────────────────────────────────────────────────
mkdir -p "$work/case3"
sed 's/^  обеспечивает «смещение не уходит влево от начала холста» результат не меньше 0$/  обеспечивает «смещение не уходит влево от начала холста» результат больше 1000000/' \
    "$ROOT/flang/viewport.flang" > "$work/case3/viewport.flang"
cmp -s "$ROOT/flang/viewport.flang" "$work/case3/viewport.flang" &&
  fail "порча постусловия ничего не изменила"
if code_of "$FLANG" test "$work/case3/viewport.flang"; then
  fail "заведомо ложное «обеспечивает» прошло прогон примеров"
fi
ok "3. постусловие: заведомо ложное «обеспечивает» роняет прогон примеров"

# ── 4. Ведомость — и ловушка с конвейером ───────────────────────────────────
if code_of "$FLANG" check --proof "$work/case2/viewport.flang"; then
  fail "ведомость сломанного модуля отдала ноль"
fi
ok "4. ведомость: сломанный модуль роняет «flang check --proof»"

# А теперь то, ради чего этот контроль вообще написан. Ровно та же команда,
# но с конвейером — и код возврата уже не её, а `tail`.
set +e
"$FLANG" check --proof "$work/case2/viewport.flang" 2>&1 | tail -8 >/dev/null
piped=$?
set -e
if [ "$piped" != "0" ]; then
  err "  (в этой оболочке конвейер отдал $piped, а не ноль: ловушка не воспроизвелась,"
  err "   но правило «ни одного | над проверяющей командой» остаётся в силе)"
else
  ok "   ТА ЖЕ команда через «| tail -8» отдала 0 — вот почему в конвейере нет ни одного «|»"
fi

# ── 5. Печать ───────────────────────────────────────────────────────────────
if code_of "$FLANG" emit "$work/case2/viewport.flang" --target c --out "$work/case5"; then
  fail "печать сломанного модуля прошла"
fi
if [ -d "$work/case5" ] && [ -n "$(ls -A "$work/case5" 2>/dev/null)" ]; then
  fail "печать отказала, но файлы всё-таки записала"
fi
ok "5. печать: сломанный модуль роняет «flang emit» и не пишет ни файла"

# ── 6. Лицензионный сторож ──────────────────────────────────────────────────
# Сторож спрашивает список у `git ls-files`, поэтому копия дерева заводится
# своим репозиторием. Рабочее дерево не трогается.
mkdir -p "$work/tree"
( cd "$ROOT" && git ls-files -z ) | ( cd "$ROOT" && xargs -0 tar cf - ) | ( cd "$work/tree" && tar xf - )
( cd "$work/tree" && git init -q && git add -A && git -c user.name=n -c user.email=n@n commit -qm x )

if ! code_of sh -c "cd '$work/tree/tools' && '$FLANG' io licensing.flang"; then
  err "чистая копия дерева не прошла сторожа:"; cat "$work/out.txt" >&2
  fail "сторож ругается на нетронутое дерево — контроль бессмыслен"
fi
listed=$(cd "$work/tree" && git ls-files | wc -l)
read_n=$(grep -o '"Прочитать файл"' "$work/out.txt" | wc -l)
[ "$listed" -eq "$read_n" ] ||
  fail "сторож прочитал $read_n файлов из $listed — часть дерева он не смотрел"
ok "6. сторож: на чистой копии зелёный и прочитал все $listed файлов"

# Примета собирается по частям: напиши её здесь целиком — и сторож справедливо
# заругался бы на сам этот файл.
printf 'GPL%s3.0\n' '-' > "$work/tree/POISON.txt"
( cd "$work/tree" && git add -A )
if code_of sh -c "cd '$work/tree/tools' && '$FLANG' io licensing.flang"; then
  fail "подложенный копилефт сторожа не уронил"
fi
rm -f "$work/tree/POISON.txt"
ok "   подложенный копилефт роняет сторожа"

printf 'print(1)\n' > "$work/tree/poison.py"
( cd "$work/tree" && git add -A )
if code_of sh -c "cd '$work/tree/tools' && '$FLANG' io licensing.flang"; then
  fail "подложенный чужой язык сторожа не уронил"
fi
rm -f "$work/tree/poison.py"
ok "   подложенный чужой язык роняет сторожа"

printf 'int main(void) { return 0; }\n' > "$work/tree/poison.c"
( cd "$work/tree" && git add -A )
if code_of sh -c "cd '$work/tree/tools' && '$FLANG' io licensing.flang"; then
  fail "подложенный рукописный C сторожа не уронил"
fi
rm -f "$work/tree/poison.c"
( cd "$work/tree" && git add -A )
ok "   подложенный рукописный C роняет сторожа"

# ── 7. Сверка ───────────────────────────────────────────────────────────────
# Самый дорогой контроль и самый нужный: если перевранная арифметика проходит
# сверку, сверка ничего не значит.
if [ "${RIBBON_SKIP_COMPARE:-}" = "1" ]; then
  echo "  7. сверка: пропущена по RIBBON_SKIP_COMPARE=1 — это ПРОПУСК, а не успех"
else
  sed -i.bak 's/^  пусть отступ равно (если (ширина плюс зазор) больше окно то 0 иначе зазор)$/  пусть отступ равно (если (ширина плюс зазор) больше окно то 1 иначе зазор)/' \
      "$work/tree/flang/viewport.flang"
  rm -f "$work/tree/flang/viewport.flang.bak"
  cmp -s "$ROOT/flang/viewport.flang" "$work/tree/flang/viewport.flang" &&
    fail "порча арифметики ничего не изменила"
  if code_of sh "$work/tree/tools/compare.sh"; then
    fail "перевранная арифметика прошла сверку с эталоном"
  fi
  grep -q "РАСХОЖДЕНИЕ" "$work/out.txt" ||
    fail "сверка покраснела, но ни одного расхождения не назвала"
  ok "7. сверка: перевранная арифметика роняет прогон против эталона"
fi

# ── 8. Вставка: портится ОТВЕТ C ────────────────────────────────────────────
# ПОЧЕМУ ИМЕННО ОТВЕТ C, А НЕ СПЕКА. У flang примеры спеки И ЕСТЬ векторы,
# поэтому всякая порча спеки валится раньше — на её собственных примерах — и о
# сверке не говорит ничего. Сверка стоит ровно за тем, чего примеры не ловят:
# за расхождением, пришедшим СО СТОРОНЫ C. Его и надо подделать. Подделка не
# требует пересборки: `cwm` подменяется оболочкой, которая зовёт настоящий и
# правит одно число в ответе. Спека при этом не тронута ни буквой.
if [ -z "${CWM:-}" ] && [ -n "${DIGITWM:-}" ]; then CWM=$DIGITWM/cwm; fi
if [ -z "${CWM:-}" ] || [ ! -x "${CWM:-}" ]; then
  echo "  8. вставка: пропущена — нет собранного cwm (DIGITWM= или CWM=). Это ПРОПУСК, а не успех"
  echo "  9. сетка: считается ниже отдельно"
else
  mkdir -p "$work/ins/flang" "$work/ins/tools"
  cp "$ROOT"/flang/*.flang "$work/ins/flang/"
  cp "$ROOT/tools/insert.flang" "$work/ins/tools/"

  # mutant <имя> <программа awk> <что обязано быть в жалобе>
  mutant() {
    name=$1; program=$2; want=$3
    {
      printf '%s\n' '#!/bin/sh'
      printf '"%s" "$@" | awk %s\n' "$CWM" "'$program'"
    } > "$work/ins/cwm"
    chmod +x "$work/ins/cwm"
    if code_of "$FLANG" io "$work/ins/tools/insert.flang"; then
      fail "порча «$name» сверку не уронила"
    fi
    if ! grep -q -- "$want" "$work/out.txt"; then
      err "жалоба: $(cut -c1-400 "$work/out.txt")"
      fail "порча «$name» сверку уронила, но в жалобе нет «$want»"
    fi
    ok "   $name — замечено, и названо «$want»"
  }

  # Сперва — что на НЕТРОНУТОМ ответе сверка зелёная. Иначе красное ниже
  # не значило бы ничего: оно могло бы быть красным всегда.
  printf '%s\n' '#!/bin/sh' > "$work/ins/cwm"
  printf '"%s" "$@"\n' "$CWM" >> "$work/ins/cwm"
  chmod +x "$work/ins/cwm"
  if ! code_of "$FLANG" io "$work/ins/tools/insert.flang"; then
    err "$(cut -c1-400 "$work/out.txt")"
    fail "нетронутый ответ C сверку не прошёл — контроль бессмыслен"
  fi
  ok "8. вставка: на нетронутом ответе C сверка зелёная"

  mutant "окно просмотра другое" \
    '{ if ($1 == "viewport") { $4 = $4 + 1 }; print }' \
    'строка 3: спека «viewport'
  mutant "смещение ленты на единицу больше" \
    '{ if ($1 == "ribbon") { $5 = $5 + 1 }; print }' \
    'строка 6: спека «ribbon length'
  mutant "высота полотна на единицу больше" \
    '{ if ($1 == "ribbon") { $11 = $11 + 1 }; print }' \
    'строка 6: спека «ribbon length'
  mutant "ширина колонки на единицу больше" \
    '{ if ($1 == "column") { $6 = $6 + 1 }; print }' \
    'строка 7: спека «column'
  mutant "окно на ленте съехало" \
    '{ if ($1 == "window") { $6 = $6 + 1 }; print }' \
    'строка 8: спека «window'
  mutant "окно на экране съехало" \
    '{ if ($1 == "window") { $11 = $11 + 1 }; print }' \
    'строка 8: спека «window'

  # ГЛАВНАЯ ПОРЧА ЭТОГО КОНТРОЛЯ. Все шесть выше правят и начальное состояние
  # тоже, и сверка могла бы ловить их одним лишь первым состоянием — тогда про
  # ВСТАВКУ она не говорила бы ничего. Эта правит ТОЛЬКО то, что напечатано
  # после `stage column`, то есть ровно ответ `ribbon_insert()`.
  mutant "тронуто только состояние ПОСЛЕ вставки" \
    '/^stage column/ { after = 1 } { if (after && $1 == "column") { $6 = $6 + 1 }; print }' \
    'строка 21: спека «column'
fi

# ── 9. Сетка обещаний ───────────────────────────────────────────────────────
# Обход 896 лент пересчитывает оба обещания на каждом вызове `«Вставить окно»`.
# Ужесточённое до неправды обещание обязано его уронить — иначе обход считает
# ленты, а не проверяет что-либо. Ломается КОПИЯ модуля.
#
# ЗОВЁТСЯ `flang run`, А НЕ `flang test`, И ЭТО ВАЖНО. `test` прогнал бы заодно
# 99 примеров самого модуля, и красное могло бы прийти от них, а не от обхода;
# `run` примеры НЕ считает (проверено), поэтому единственное, что может здесь
# покраснеть, — постусловие на одной из 896 лент. Жалоба обязана назвать
# обещание по имени.
mkdir -p "$work/grid/flang" "$work/grid/tools"
cp "$ROOT"/flang/*.flang "$work/grid/flang/"
cp "$ROOT/tools/grid.flang" "$work/grid/tools/"
sed -i.bak 's/и притом (голова.высота равен образец.высота)/и притом (голова.высота больше образец.высота)/' \
    "$work/grid/flang/ribbon.flang"
rm -f "$work/grid/flang/ribbon.flang.bak"
cmp -s "$ROOT/flang/ribbon.flang" "$work/grid/flang/ribbon.flang" &&
  fail "ужесточение обещания ничего не изменило — текст модуля поехал"
if code_of "$FLANG" run "$work/grid/tools/grid.flang" --function '«Сетка обещаний»'; then
  fail "ужесточённое до неправды обещание обход сетки не уронило"
fi
grep -q "FLANG_PROPERTY" "$work/out.txt" ||
  fail "обход сетки покраснел, но не постусловием: $(cut -c1-300 "$work/out.txt")"
grep -q "не меняет геометрию ни одного окна" "$work/out.txt" ||
  fail "обход покраснел постусловием, но не тем: $(cut -c1-300 "$work/out.txt")"
ok "9. сетка: ужесточённое до неправды обещание роняет обход 896 лент, и названо по имени"

echo
echo "отрицательных контролей пройдено: $passed"
echo "Рабочее дерево не тронуто ни разу — ломались только копии."
