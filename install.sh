#!/usr/bin/env bash
# Установщик brain-claude-framework.
#
# Использование:
#   ./install.sh                  # установит brain в ~/brain
#   ./install.sh /путь/до/brain   # установит в указанную директорию
#   ./install.sh --no-git         # не настраивать git-репозиторий
#   ./install.sh --no-wire        # только данные brain, без подключения к Claude Code
#                                 # (для установки через плагин: скиллы и хуки даёт плагин)
#
# Что делает:
#   1. Копирует заготовку brain в целевую директорию (данные + механика).
#   2. Подставляет реальный путь brain в файлы данных; путь пишется в ~/.claude/brain-dir.
#   3. Подключает brain к Claude Code: правила (симлинк), скиллы (симлинки),
#      точка входа в ~/.claude/CLAUDE.md, хуки в ~/.claude/settings.json.
#   4. Инициализирует git-репозиторий для бэкапа (если git установлен).
#
# Повторный запуск безопасен: существующий brain не перезаписывается,
# подключение к Claude Code до-настраивается. Обновление установленного brain — update.sh.
set -euo pipefail

# --- разбор аргументов ---
BRAIN_DIR="$HOME/brain"
NO_GIT=0
NO_WIRE=0
for arg in "$@"; do
  case "$arg" in
    --no-git) NO_GIT=1 ;;
    --no-wire) NO_WIRE=1 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) BRAIN_DIR="$arg" ;;
  esac
done

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_HOME="$HOME/.claude"
SETTINGS="$CLAUDE_HOME/settings.json"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mВНИМАНИЕ:\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mОШИБКА:\033[0m %s\n' "$*" >&2; exit 1; }

# --- 0. проверки окружения ---
command -v jq >/dev/null 2>&1 || die "не найден jq — он нужен для хуков. Установи: macOS: 'brew install jq'; Ubuntu/Debian: 'sudo apt install jq'."
command -v claude >/dev/null 2>&1 || warn "не найден 'claude' (Claude Code CLI). Установи его: https://claude.com/claude-code — фреймворк работает внутри Claude Code."
command -v curl >/dev/null 2>&1 || warn "не найден curl — не будет работать проверка обновлений (остальное будет)."
HAVE_GIT=0
command -v git >/dev/null 2>&1 && HAVE_GIT=1
[ "$HAVE_GIT" -eq 0 ] && warn "git не найден — бэкап brain настроен не будет (всё остальное будет работать)."

[ -d "$REPO_DIR/framework" ] && [ -d "$REPO_DIR/skills" ] || die "не найдены framework/ и skills/ рядом с install.sh — запускай скрипт из клона репозитория."

# нормализуем путь до абсолютного
case "$BRAIN_DIR" in
  /*) : ;;
  ~*) BRAIN_DIR="${BRAIN_DIR/#\~/$HOME}" ;;
  *)  BRAIN_DIR="$PWD/$BRAIN_DIR" ;;
esac

# --- 1. копирование заготовки ---
if [ -f "$BRAIN_DIR/CONVENTIONS.md" ]; then
  say "brain уже существует в $BRAIN_DIR — файлы не трогаю (обновление механики — update.sh), до-настраиваю подключение."
elif [ -d "$BRAIN_DIR" ] && [ -n "$(ls -A "$BRAIN_DIR" 2>/dev/null)" ]; then
  die "директория $BRAIN_DIR существует и не пуста (и это не brain — нет CONVENTIONS.md). Укажи другой путь: ./install.sh /другой/путь"
else
  say "копирую заготовку brain в $BRAIN_DIR"
  mkdir -p "$BRAIN_DIR"
  cp -R "$REPO_DIR/framework/." "$BRAIN_DIR/"
  mkdir -p "$BRAIN_DIR/.claude/skills"
  cp -R "$REPO_DIR/skills/." "$BRAIN_DIR/.claude/skills/"
  cp "$REPO_DIR/VERSION" "$BRAIN_DIR/.claude/VERSION"

  # --- 2. подстановка пути в файлы данных (механика путь читает из ~/.claude/brain-dir) ---
  say "подставляю путь brain в файлы"
  find "$BRAIN_DIR" -type f \( -name '*.md' -o -name '*.sh' \) | while IFS= read -r f; do
    if grep -q '__BRAIN_DIR__' "$f"; then
      sed "s|__BRAIN_DIR__|$BRAIN_DIR|g" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    fi
  done
  chmod +x "$BRAIN_DIR"/.claude/hooks/*.sh "$BRAIN_DIR"/.claude/scripts/*.sh
fi

mkdir -p "$CLAUDE_HOME"
echo "$BRAIN_DIR" > "$CLAUDE_HOME/brain-dir"
say "путь brain записан в ~/.claude/brain-dir"

# --- 3. подключение к Claude Code ---
if [ "$NO_WIRE" -eq 1 ]; then
  say "--no-wire: пропускаю подключение к Claude Code (скиллы и хуки даёт плагин)"
else
  mkdir -p "$CLAUDE_HOME/skills"

  # 3a. правила: ~/.claude/rules -> brain/rules (автозагрузка в каждую сессию)
  if [ -L "$CLAUDE_HOME/rules" ]; then
    current="$(readlink "$CLAUDE_HOME/rules")"
    if [ "$current" = "$BRAIN_DIR/rules" ]; then
      say "симлинк правил уже настроен"
    else
      warn "~/.claude/rules уже указывает на $current — не трогаю. Чтобы правила brain автозагружались: ln -sfn '$BRAIN_DIR/rules' '$CLAUDE_HOME/rules'"
    fi
  elif [ -e "$CLAUDE_HOME/rules" ]; then
    warn "~/.claude/rules существует и не симлинк — не трогаю. Перенеси свои правила в $BRAIN_DIR/rules/ и сделай: ln -sfn '$BRAIN_DIR/rules' '$CLAUDE_HOME/rules'"
  else
    ln -s "$BRAIN_DIR/rules" "$CLAUDE_HOME/rules"
    say "правила подключены: ~/.claude/rules -> $BRAIN_DIR/rules"
  fi

  # 3b. скиллы: симлинк на каждый скилл brain
  for skill_dir in "$BRAIN_DIR"/.claude/skills/*/; do
    name="$(basename "$skill_dir")"
    link="$CLAUDE_HOME/skills/$name"
    if [ -L "$link" ] || [ -e "$link" ]; then
      [ "$(readlink "$link" 2>/dev/null)" = "${skill_dir%/}" ] || warn "скилл '$name' уже существует в ~/.claude/skills — пропускаю"
    else
      ln -s "${skill_dir%/}" "$link"
    fi
  done
  say "скиллы подключены: $(ls "$BRAIN_DIR/.claude/skills" | tr '\n' ' ')"

  # 3c. точка входа в ~/.claude/CLAUDE.md
  MARKER="brain-claude-framework"
  if [ -f "$CLAUDE_HOME/CLAUDE.md" ] && grep -q "$MARKER" "$CLAUDE_HOME/CLAUDE.md"; then
    say "точка входа в ~/.claude/CLAUDE.md уже есть"
  else
    cat >> "$CLAUDE_HOME/CLAUDE.md" <<EOF

# Brain — точка входа ($MARKER)

Всё взаимодействие с Claude живёт в $BRAIN_DIR.

@$BRAIN_DIR/.claude/CLAUDE.md
EOF
    say "точка входа дописана в ~/.claude/CLAUDE.md"
  fi

  # 3d. хуки в ~/.claude/settings.json
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  jq -e . "$SETTINGS" >/dev/null 2>&1 || die "~/.claude/settings.json повреждён (невалидный JSON) — поправь его и перезапусти установщик."

  add_hook() {
    local event="$1" cmd="$2" timeout="$3" tmp
    if grep -qs "$cmd" "$SETTINGS"; then return 0; fi
    tmp="$(mktemp)"
    jq --arg e "$event" --arg c "$cmd" --argjson t "$timeout" \
      '.hooks //= {} | .hooks[$e] = ((.hooks[$e] // []) + [{"hooks":[{"type":"command","command":$c,"timeout":$t}]}])' \
      "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  }
  add_hook "SessionStart"     "$BRAIN_DIR/.claude/hooks/session-start-brain-status.sh" 10
  add_hook "SessionEnd"       "$BRAIN_DIR/.claude/hooks/session-end.sh" 30
  add_hook "PreCompact"       "$BRAIN_DIR/.claude/hooks/pre-compact-journal.sh" 5
  add_hook "UserPromptSubmit" "$BRAIN_DIR/.claude/hooks/user-prompt-ondemand.sh" 10
  say "хуки зарегистрированы в ~/.claude/settings.json"
fi

# --- 4. git ---
if [ "$NO_GIT" -eq 0 ] && [ "$HAVE_GIT" -eq 1 ] && [ ! -d "$BRAIN_DIR/.git" ]; then
  say "инициализирую git-репозиторий в $BRAIN_DIR"
  (
    cd "$BRAIN_DIR"
    git init -q
    git checkout -q -b main 2>/dev/null || true
    # без identity git-коммиты (в т.ч. автобэкап из хука) молча падают — задаём локально для этого репо
    git config user.email >/dev/null 2>&1 || {
      git config user.name "${USER:-brain}"
      git config user.email "${USER:-brain}@local"
    }
    git add -A
    git commit -q -m "brain: первичная установка фреймворка" || true
  )
fi

# --- 5. итог ---
echo
say "Готово! brain установлен в $BRAIN_DIR (версия $(cat "$BRAIN_DIR/.claude/VERSION" 2>/dev/null || echo '?'))"
echo
echo "Дальше:"
echo "  1. Перезапусти Claude Code (новые правила и скиллы подхватываются при старте сессии)."
echo "  2. В Claude Code набери: /setup-brain — он задаст пару вопросов и настроит профиль."
echo "  3. Бэкап (рекомендую): создай ПРИВАТНЫЙ репозиторий на github.com и подключи его:"
echo "       cd $BRAIN_DIR"
echo "       git remote add origin git@github.com:<твой-логин>/<имя-репо>.git"
echo "       git push -u origin main"
echo "     После этого brain будет бэкапиться автоматически."
echo "  4. Обновление в будущем: /update-brain (Claude сам подскажет, когда выйдет новая версия)."
