#!/usr/bin/env bash
# SessionStart hook: сводка состояния brain в контекст новой сессии.
# Строка гигиены + краткая сводка активных проектов (title + число открытых хвостов +
# дата снапшота brain) — как /status, но БЕЗ сверки статусов во внешнем трекере.
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

# Очередь digest = уникальные session-id из sessions.log, ещё не попавшие в digested-лог.
# sessions.log пишет одну сессию многократно (по событию) → считать по строкам нельзя,
# только по уникальному id (col2 в sessions.log, col1 в sessions-digested.log).
queue=$(comm -23 \
  <(awk -F'\t' '$2!=""{print $2}' "$BRAIN/inbox/sessions.log" 2>/dev/null | sort -u) \
  <(awk -F'\t' '$1!=""{print $1}' "$BRAIN/inbox/sessions-digested.log" 2>/dev/null | sort -u) \
  | grep -c .) || queue=0

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

# --- краткая сводка активных проектов (только из brain, без сверки статусов во внешнем трекере) ---
today=$(TZ=Europe/Moscow date +%Y-%m-%d 2>/dev/null)
today_s=$(date -d "$today" +%s 2>/dev/null) || today_s=

proj_lines=""
for f in "$BRAIN"/projects/*/CONTEXT.md; do
  [ -f "$f" ] || continue
  case "$f" in *"/archive/"*) continue;; esac
  head -10 "$f" | grep -qiE '^status:[[:space:]]*active' || continue

  id=$(basename "$(dirname "$f")")
  title=$(grep -m1 '^# ' "$f" | sed 's/^#\+[[:space:]]*//')
  tails=$(awk '/^## Открытые хвосты/{f=1;next} /^## /{f=0} f&&/^- /{c++} END{print c+0}' "$f")
  # дата снапшота — последняя дата в строках-маркерах со словом "снапшот"
  snap=$(grep -hiE 'снапшот' "$f" 2>/dev/null \
    | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort | tail -1)

  line="- ${id} — ${title} | хвостов: ${tails}"
  if [ -n "$snap" ]; then
    line="${line} | снапшот ${snap}"
    snap_s=$(date -d "$snap" +%s 2>/dev/null) || snap_s=
    if [ -n "$snap_s" ] && [ -n "$today_s" ]; then
      days=$(( (today_s - snap_s) / 86400 ))
      [ "$days" -gt 7 ] && line="${line} ⚠ ${days}д"
    fi
  fi
  proj_lines="${proj_lines}${line}\n"
done

if [ -n "$proj_lines" ]; then
  msg="${msg}
[brain] активные проекты (снапшот brain, без сверки статусов — /status для актуального):
$(printf '%b' "$proj_lines")"
fi

echo "$msg"
