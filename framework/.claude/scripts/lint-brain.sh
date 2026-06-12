#!/usr/bin/env bash
# Линт целостности brain: битые wikilinks, битые markdown-пути в INDEX.md,
# отсутствующие файлы из таблицы rules/ondemand-rules.md;
# предупреждения (не ошибки): знания-сироты вне INDEX.md, знания без даты проверки.
# Запускается шагами /retro и /evolve; можно руками: .claude/scripts/lint-brain.sh
#
# ВАЖНО: brain может быть симлинком — все find ТОЛЬКО с -L
# (find без -L молча не спускается в симлинк и даёт ложные «файла нет»).
set -u

BRAIN="$(cat "$HOME/.claude/brain-dir" 2>/dev/null || true)"
[ -n "$BRAIN" ] || BRAIN="$HOME/brain"
BRAIN=$(readlink -f "$BRAIN")
fail=0

# --- 1) wikilinks в курируемых слоях ---
# Скоуп: rules/, rules-ondemand/, knowledge/, learning/, INDEX.md, CONVENTIONS.md.
# Журналы tasks/ не линтуем (append-only архив, прошлые записи не правятся).
lint_files=$( { find -L "$BRAIN/rules" "$BRAIN/rules-ondemand" "$BRAIN/knowledge" "$BRAIN/learning" -name '*.md' 2>/dev/null; printf '%s\n' "$BRAIN/INDEX.md" "$BRAIN/CONVENTIONS.md"; } )

while IFS= read -r f; do
  [ -f "$f" ] || continue
  # inline-код `...` вырезаем: там [[wikilinks]]-иллюстрации, не ссылки
  targets=$(sed 's/`[^`]*`//g' "$f" | grep -oE '\[\[[^]|#]+' | sed 's/^\[\[//' | sort -u)
  [ -z "$targets" ] && continue
  while IFS= read -r t; do
    [ -z "$t" ] && continue
    case "$t" in *'<'*) continue;; esac   # плейсхолдеры вида [[projects/<id>]]
    case "$t" in [A-Z]) continue;; esac   # иллюстративные [[X]], [[Y]] в прозе CONVENTIONS
    if [ -e "$BRAIN/$t.md" ] || [ -e "$BRAIN/$t" ]; then continue; fi
    base=$(basename "$t")
    if [ -n "$(find -L "$BRAIN" -name "$base.md" -not -path '*/.git/*' -print -quit 2>/dev/null)" ]; then continue; fi
    echo "BROKEN WIKILINK: [[$t]] — ${f#"$BRAIN"/}"
    fail=1
  done <<<"$targets"
done <<<"$lint_files"

# --- 2) markdown-ссылки на файлы brain в INDEX.md ---
idx_links=$(grep -oE '\]\([^)]+\)' "$BRAIN/INDEX.md" | sed -e 's/^](//' -e 's/)$//' -e 's/#.*$//' | grep -v -E '^https?://' | sort -u)
while IFS= read -r p; do
  [ -z "$p" ] && continue
  [ -e "$BRAIN/$p" ] || { echo "BROKEN PATH: $p — INDEX.md"; fail=1; }
done <<<"$idx_links"

# --- 3) таблица ondemand-rules.md: каждый упомянутый файл существует ---
od_refs=$(grep -oE '[a-z0-9-]+\.md' "$BRAIN/rules/ondemand-rules.md" 2>/dev/null | grep -v '^ondemand-rules\.md$' | sort -u)
while IFS= read -r m; do
  [ -z "$m" ] && continue
  if [ ! -e "$BRAIN/rules-ondemand/$m" ] && [ ! -e "$BRAIN/rules/$m" ]; then
    echo "MISSING FILE: $m — упомянут в rules/ondemand-rules.md, нет ни в rules-ondemand/, ни в rules/"
    fail=1
  fi
done <<<"$od_refs"

# --- 4) WARN: знания-сироты (файл в knowledge/ без строки в INDEX.md) ---
while IFS= read -r k; do
  [ -z "$k" ] && continue
  rel="${k#"$BRAIN"/}"
  base=$(basename "$k")
  if ! grep -qF "$rel" "$BRAIN/INDEX.md" 2>/dev/null && ! grep -qF "${base%.md}" "$BRAIN/INDEX.md" 2>/dev/null; then
    echo "WARN ORPHAN: $rel — нет строки в INDEX.md (CONVENTIONS: знание = строка в индексе)"
  fi
done <<<"$(find -L "$BRAIN/knowledge" -name '*.md' 2>/dev/null)"

# --- 5) WARN: знания без даты проверки (битемпоральные метки) ---
while IFS= read -r k; do
  [ -z "$k" ] && continue
  if ! grep -qiE 'проверено|верно на' "$k" 2>/dev/null; then
    echo "WARN NO-VERIFY-DATE: ${k#"$BRAIN"/} — нет даты «проверено/верно на» (CONVENTIONS, knowledge: две даты)"
  fi
done <<<"$(find -L "$BRAIN/knowledge" -name '*.md' 2>/dev/null)"

[ "$fail" -eq 0 ] && echo "OK: ссылки brain целы (wikilinks, INDEX.md, ondemand-таблица); WARN-строки выше (если есть) — на усмотрение"
exit "$fail"
