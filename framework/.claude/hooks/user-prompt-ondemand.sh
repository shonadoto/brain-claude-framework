#!/usr/bin/env bash
# UserPromptSubmit hook: матчит промпт пользователя по триггерам ondemand-правил
# и подсказывает агенту прочитать нужный файл rules-ondemand/ ДО первого действия в теме.
# Карта триггеров — $BRAIN/rules/ondemand-keywords.tsv:
#   расширенный-regex<TAB>файл(ы) через запятую<TAB>короткая подсказка
# Строки с # и пустые игнорируются. Нет файла/совпадений → молча exit 0.
set -u

BRAIN="$(cat "$HOME/.claude/brain-dir" 2>/dev/null || true)"
[ -n "$BRAIN" ] || BRAIN="$HOME/brain"
MAP="$BRAIN/rules/ondemand-keywords.tsv"
[ -f "$MAP" ] || exit 0

input=$(cat || true)
prompt=$(jq -r '.prompt // ""' <<<"$input" 2>/dev/null || true)
[ -n "$prompt" ] || exit 0

hits=""
n=0
while IFS=$'\t' read -r regex files hint; do
  [ -z "$regex" ] && continue
  case "$regex" in \#*) continue;; esac
  if printf '%s' "$prompt" | grep -qiE "$regex" 2>/dev/null; then
    hits="${hits}- ${files}${hint:+ — ${hint}}\n"
    n=$((n+1))
    [ "$n" -ge 3 ] && break
  fi
done < "$MAP"

[ "$n" -eq 0 ] && exit 0

printf '[brain] Запрос задевает тему ondemand-правил. ДО первого действия по теме прочитай из %s/rules-ondemand/:\n%b(Если тема запросу не релевантна — молча игнорируй.)\n' "$BRAIN" "$hits"
exit 0
