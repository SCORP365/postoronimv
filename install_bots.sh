#!/usr/bin/env bash
# One-command bootstrap for SCORP365/postoronimv_bots.
set -Eeuo pipefail
umask 077

if [[ ${EUID} -ne 0 ]]; then
  echo "Запусти команду от root." >&2
  exit 1
fi

if [[ ! -f /etc/os-release ]] || ! grep -Eqi 'ubuntu|debian' /etc/os-release; then
  echo "Поддерживаются Ubuntu и Debian с APT." >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y git
fi

TOKEN_DIR="/root/.config/bot_manager"
TOKEN_FILE="$TOKEN_DIR/github_token"
install -d -m 700 "$TOKEN_DIR"
chmod 700 "$TOKEN_DIR"

if [[ -s "$TOKEN_FILE" ]]; then
  read -r -s -p "GitHub Token (Enter — использовать сохранённый): " TOKEN
  echo
  TOKEN="${TOKEN:-$(<"$TOKEN_FILE")}"
else
  read -r -s -p "GitHub Token: " TOKEN
  echo
fi

if [[ -z "$TOKEN" ]]; then
  echo "Токен пуст. Установка отменена." >&2
  exit 1
fi

printf '%s\n' "$TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"
export GITHUB_TOKEN="$TOKEN"
unset TOKEN

ASKPASS_DIR="$(mktemp -d)"
cleanup() {
  rm -rf -- "$ASKPASS_DIR"
  unset GITHUB_TOKEN GIT_ASKPASS GIT_TERMINAL_PROMPT
}
trap cleanup EXIT

cat > "$ASKPASS_DIR/askpass.sh" <<'ASKPASS'
#!/usr/bin/env bash
case "${1:-}" in
  *sername*) printf '%s\n' 'x-access-token' ;;
  *)         printf '%s\n' "$GITHUB_TOKEN" ;;
esac
ASKPASS
chmod 700 "$ASKPASS_DIR/askpass.sh"
export GIT_ASKPASS="$ASKPASS_DIR/askpass.sh"
export GIT_TERMINAL_PROMPT=0

if [[ -d /root/bots/.git ]]; then
  echo "Репозиторий уже существует в /root/bots; пропускаю clone."
elif [[ -e /root/bots ]]; then
  echo "Путь /root/bots уже занят и не является Git-репозиторием. Остановлено." >&2
  exit 1
else
  git clone --branch main --depth 1 https://github.com/SCORP365/postoronimv_bots.git /root/bots
fi

echo "Репозиторий загружен. Запускаю установщик..."
bash /root/bots/install.sh
