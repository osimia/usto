# USTO Architecture

## Целевая Архитектура

USTO состоит из четырех основных частей:

- Flutter mobile app;
- Go backend API;
- PostgreSQL database;
- Admin web panel.

Дополнительные сервисы:

- SMS provider;
- push notifications через Firebase;
- object storage для фото и документов;
- payment provider или ручной баланс на MVP.

## Backend Структура

Рекомендуемая структура Go-проекта:

```text
cmd/api/main.go
internal/config
internal/http
internal/auth
internal/users
internal/categories
internal/orders
internal/responses
internal/chats
internal/wallet
internal/verification
internal/admin
internal/storage
internal/notifications
migrations
```

## Flutter Структура

Рекомендуемая структура Flutter-приложения:

```text
lib/
  app/
    app.dart
    router.dart
    theme.dart
  core/
    api/
    storage/
    errors/
    widgets/
  features/
    auth/
    onboarding/
    customer/
    master/
    orders/
    responses/
    chat/
    wallet/
    profile/
    verification/
```

## Принципы API

- мобильное приложение не должно зависеть от структуры базы;
- каждый endpoint возвращает только нужные мобильному экрану данные;
- ошибки всегда в одном формате;
- пагинация через cursor;
- все приватные endpoint требуют JWT;
- admin endpoint отдельно защищены ролью `admin`.

## Хранение Файлов

Фото заявок, портфолио, аватары и документы не хранятся в PostgreSQL.

В базе хранится:

- URL;
- тип файла;
- владелец;
- статус проверки;
- дата загрузки.

Для MVP можно хранить файлы локально, но интерфейс storage лучше сразу сделать абстракцией, чтобы потом перейти на S3-compatible storage.

## Push Уведомления

События для уведомлений:

- новый отклик на заявку;
- мастер выбран;
- новое сообщение;
- заявка отменена;
- заказ завершен;
- статус верификации изменен;
- пополнение баланса.

## Безопасность

Нужно предусмотреть:

- refresh token rotation;
- хранение токенов Flutter через secure storage;
- rate limit для SMS;
- ограничение загрузки файлов;
- проверку ролей на backend;
- audit log для admin-действий;
- блокировку пользователя;
- защиту документов мастеров.

## MVP Решения

Чтобы быстрее получить рабочую версию:

- сначала использовать тестовый SMS-код в dev-режиме;
- платежи заменить ручным балансом;
- admin сделать минимальным;
- карту заменить текстовым адресом и районом;
- real-time чат можно начать с polling, потом перейти на WebSocket.
