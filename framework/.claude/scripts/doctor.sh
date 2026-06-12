#!/usr/bin/env bash
# Самодиагностика установки brain: пути, симлинки, хуки, зависимости, git, версия.
# Запуск: .claude/scripts/doctor.sh (или скиллом /brain-doctor).
# Только чтение, ничего не меняет. Выход: 0 — всё ок, 1 — есть проблемы.
set -u

ok=0; bad=0
pass() { printf '  ✓ %s\n' "$*"; ok=$((ok+1)); }
failmsg() { printf '  ✗ %s\n' "$*"; bad=$((bad+1)); }

echo "== brain doctor =="

# 1. путь к brain
BRAIN="$(cat "$HOME/.claude/brain-dir" 2>/dev/null || true)"
if [ -n "$BRAIN" ]; then
  pass "~/.claude/brain-dir → $BRAIN"
else
  BRAIN="$HOME/brain"
  failmsg "~/.claude/brain-dir отсутствует — использую дефолт $BRAIN (лечится: echo '$BRAIN' > ~/.claude/brain-dir)"
fi

# 2. структура brain
if [ -f "$BRAIN/CONVENTIONS.md" ]; then pass "brain найден: $BRAIN"; else failmsg "в $BRAIN нет CONVENTIONS.md — brain не установлен (запусти install.sh)"; fi
for d in inbox tasks projects knowledge learning rules rules-ondemand areas days templates .claude/hooks .claude/scripts .claude/skills; do
  [ -d "$BRAIN/$d" ] || failmsg "нет директории $BRAIN/$d (восстановит /update-brain)"
done

# 3. версия
if [ -f "$BRAIN/.claude/VERSION" ]; then
  v=$(tr -d ' \n' < "$BRAIN/.claude/VERSION")
  pass "версия фреймворка: $v"
  if [ -f "$BRAIN/.claude/.update-cache" ]; then
    rv=$(tr -d ' \n' < "$BRAIN/.claude/.update-cache")
    [ "$rv" != "$v" ] && [ -n "$rv" ] && failmsg "доступно обновление: $v → $rv (запусти /update-brain)"
  fi
else
  failmsg "нет $BRAIN/.claude/VERSION (восстановит /update-brain)"
fi

# 4. подключение к Claude Code
if [ "$(readlink "$HOME/.claude/rules" 2>/dev/null)" = "$BRAIN/rules" ]; then
  pass "~/.claude/rules → brain/rules (правила автозагружаются)"
else
  failmsg "~/.claude/rules не указывает на $BRAIN/rules — правила НЕ автозагружаются (лечится: ln -sfn '$BRAIN/rules' ~/.claude/rules)"
fi
miss=""
for s in "$BRAIN"/.claude/skills/*/; do
  name=$(basename "$s")
  [ -e "$HOME/.claude/skills/$name" ] || miss="$miss $name"
done
if [ -z "$miss" ]; then pass "скиллы подключены в ~/.claude/skills"; else failmsg "не подключены скиллы:$miss (перезапусти install.sh — он до-настроит)"; fi

if [ -f "$HOME/.claude/CLAUDE.md" ] && grep -q "brain-claude-framework" "$HOME/.claude/CLAUDE.md"; then
  pass "точка входа в ~/.claude/CLAUDE.md есть"
else
  failmsg "в ~/.claude/CLAUDE.md нет точки входа brain (перезапусти install.sh)"
fi

SETTINGS="$HOME/.claude/settings.json"
for h in session-start-brain-status.sh session-end.sh pre-compact-journal.sh user-prompt-ondemand.sh; do
  if grep -qs "$h" "$SETTINGS"; then pass "хук $h зарегистрирован"; else failmsg "хук $h НЕ зарегистрирован в settings.json (перезапусти install.sh)"; fi
done
if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
  jq -e . "$SETTINGS" >/dev/null 2>&1 && pass "settings.json — валидный JSON" || failmsg "settings.json повреждён (невалидный JSON)"
fi

# 5. зависимости
for c in jq git curl; do
  if command -v "$c" >/dev/null 2>&1; then pass "$c установлен"; else failmsg "$c не найден (jq — обязателен для хуков; git — бэкап; curl — проверка обновлений)"; fi
done

# 6. исполняемость хуков/скриптов
for f in "$BRAIN"/.claude/hooks/*.sh "$BRAIN"/.claude/scripts/*.sh; do
  [ -x "$f" ] || failmsg "не исполняемый: $f (лечится: chmod +x)"
done

# 7. git/бэкап
if [ -d "$BRAIN/.git" ]; then
  pass "brain под git"
  if (cd "$BRAIN" && git remote get-url origin >/dev/null 2>&1); then
    pass "remote настроен: $(cd "$BRAIN" && git remote get-url origin)"
    n=$(cd "$BRAIN" && git log --branches --not --remotes --oneline 2>/dev/null | wc -l | tr -d ' ')
    [ "$n" -gt 0 ] && failmsg "$n непушнутых коммитов (запусти /sync-brain)"
  else
    failmsg "git без remote — бэкапа наружу нет (см. README, раздел «Бэкап»)"
  fi
  if ! (cd "$BRAIN" && git config user.email >/dev/null 2>&1); then
    failmsg "git identity не настроена — коммиты будут падать (cd $BRAIN && git config user.email you@example.com && git config user.name 'Имя')"
  fi
else
  failmsg "brain не под git — бэкапа нет (cd $BRAIN && git init; см. README)"
fi

# 8. остатки плейсхолдера (паттерн собран из частей — иначе install.sh подменит его в самом этом скрипте)
ph="__BRAIN""_DIR__"
if grep -rqs "$ph" "$BRAIN" --exclude-dir=.git 2>/dev/null; then
  failmsg "в brain остались ${ph}-плейсхолдеры (установка прошла некорректно; перезапусти install.sh)"
fi

echo "== итог: ✓ $ok / ✗ $bad =="
[ "$bad" -eq 0 ]
