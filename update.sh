#!/usr/bin/env bash
# Обновление механики фреймворка brain в уже установленном brain.
#
# Использование (обычно через скилл /update-brain):
#   ./update.sh [/путь/до/brain]     # без аргумента — путь из ~/.claude/brain-dir, иначе ~/brain
#
# Что обновляется: скиллы, хуки, скрипты, шаблоны, версия + подключение к Claude Code.
# Что НЕ трогается: данные (журналы, знания, петли, INDEX, профиль), существующие правила,
# CONVENTIONS.md — для них только отчёт «разошёлся с репозиторием».
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_HOME="$HOME/.claude"
SETTINGS="$CLAUDE_HOME/settings.json"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mВНИМАНИЕ:\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mОШИБКА:\033[0m %s\n' "$*" >&2; exit 1; }

BRAIN_DIR="${1:-}"
[ -n "$BRAIN_DIR" ] || BRAIN_DIR="$(cat "$CLAUDE_HOME/brain-dir" 2>/dev/null || true)"
[ -n "$BRAIN_DIR" ] || BRAIN_DIR="$HOME/brain"

[ -d "$REPO_DIR/framework" ] && [ -d "$REPO_DIR/skills" ] || die "запускай из клона репозитория (нет framework/ или skills/ рядом со скриптом)"
[ -f "$BRAIN_DIR/CONVENTIONS.md" ] || die "в $BRAIN_DIR нет brain (нет CONVENTIONS.md) — для первичной установки запусти install.sh"
command -v jq >/dev/null 2>&1 || die "не найден jq"

old_v="$(cat "$BRAIN_DIR/.claude/VERSION" 2>/dev/null | tr -d ' \n' || true)"; [ -n "$old_v" ] || old_v="<нет>"
new_v="$(tr -d ' \n' < "$REPO_DIR/VERSION")"
say "обновление фреймворка: $old_v → $new_v (brain: $BRAIN_DIR)"

# --- 1. механика: скиллы, хуки, скрипты, шаблоны (перезапись) ---
mkdir -p "$BRAIN_DIR/.claude/skills" "$BRAIN_DIR/.claude/hooks" "$BRAIN_DIR/.claude/scripts" "$BRAIN_DIR/templates"
cp -R "$REPO_DIR/skills/." "$BRAIN_DIR/.claude/skills/"
cp -R "$REPO_DIR/framework/.claude/hooks/." "$BRAIN_DIR/.claude/hooks/"
cp -R "$REPO_DIR/framework/.claude/scripts/." "$BRAIN_DIR/.claude/scripts/"
cp -R "$REPO_DIR/framework/templates/." "$BRAIN_DIR/templates/"
chmod +x "$BRAIN_DIR"/.claude/hooks/*.sh "$BRAIN_DIR"/.claude/scripts/*.sh
say "механика обновлена: скиллы, хуки, скрипты, шаблоны"

# --- 2. недостающие директории данных (новые слои версий) ---
for d in inbox/archive tasks/archive projects/archive areas days knowledge learning rules rules-ondemand; do
  [ -d "$BRAIN_DIR/$d" ] || { mkdir -p "$BRAIN_DIR/$d"; say "создан новый слой: $d/"; }
done

# --- 3. правила: новые стартовые — добавить; существующие — не трогать, сообщить о расхождении ---
diverged=""
for src in "$REPO_DIR"/framework/rules/*; do
  base="$(basename "$src")"
  dst="$BRAIN_DIR/rules/$base"
  if [ ! -e "$dst" ]; then
    sed "s|__BRAIN_DIR__|$BRAIN_DIR|g" "$src" > "$dst"
    say "новое стартовое правило: rules/$base"
  else
    case "$base" in *.tsv) continue;; esac   # карты-данные пользователь заполняет сам — расхождение норма
    if ! sed "s|__BRAIN_DIR__|$BRAIN_DIR|g" "$src" | diff -q - "$dst" >/dev/null 2>&1; then
      diverged="$diverged rules/$base"
    fi
  fi
done
if ! diff -q "$REPO_DIR/framework/CONVENTIONS.md" "$BRAIN_DIR/CONVENTIONS.md" >/dev/null 2>&1; then
  diverged="$diverged CONVENTIONS.md"
fi
if [ -n "$diverged" ]; then
  warn "разошлись с репозиторием (не перезаписаны, твои версии сохранены):$diverged"
  warn "посмотреть отличия: diff <(sed \"s|__BRAIN_DIR__|$BRAIN_DIR|g\" <клон>/framework/rules/<файл>) $BRAIN_DIR/rules/<файл>"
fi

# --- 4. подключение к Claude Code: новые скиллы и хуки ---
echo "$BRAIN_DIR" > "$CLAUDE_HOME/brain-dir"
mkdir -p "$CLAUDE_HOME/skills"
for skill_dir in "$BRAIN_DIR"/.claude/skills/*/; do
  name="$(basename "$skill_dir")"
  link="$CLAUDE_HOME/skills/$name"
  if [ ! -e "$link" ] && [ ! -L "$link" ]; then
    ln -s "${skill_dir%/}" "$link"
    say "подключён новый скилл: $name"
  fi
done

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
add_hook() {
  local event="$1" cmd="$2" timeout="$3" tmp
  if grep -qs "$cmd" "$SETTINGS"; then return 0; fi
  tmp="$(mktemp)"
  jq --arg e "$event" --arg c "$cmd" --argjson t "$timeout" \
    '.hooks //= {} | .hooks[$e] = ((.hooks[$e] // []) + [{"hooks":[{"type":"command","command":$c,"timeout":$t}]}])' \
    "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  say "зарегистрирован хук: $event → $(basename "$cmd")"
}
add_hook "SessionStart"     "$BRAIN_DIR/.claude/hooks/session-start-brain-status.sh" 10
add_hook "SessionEnd"       "$BRAIN_DIR/.claude/hooks/session-end.sh" 30
add_hook "PreCompact"       "$BRAIN_DIR/.claude/hooks/pre-compact-journal.sh" 5
add_hook "UserPromptSubmit" "$BRAIN_DIR/.claude/hooks/user-prompt-ondemand.sh" 10

# --- 5. версия ---
printf '%s\n' "$new_v" > "$BRAIN_DIR/.claude/VERSION"
printf '%s\n' "$new_v" > "$BRAIN_DIR/.claude/.update-cache"

echo
say "Готово: фреймворк обновлён до $new_v. Перезапусти Claude Code, чтобы подхватились новые скиллы и хуки."
