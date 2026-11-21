#!/usr/bin/env bash
# /root/update_vps.sh
set -Eeuo pipefail

readonly LOG_DIR="/var/log"
readonly LOG_FILE="${LOG_DIR}/vps-system-update-$(date +%Y%m%d_%H%M%S).log"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Ошибка: запусти скрипт от root."
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo "Ошибка: не удалось определить операционную систему."
  exit 1
fi

. /etc/os-release
case "${ID:-}" in
  ubuntu|debian) ;;
  *)
    echo "Ошибка: поддерживаются только Ubuntu и Debian. Обнаружено: ${PRETTY_NAME:-unknown}"
    exit 1
    ;;
esac

if ! command -v apt-get >/dev/null 2>&1; then
  echo "Ошибка: apt-get не найден."
  exit 1
fi

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo " ПОЛНОЕ ОБНОВЛЕНИЕ СИСТЕМЫ VPS"
echo "=================================================="
echo "ОС: ${PRETTY_NAME:-unknown}"
echo "Дата: $(date -Is)"
echo "Журнал: $LOG_FILE"
echo
echo "Будут обновлены системные пакеты, ядро и компоненты ОС."
echo "Будут удалены только ставшие ненужными зависимости."
echo "Стороннее ПО и прикладные сервисы устанавливаться не будут."
echo

if [[ -t 0 ]]; then
  read -r -p "Начать обновление? [y/N]: " answer
  case "$answer" in
    y|Y|yes|YES|д|Д|да|ДА) ;;
    *) echo "Отменено."; exit 0 ;;
  esac
else
  echo "Подтверждение не запрошено: скрипт запущен без интерактивного терминала."
fi

echo
echo "===== ОЖИДАНИЕ ОСВОБОЖДЕНИЯ APT/DPKG ====="
for attempt in $(seq 1 120); do
  busy=0
  if command -v fuser >/dev/null 2>&1; then
    for lock in /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock; do
      if fuser "$lock" >/dev/null 2>&1; then busy=1; break; fi
    done
  else
    pgrep -x apt >/dev/null || pgrep -x apt-get >/dev/null || pgrep -x dpkg >/dev/null || busy=0
    if pgrep -x apt >/dev/null || pgrep -x apt-get >/dev/null || pgrep -x dpkg >/dev/null; then busy=1; fi
  fi
  [[ "$busy" -eq 0 ]] && break
  if [[ "$attempt" -eq 120 ]]; then
    echo "Ошибка: менеджер пакетов занят более 10 минут. Повтори запуск позже."
    exit 1
  fi
  sleep 5
done

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

echo
echo "===== 1. ОБНОВЛЕНИЕ СПИСКА ПАКЕТОВ ====="
apt-get update

echo
echo "===== 2. УСТАНОВКА ВСЕХ ДОСТУПНЫХ ОБНОВЛЕНИЙ ====="
apt-get "${APT_OPTS[@]}" full-upgrade -y

echo
echo "===== 3. НАСТРОЙКА НЕЗАВЕРШЁННЫХ ПАКЕТОВ ====="
dpkg --configure -a

echo
echo "===== 4. УДАЛЕНИЕ НЕИСПОЛЬЗУЕМЫХ ЗАВИСИМОСТЕЙ ====="
apt-get "${APT_OPTS[@]}" autoremove --purge -y

echo
echo "===== 5. ОЧИСТКА КЭША ПАКЕТОВ ====="
apt-get clean
apt-get autoclean -y

echo
echo "===== 6. ИТОГОВАЯ ПРОВЕРКА ====="
if dpkg --audit | grep -q .; then
  echo "ВНИМАНИЕ: dpkg сообщает о пакетах, требующих внимания:"
  dpkg --audit
else
  echo "dpkg: ошибок незавершённой установки не обнаружено."
fi

echo
if [[ -f /var/run/reboot-required ]]; then
  echo "=================================================="
  echo " ТРЕБУЕТСЯ ПЕРЕЗАГРУЗКА VPS"
  echo "=================================================="
  if [[ -f /var/run/reboot-required.pkgs ]]; then
    echo "Причина:"
    cat /var/run/reboot-required.pkgs
  fi
  if [[ -t 0 ]]; then
    read -r -p "Перезагрузить сервер сейчас? [y/N]: " reboot_answer
    case "$reboot_answer" in
      y|Y|yes|YES|д|Д|да|ДА)
        echo "Перезагрузка..."
        sync
        reboot
        ;;
      *) echo "Перезагрузка отложена. Выполни reboot вручную, когда будешь готов." ;;
    esac
  else
    echo "Скрипт запущен без терминала. Перезагрузку выполни вручную командой: reboot"
  fi
else
  echo "Перезагрузка по результатам обновления не требуется."
fi

echo
echo "===== ОБНОВЛЕНИЕ ЗАВЕРШЕНО ====="
echo "Журнал сохранён: $LOG_FILE"
