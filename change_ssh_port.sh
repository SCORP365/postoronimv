#!/usr/bin/env bash
# Безопасный перенос SSH с порта 22 на 8422 для Ubuntu/Debian.
set -Eeuo pipefail
umask 077

TARGET_PORT=8422
SSH_DROPIN_DIR=/etc/ssh/sshd_config.d
SSH_DROPIN="$SSH_DROPIN_DIR/99-custom-port.conf"
SOCKET_DROPIN_DIR=/etc/systemd/system/ssh.socket.d
SOCKET_DROPIN="$SOCKET_DROPIN_DIR/override.conf"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="/root/ssh-port-migration-$TIMESTAMP"
SOCKET_MODE=0

log() { printf '\n===== %s =====\n' "$*"; }
fail() { echo "ОШИБКА: $*" >&2; exit 1; }
has_listener() {
  local port="$1"
  ss -H -lnt 2>/dev/null | awk -v suffix=":$port" '$4 ~ (suffix "$") { found=1 } END { exit !found }'
}
effective_has_port() {
  local port="$1"
  sshd -T 2>/dev/null | awk -v wanted="$port" '$1=="port" && $2==wanted { found=1 } END { exit !found }'
}
show_listener() {
  local port="$1"
  ss -lntp 2>/dev/null | awk -v suffix=":$port" 'NR==1 || $4 ~ (suffix "$")'
}
backup_one() {
  local file="$1" marker="$2"
  if [[ -e "$file" ]]; then
    mkdir -p "$(dirname "$BACKUP_DIR/$file")"
    cp -a "$file" "$BACKUP_DIR/$file"
    : > "$BACKUP_DIR/$marker"
  fi
}
restore_one() {
  local file="$1" marker="$2"
  if [[ -f "$BACKUP_DIR/$marker" ]]; then
    mkdir -p "$(dirname "$file")"
    cp -a "$BACKUP_DIR/$file" "$file"
  else
    rm -f "$file"
  fi
}
write_ssh_config() {
  local mode="$1"
  mkdir -p "$SSH_DROPIN_DIR"
  if [[ "$mode" == "both" ]]; then
    cat > "$SSH_DROPIN" <<'EOF'
# Управляется change_ssh_port.sh
Port 22
Port 8422
EOF
  else
    cat > "$SSH_DROPIN" <<'EOF'
# Управляется change_ssh_port.sh
Port 8422
EOF
  fi
  chmod 644 "$SSH_DROPIN"
}
write_socket_config() {
  local mode="$1"
  mkdir -p "$SOCKET_DROPIN_DIR"
  if [[ "$mode" == "both" ]]; then
    cat > "$SOCKET_DROPIN" <<'EOF'
# Управляется change_ssh_port.sh
[Socket]
ListenStream=
ListenStream=0.0.0.0:22
ListenStream=[::]:22
ListenStream=0.0.0.0:8422
ListenStream=[::]:8422
EOF
  else
    cat > "$SOCKET_DROPIN" <<'EOF'
# Управляется change_ssh_port.sh
[Socket]
ListenStream=
ListenStream=0.0.0.0:8422
ListenStream=[::]:8422
EOF
  fi
  chmod 644 "$SOCKET_DROPIN"
}
apply_ssh_config() {
  sshd -t || return 1
  if (( SOCKET_MODE )); then
    systemctl daemon-reload || return 1
    systemctl enable ssh.socket >/dev/null 2>&1 || return 1
    systemctl restart ssh.socket || return 1
  else
    if systemctl reload ssh >/dev/null 2>&1; then
      :
    elif systemctl reload sshd >/dev/null 2>&1; then
      :
    elif systemctl restart ssh >/dev/null 2>&1; then
      :
    else
      systemctl restart sshd || return 1
    fi
  fi
}
restore_dual_port() {
  write_ssh_config both
  if (( SOCKET_MODE )); then write_socket_config both; fi
  apply_ssh_config || true
}

[[ $EUID -eq 0 ]] || fail "Запусти скрипт от root."
[[ -f /etc/os-release ]] || fail "Не найден /etc/os-release."
grep -Eqi '^(ID|ID_LIKE)=.*(ubuntu|debian)' /etc/os-release || fail "Поддерживаются Ubuntu и Debian."
command -v systemctl >/dev/null 2>&1 || fail "Не найден systemd."
command -v sshd >/dev/null 2>&1 || fail "Не найден sshd."
command -v ss >/dev/null 2>&1 || fail "Не найдена команда ss (пакет iproute2)."

if has_listener "$TARGET_PORT" && ! has_listener 22; then
  log "SSH уже переведён на порт $TARGET_PORT"
  show_listener "$TARGET_PORT"
  exit 0
fi

if ss -H -lnt 2>/dev/null | awk -v suffix=":$TARGET_PORT" '$4 ~ (suffix "$") { found=1 } END { exit !found }'; then
  echo "Порт $TARGET_PORT уже занят. Освободи его или выбери другой порт." >&2
  show_listener "$TARGET_PORT"
  exit 1
fi

if systemctl is-active --quiet ssh.socket; then
  SOCKET_MODE=1
fi

install -d -m 700 "$BACKUP_DIR"
backup_one "$SSH_DROPIN" "ssh-dropin-existed"
if (( SOCKET_MODE )); then
  backup_one "$SOCKET_DROPIN" "socket-dropin-existed"
fi

log "Режим работы SSH"
if (( SOCKET_MODE )); then
  echo "Обнаружен активный ssh.socket — будет настроена активация через systemd socket."
else
  echo "Активный ssh.socket не обнаружен — будет изменена конфигурация ssh.service."
  echo "Текущий режим systemd socket activation не переключается автоматически."
fi

log "Подготовка firewall"
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
  ufw allow "$TARGET_PORT/tcp" || fail "Не удалось открыть порт $TARGET_PORT в UFW."
  echo "UFW: разрешён TCP-порт $TARGET_PORT."
elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
  firewall-cmd --add-port="$TARGET_PORT/tcp" || fail "Не удалось открыть порт в firewalld."
  firewall-cmd --permanent --add-port="$TARGET_PORT/tcp" || fail "Не удалось сохранить правило firewalld."
  echo "firewalld: разрешён TCP-порт $TARGET_PORT."
else
  echo "Локальный UFW/firewalld не активен или не обнаружен."
  echo "Если у VPS есть внешний firewall в панели хостинга, заранее разреши TCP $TARGET_PORT."
fi

log "Этап 1/2: временно включаем оба SSH-порта"
write_ssh_config both
if (( SOCKET_MODE )); then write_socket_config both; fi

if ! effective_has_port "$TARGET_PORT"; then
  echo "sshd не видит порт $TARGET_PORT в итоговой конфигурации. Возможно, sshd_config не подключает каталог $SSH_DROPIN_DIR."
  restore_one "$SSH_DROPIN" "ssh-dropin-existed"
  if (( SOCKET_MODE )); then restore_one "$SOCKET_DROPIN" "socket-dropin-existed"; fi
  fail "Конфигурация не применена. Исходные файлы восстановлены. Резервная копия: $BACKUP_DIR"
fi

if ! apply_ssh_config; then
  echo "Не удалось применить конфигурацию. Восстанавливаю исходные файлы."
  restore_one "$SSH_DROPIN" "ssh-dropin-existed"
  if (( SOCKET_MODE )); then restore_one "$SOCKET_DROPIN" "socket-dropin-existed"; fi
  if (( SOCKET_MODE )); then systemctl daemon-reload || true; systemctl restart ssh.socket || true
  else systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true; fi
  fail "Конфигурация не применена. Резервная копия: $BACKUP_DIR"
fi

if ! has_listener "$TARGET_PORT"; then
  echo "Порт $TARGET_PORT не появился в LISTEN. Восстанавливаю исходную конфигурацию."
  show_listener 22
  show_listener "$TARGET_PORT"
  restore_one "$SSH_DROPIN" "ssh-dropin-existed"
  if (( SOCKET_MODE )); then restore_one "$SOCKET_DROPIN" "socket-dropin-existed"; fi
  if (( SOCKET_MODE )); then
    systemctl daemon-reload || true
    systemctl restart ssh.socket || true
  else
    systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
  fi
  echo "Резервные копии: $BACKUP_DIR"
  fail "Новый порт не заработал. Исходные SSH-файлы восстановлены; текущую сессию не закрывай."
fi

log "Проверка нового подключения"
show_listener "$TARGET_PORT"
echo
echo "ВАЖНО: не закрывай эту SSH-сессию."
echo "Открой второе окно терминала и проверь вход:"
echo "  ssh -p $TARGET_PORT USER@АДРЕС_СЕРВЕРА"
echo
echo "Убедись, что вход по порту $TARGET_PORT действительно работает."
if [[ ! -t 0 ]]; then
  echo "Нет интерактивного терминала. Оставлены открытыми оба порта 22 и $TARGET_PORT."
  echo "После проверки запусти скрипт повторно из SSH-сессии на порту $TARGET_PORT."
  exit 0
fi
read -r -p "Новое SSH-подключение на порту $TARGET_PORT успешно? [y/N]: " answer
case "$answer" in
  y|Y|yes|YES|д|Д|да|ДА) ;;
  *)
    echo "Оставляю оба порта 22 и $TARGET_PORT открытыми."
    echo "После успешной проверки запусти скрипт повторно и подтверди отключение порта 22."
    exit 0
    ;;
esac

log "Этап 2/2: отключаем SSH-порт 22"
write_ssh_config new
if (( SOCKET_MODE )); then write_socket_config new; fi

if ! effective_has_port "$TARGET_PORT" || effective_has_port 22; then
  echo "Итоговая конфигурация sshd всё ещё содержит порт 22 или не содержит порт $TARGET_PORT."
  echo "Возвращаю конфигурацию с обоими портами."
  restore_dual_port
  fail "Порт 22 не отключён в конфигурации. Резервная копия: $BACKUP_DIR"
fi

if ! apply_ssh_config; then
  echo "Не удалось применить финальную конфигурацию. Возвращаю оба порта."
  restore_dual_port
  fail "Оставлены оба порта. Резервная копия: $BACKUP_DIR"
fi

if ! has_listener "$TARGET_PORT"; then
  echo "После финального применения порт $TARGET_PORT не прослушивается. Возвращаю оба порта."
  restore_dual_port
  fail "Финальная проверка не пройдена. Резервная копия: $BACKUP_DIR"
fi

log "Результат"
echo "SSH настроен на TCP-порт $TARGET_PORT."
show_listener "$TARGET_PORT"
if has_listener 22; then
  echo
  echo "ВНИМАНИЕ: порт 22 всё ещё прослушивается:"
  show_listener 22
  echo "Возможно, его использует другая служба или осталась сторонняя настройка SSH."
else
  echo "Порт 22 больше не прослушивается."
fi
echo
echo "ssh.socket: $(systemctl is-enabled ssh.socket 2>/dev/null || echo 'не используется')"
echo "Резервные копии: $BACKUP_DIR"
echo "Текущую SSH-сессию можно закрыть только после повторной проверки входа на порт $TARGET_PORT."
