#!/usr/bin/env bash
# SessionStart hook: однострочная сводка состояния brain в контекст новой сессии.
# Дополнительно: подсказка /digest при очереди ≥5, подсказка /inbox-process при ≥5 заметок,
# проверка версии фреймворка (по суточному кэшу, сеть — только фоном),
# восстановление контекста после /clear или компакции (поле source из stdin).
# Только файловые подсчёты в форграунде — старт сессии не тормозим.
set -u

BRAIN="$(cat "$HOME/.claude/brain-dir" 2>/dev/null || true)"
[ -n "$BRAIN" ] || BRAIN="$HOME/brain"
[ -d "$BRAIN" ] || exit 0

# источник старта сессии (startup / resume / clear / compact); stdin может быть пуст
src="startup"
if [ ! -t 0 ]; then
  input=$(cat || true)
  [ -n "$input" ] && src=$(jq -r '.source // "startup"' <<<"$input" 2>/dev/null || echo "startup")
fi

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
[ "$inbox" -ge 5 ] && msg="${msg} Заметок в inbox накопилось — предложи пользователю прогнать /inbox-process."

# --- проверка версии фреймворка ---
# Локальная версия — $BRAIN/.claude/VERSION; удалённая — суточный кэш .update-cache,
# обновляемый фоновым curl (форграунд в сеть не ходит).
VERSION_FILE="$BRAIN/.claude/VERSION"
CACHE="$BRAIN/.claude/.update-cache"
REMOTE_VERSION_URL="https://raw.githubusercontent.com/shonadoto/brain-claude-framework/main/VERSION"
if [ -f "$VERSION_FILE" ]; then
  local_v=$(tr -d ' \n' < "$VERSION_FILE")
  remote_v=""
  [ -f "$CACHE" ] && remote_v=$(tr -d ' \n' < "$CACHE")
  if [ -n "$remote_v" ] && [ -n "$local_v" ] && [ "$remote_v" != "$local_v" ]; then
    msg="${msg} ⬆ Доступно обновление фреймворка brain: ${local_v} → ${remote_v}. Сообщи пользователю и предложи /update-brain."
  fi
  # кэш отсутствует или старше суток → освежить фоном, сессию не задерживаем
  if command -v curl >/dev/null 2>&1; then
    if [ ! -f "$CACHE" ] || [ -n "$(find "$CACHE" -mmin +1440 2>/dev/null)" ]; then
      ( curl -m 5 -fsSL "$REMOTE_VERSION_URL" -o "$CACHE.tmp" 2>/dev/null \
          && mv "$CACHE.tmp" "$CACHE" || rm -f "$CACHE.tmp" ) >/dev/null 2>&1 &
    fi
  fi
fi

# --- восстановление после /clear или компакции ---
if [ "$src" = "clear" ] || [ "$src" = "compact" ]; then
  msg="${msg} Контекст был очищен (${src}) — если шла работа над задачей, восстанови контекст: прочитай tasks/<task>/CONTEXT.md и хвост journal.md, не переспрашивая пользователя с нуля."
fi

echo "$msg"
