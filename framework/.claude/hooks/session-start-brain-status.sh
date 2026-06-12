#!/usr/bin/env bash
# SessionStart hook: однострочная сводка состояния brain в контекст новой сессии.
# Триггер консолидации по накоплению: очередь digest ≥5 → подсказка предложить /digest.
# Только файловые подсчёты, без git/сети — старт сессии не тормозим.
set -u

BRAIN="__BRAIN_DIR__"
[ -d "$BRAIN" ] || exit 0

total=$(grep -c . "$BRAIN/inbox/sessions.log" 2>/dev/null) || total=0
digested=$(grep -c . "$BRAIN/inbox/sessions-digested.log" 2>/dev/null) || digested=0
queue=$(( total - digested ))
[ "$queue" -lt 0 ] && queue=0

loops=$(grep -c '^- \[ \]' "$BRAIN/loops.md" 2>/dev/null) || loops=0

# CONTEXT.md активных задач, не обновлявшиеся >7 дней (mtime)
stale=$(find -L "$BRAIN/tasks" -maxdepth 2 -name CONTEXT.md -not -path '*archive*' -mtime +7 2>/dev/null \
  | xargs -r -n1 dirname | xargs -r -n1 basename | paste -sd, -)

# необработанные daily-заметки inbox (вне archive)
inbox=$(find -L "$BRAIN/inbox" -maxdepth 1 -name '20*.md' 2>/dev/null | wc -l | tr -d ' ')

msg="[brain] очередь digest: ${queue} сессий; открытых петель: ${loops}; необработанных заметок inbox: ${inbox}"
[ -n "$stale" ] && msg="${msg}; CONTEXT.md старше 7 дней: ${stale}"
[ "$queue" -ge 5 ] && msg="${msg}. Очередь digest большая — предложи пользователю прогнать /digest."

echo "$msg"
