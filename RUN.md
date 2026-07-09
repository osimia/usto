# USTO Go Web

В проекте реализована веб-версия USTO на Go с базой данных SQLite.

## Что внутри

- `main.go` - Go backend, REST API, миграции SQLite и стартовые demo-данные.
- `go.mod` - модуль Go и зависимость `modernc.org/sqlite`.
- `web/index.html` - точка входа frontend.
- `web/styles.css` - мобильная и desktop-адаптация.
- `web/app.js` - SPA-логика экранов: onboarding, auth, заказчик, мастер, заявки, отклики, чат, кошелёк, профиль.
- `usto.db` - создаётся автоматически при первом запуске.

## Запуск

Нужен установленный Go.

```bash
go mod tidy
go run .
```

Открыть:

```text
http://localhost:8080
```

Демо-вход:

```text
SMS-код: 1234
```

## Настройки

Изменить порт:

```bash
PORT=3000 go run .
```

Изменить путь к базе:

```bash
DB_PATH=data/usto.db go run .
```

Dev-настройки авторизации:

```bash
DEV_SMS_CODE=1234 JWT_SECRET=change-me go run .
```

Проверка auth API:

```bash
curl -X POST -H 'Content-Type: application/json' \
  --data '{"phone":"+992900112233"}' \
  http://localhost:8080/api/auth/request-code

curl -X POST -H 'Content-Type: application/json' \
  --data '{"phone":"+992900112233","code":"1234","role":"customer"}' \
  http://localhost:8080/api/auth/verify-code
```

После получения `accessToken`:

```bash
curl -H "Authorization: Bearer <accessToken>" \
  http://localhost:8080/api/me

curl -X PATCH -H "Authorization: Bearer <accessToken>" \
  -H 'Content-Type: application/json' \
  --data '{"name":"Акрам Осими","city":"Душанбе","district":"Сино","avatarUrl":""}' \
  http://localhost:8080/api/me/profile
```

Проверка заказов:

```bash
curl 'http://localhost:8080/api/orders?wrap=1&district=Сино'

curl http://localhost:8080/api/orders/1

curl http://localhost:8080/api/orders/1/responses

curl -X POST -H 'Content-Type: application/json' \
  --data '{"price":250,"comment":"Могу приехать сегодня после 17:00"}' \
  http://localhost:8080/api/orders/1/responses
```

Проверка чата:

```bash
curl http://localhost:8080/api/chats

curl http://localhost:8080/api/chats/1/messages

curl -X POST -H 'Content-Type: application/json' \
  --data '{"text":"Здравствуйте, когда сможете приехать?","fromRole":"customer"}' \
  http://localhost:8080/api/chats/1/messages
```

Проверка кошелька:

```bash
curl http://localhost:8080/api/wallet

curl http://localhost:8080/api/wallet/transactions

curl -X POST -H 'Content-Type: application/json' \
  --data '{"amount":100}' \
  'http://localhost:8080/api/wallet/topup?wrap=1'
```

Проверка мастеров:

```bash
curl 'http://localhost:8080/api/masters?wrap=1&service=Сантехника'

curl http://localhost:8080/api/masters/1
```

Проверка категорий:

```bash
curl 'http://localhost:8080/api/categories?wrap=1'

curl http://localhost:8080/api/categories/1/services
```

Проверка верификации:

```bash
curl http://localhost:8080/api/verification/status

curl -X POST -H 'Content-Type: application/json' \
  --data '{"documentType":"passport","fileUrl":"https://example.com/passport.jpg"}' \
  http://localhost:8080/api/verification/documents

curl -X POST 'http://localhost:8080/api/verification?wrap=1'
```

## Сборка exe для Windows

```bash
go build -o usto.exe .
```

После этого можно запускать:

```bash
.\usto.exe
```

## Flutter mobile

Мобильный проект находится в `mobile/`.

Android emulator использует `10.0.2.2`, чтобы обращаться к backend на хосте:

```bash
cd mobile
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api
```

iOS simulator обычно может обращаться к `localhost`:

```bash
cd mobile
flutter run --dart-define=API_BASE_URL=http://localhost:3000/api
```

Проверки:

```bash
cd mobile
flutter analyze
flutter test
```

Сейчас во Flutter уже подключены:

- вход по телефону и dev SMS-коду;
- главная сводка;
- список заявок и детали заявки;
- создание заявки;
- просмотр откликов и отправка отклика;
- список мастеров и профиль мастера;
- чат и отправка сообщения;
- кошелек: баланс, транзакции, пополнение;
- профиль пользователя и редактирование имени/города/района.
- верификация мастера: статус, отправка документа, dev-подтверждение.
