# Установка менеджера ботов PostoronimV

Этот репозиторий содержит публичный установщик. Сам менеджер, исходники ботов и резервные копии находятся в приватном репозитории [SCORP365/postoronimv_bots](https://github.com/SCORP365/postoronimv_bots).

## Быстрая установка на чистый сервер

Подключись к серверу по SSH под пользователем `root` и выполни одну команду:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/SCORP365/postoronimv/main/install_bots.sh)
```

Установщик проверит и при необходимости установит необходимые пакеты, запустит авторизацию GitHub Device Flow, клонирует приватный репозиторий и запустит установку менеджера.

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

## Требования

- Ubuntu или Debian с пакетным менеджером APT.
- Запуск от пользователя `root`.
- Доступ к GitHub по HTTPS.
