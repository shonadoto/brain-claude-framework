#!/usr/bin/env bash
# SessionEnd hook: логирует завершённую сессию в brain/inbox/sessions.log.
# Вход (stdin JSON): session_id, transcript_path, cwd, reason.
# Формат строки лога (TSV): дата \t session_id \t cwd \t transcript_path \t размер_транскрипта \t reason
set -u

BRAIN="__BRAIN_DIR__"
LOG="${BRAIN_SESSIONS_LOG:-$BRAIN/inbox/sessions.log}"

input=$(cat)

session_id=$(jq -r '.session_id // "-"' <<<"$input")
transcript=$(jq -r '.transcript_path // "-"' <<<"$input")
cwd=$(jq -r '.cwd // "-"' <<<"$input")
reason=$(jq -r '.reason // "-"' <<<"$input")

size="-"
if [ -f "$transcript" ]; then
  size=$(stat -c %s "$transcript" 2>/dev/null || stat -f %z "$transcript" 2>/dev/null || echo "-")
fi

printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$(date '+%Y-%m-%d %H:%M')" \
  "$session_id" "$cwd" "$transcript" "$size" "$reason" >> "$LOG"

# brain-backup: лог сессии не висит незакоммиченным между сессиями (rules/brain-backup.md).
# Коммитим ТОЛЬКО inbox/sessions.log (явный pathspec — чужие staged-файлы не задеваем);
# содержимое генерит сам этот хук (даты/id/пути/reason) — секретов в диффе нет by construction.
# Brain не под git / push упал (сеть, нет remote) → молча пропускаем, догонит /sync-brain.
if [ "$LOG" = "$BRAIN/inbox/sessions.log" ] && [ -d "$BRAIN/.git" ]; then
  (
    cd "$BRAIN" || exit 0
    timeout 30 git add inbox/sessions.log || exit 0
    timeout 30 git commit -m "session-end: лог сессии ${session_id}" inbox/sessions.log || exit 0
    timeout 60 git push || true
  ) >/dev/null 2>&1 || true
fi
exit 0
