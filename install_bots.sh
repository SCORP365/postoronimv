#!/usr/bin/env bash
# One-command bootstrap for SCORP365/postoronimv_bots using GitHub App Device Flow.
set -Eeuo pipefail
umask 077

[[ \${EUID} -eq 0 ]] || { echo "Запусти команду от root." >&2; exit 1; }
[[ -f /etc/os-release ]] && grep -Eqi 'ubuntu|debian' /etc/os-release || {
  echo "Поддерживаются Ubuntu и Debian с APT." >&2
  exit 1
}

if ! command -v curl >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y curl git python3
fi

CLIENT_ID="Iv23liEdH6Ic3zheeHJP"
REPOSITORY_ID="1457890740"
CONFIG_DIR="/root/.config/bot_manager"
ACCESS_FILE="$CONFIG_DIR/github_access_token"
REFRESH_FILE="$CONFIG_DIR/github_refresh_token"
EXPIRY_FILE="$CONFIG_DIR/github_access_expires_at"
install -d -m 700 "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

parse_json() {
  python3 -c 'import json,sys; d=json.load(sys.stdin); v=d.get(sys.argv[1],""); print(v if isinstance(v,(str,int,float)) else "")' "$1"
}

echo "===== АВТОРИЗАЦИЯ GITHUB ЧЕРЕЗ DEVICE FLOW ====="
response="$(curl -fsS -X POST https://github.com/login/device/code \
  -H 'Accept: application/json' \
  --data-urlencode "client_id=$CLIENT_ID" \
  --data-urlencode 'scope=offline_access')"
device_code="$(printf '%s' "$response" | parse_json device_code)"
user_code="$(printf '%s' "$response" | parse_json user_code)"
verification_uri="$(printf '%s' "$response" | parse_json verification_uri)"
interval="$(printf '%s' "$response" | parse_json interval)"
expires_in="$(printf '%s' "$response" | parse_json expires_in)"
[[ -n "$device_code" && -n "$user_code" && "$verification_uri" == https://* ]] || {
  echo "GitHub не выдал код авторизации: $(printf '%s' "$response" | parse_json error_description)" >&2
  exit 1
}
[[ "$interval" =~ ^[0-9]+$ ]] || interval=5
[[ "$expires_in" =~ ^[0-9]+$ ]] || expires_in=900

echo
echo "Открой на телефоне или компьютере: $verification_uri"
echo "Введи одноразовый код: $user_code"
echo "Код предназначен только для авторизации на GitHub. Никому его не отправляй."
deadline=$(( $(date +%s) + expires_in ))
access_token=""
refresh_token=""
token_expires=""
while (( $(date +%s) < deadline )); do
  sleep "$interval"
  poll="$(curl -fsS -X POST https://github.com/login/oauth/access_token \
    -H 'Accept: application/json' \
    --data-urlencode "client_id=$CLIENT_ID" \
    --data-urlencode "device_code=$device_code" \
    --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:device_code' \
    --data-urlencode "repository_id=$REPOSITORY_ID")"
  error="$(printf '%s' "$poll" | parse_json error)"
  case "$error" in
    authorization_pending) continue ;;
    slow_down) interval=$((interval + 5)); continue ;;
    "")
      access_token="$(printf '%s' "$poll" | parse_json access_token)"
      refresh_token="$(printf '%s' "$poll" | parse_json refresh_token)"
      token_expires="$(printf '%s' "$poll" | parse_json expires_in)"
      break
      ;;
    *)
      echo "GitHub отклонил авторизацию: $error" >&2
      exit 1
      ;;
  esac
done

[[ -n "$access_token" && -n "$refresh_token" && "$token_expires" =~ ^[0-9]+$ ]] || {
  echo "Время действия кода истекло или GitHub не выдал токены. Запусти установку повторно." >&2
  exit 1
}

now="$(date +%s)"
printf '%s\n' "$access_token" > "$ACCESS_FILE.tmp"
printf '%s\n' "$refresh_token" > "$REFRESH_FILE.tmp"
printf '%s\n' "$((now + token_expires))" > "$EXPIRY_FILE.tmp"
chmod 600 "$ACCESS_FILE.tmp" "$REFRESH_FILE.tmp" "$EXPIRY_FILE.tmp"
mv -f "$ACCESS_FILE.tmp" "$ACCESS_FILE"
mv -f "$REFRESH_FILE.tmp" "$REFRESH_FILE"
mv -f "$EXPIRY_FILE.tmp" "$EXPIRY_FILE"
export GITHUB_TOKEN="$access_token"

ASKPASS_DIR="$(mktemp -d)"
cleanup() {
  rm -rf -- "$ASKPASS_DIR"
  unset GITHUB_TOKEN GIT_ASKPASS GIT_TERMINAL_PROMPT
}
trap cleanup EXIT
cat > "$ASKPASS_DIR/askpass.sh" <<'ASKPASS'
#!/usr/bin/env bash
case "\${1:-}" in
  *sername*) printf '%s\n' 'x-access-token' ;;
  *) printf '%s\n' "$GITHUB_TOKEN" ;;
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
