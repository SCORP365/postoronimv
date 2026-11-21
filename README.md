# Установка менеджера ботов PostoronimV

Этот репозиторий содержит публичный установщик. Сам менеджер, исходники ботов и резервные копии находятся в приватном репозитории [SCORP365/postoronimv_bots](https://github.com/SCORP365/postoronimv_bots).

## Быстрая установка на чистый сервер

Подключись к серверу по SSH под пользователем `root` и выполни одну команду:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SCORP365/postoronimv/main/install_bots.sh)
```

Установщик проверит и при необходимости установит необходимые пакеты, запустит авторизацию GitHub Device Flow, клонирует приватный репозиторий и запустит установку менеджера.

## Первичная подготовка нового VPS: обновление системы

На только что арендованном VPS сначала выполни полное обновление Ubuntu/Debian:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SCORP365/postoronimv/main/update_vps.sh)
```

Скрипт обновляет списки пакетов, устанавливает все доступные обновления системы (в том числе ядра), завершает настройку пакетов, удаляет ненужные зависимости и очищает кэш APT. После этого проверяет, нужна ли перезагрузка, и предлагает перезагрузить сервер. Самостоятельно сторонние программы и прикладной софт не устанавливает.

- [Файл update_vps.sh](https://github.com/SCORP365/postoronimv/blob/main/update_vps.sh)
- [Прямая ссылка на update_vps.sh](https://raw.githubusercontent.com/SCORP365/postoronimv/main/update_vps.sh)

## Авторизация GitHub

1. Дождись QR-кода и одноразового кода в терминале.
2. Отсканируй QR-код или открой официальный адрес GitHub, показанный установщиком.
3. Введи одноразовый код на странице GitHub и подтверди доступ.
4. Не передавай одноразовый код другим людям.

После успешной авторизации установщик продолжит работу автоматически.

## Ссылки

- [Установщик install_bots.sh](https://github.com/SCORP365/postoronimv/blob/main/install_bots.sh)
- [Прямая ссылка на install_bots.sh](https://raw.githubusercontent.com/SCORP365/postoronimv/main/install_bots.sh)
- [Приватный репозиторий менеджера и ботов](https://github.com/SCORP365/postoronimv_bots)

## Изменение SSH-порта на 8422

Для переноса SSH с порта 22 на порт 8422 на Ubuntu/Debian подключись к серверу под `root` и выполни:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SCORP365/postoronimv/main/change_ssh_port.sh)
```

Скрипт создаёт резервные копии конфигурации, разрешает TCP-порт 8422 в обнаруженном UFW/firewalld, проверяет конфигурацию SSH и сначала временно оставляет открытыми оба порта — 22 и 8422. Не закрывай исходную SSH-сессию: открой второе окно терминала и проверь вход на порт 8422. Только после твоего подтверждения скрипт отключит порт 22.

Если подтверждение не дано, оба порта останутся открытыми. Внешний firewall в панели VPS при наличии нужно настроить отдельно. Скрипт не переключает автоматически обычный `ssh.service` на socket activation; если `ssh.socket` уже активен, он сохраняет этот режим и включает его автозапуск.

- [Файл change_ssh_port.sh](https://github.com/SCORP365/postoronimv/blob/main/change_ssh_port.sh)
- [Прямая ссылка на change_ssh_port.sh](https://raw.githubusercontent.com/SCORP365/postoronimv/main/change_ssh_port.sh)

## Требования

- Ubuntu или Debian с пакетным менеджером APT.
- Запуск от пользователя `root`.
- Доступ к GitHub по HTTPS.
