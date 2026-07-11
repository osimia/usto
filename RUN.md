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

Вход — без SMS-кода: указываете номер телефона и роль (`customer`/`master`). Существующий
номер входит сразу; новый номер должен при этом же входе указать ФИО, город и район —
только тогда создаётся аккаунт (см. пример ниже, `POST /api/auth/login`).

## Настройки

Изменить порт:

```bash
PORT=3000 go run .
```

Изменить путь к базе:

```bash
DB_PATH=data/usto.db go run .
```

JWT-секрет:

```bash
JWT_SECRET=change-me go run .
```

Разрешённые CORS-origin (через запятую); без переменной в `APP_ENV=development` сервер
отражает любой origin (удобно локально), в остальных окружениях без неё — CORS закрыт:

```bash
ALLOWED_ORIGINS=https://app.example.com,https://admin.example.com go run .
```

## Деплой на Railway

Бэкенд подготовлен для Railway:

- `Dockerfile` собирает и запускает Go-сервис;
- `railway.json` задаёт Docker build и healthcheck;
- доступны `GET /healthz` и `GET /api/health`;
- поддерживаются `PostgreSQL` и `SQLite`.

### Рекомендуемый вариант: PostgreSQL

Для Railway лучше использовать встроенный PostgreSQL, а не SQLite на volume.

### Что сделать в Railway

1. Создать service из этого репозитория.
2. Railway автоматически использует `Dockerfile`.
3. Добавить Railway PostgreSQL.
4. Передать `DATABASE_URL` в backend service.
5. Задать переменные окружения:

```text
APP_ENV=production
PORT=8080
DB_DRIVER=postgres
DATABASE_URL=<Railway PostgreSQL URL>
JWT_SECRET=<long-random-secret>
ALLOWED_ORIGINS=https://<домен фронтенда>
ACCESS_TOKEN_HOURS=24
REFRESH_TOKEN_HOURS=720
```

Есть пример локального набора переменных: [.env.example](/home/osimi/Рабочий стол/usto/.env.example).

### SQLite fallback

Если временно нужен SQLite, тогда для Railway обязательно нужен persistent volume:

```text
DB_DRIVER=sqlite
DB_PATH=/data/usto.db
```

### Проверка после деплоя

```bash
curl https://<your-railway-domain>/healthz
curl https://<your-railway-domain>/api/health
```

Ожидаемый ответ:

```json
{"ok":true,"env":"production"}
```

## Локальный PostgreSQL через Docker Compose

Чтобы прогнать почти тот же сценарий, что и на Railway:

```bash
docker compose up --build
```

Сервисы:

- PostgreSQL: `localhost:5432`
- Backend: `http://localhost:8080`

Проверка:

```bash
curl http://localhost:8080/healthz
curl http://localhost:8080/api/health
```

Остановить:

```bash
docker compose down
```

Остановить и удалить volume базы:

```bash
docker compose down -v
```

Проверка auth API (без SMS-кода):

```bash
# Новый номер без ФИО — сервер просит анкету, аккаунт не создаётся:
curl -X POST -H 'Content-Type: application/json' \
  --data '{"phone":"+992900112233","role":"customer"}' \
  http://localhost:8080/api/auth/login
# => {"registrationRequired":true}

# Тот же новый номер с анкетой — аккаунт создаётся, сразу приходят токены:
curl -X POST -H 'Content-Type: application/json' \
  --data '{"phone":"+992900112233","role":"customer","name":"Иван Иванов","city":"Душанбе","district":"Сино"}' \
  http://localhost:8080/api/auth/login

# Повторный вход тем же номером — сразу токены, анкета не нужна:
curl -X POST -H 'Content-Type: application/json' \
  --data '{"phone":"+992900112233","role":"customer"}' \
  http://localhost:8080/api/auth/login
```

Тот же приём с `role=master` (или любой другой новый номер) даёт токен мастера — заявку создаёт `customer`, откликается/пополняет кошелёк/проходит верификацию/редактирует карточку в каталоге `master`:

```bash
curl -X POST -H 'Content-Type: application/json' \
  --data '{"phone":"+992918445566","role":"master","name":"Шер Назаров","city":"Душанбе","district":"Сино"}' \
  http://localhost:8080/api/auth/login
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

Проверка заказов (создание заявки и отклик требуют `Authorization`, т.к. привязаны к реальному профилю — см. п. "После получения accessToken" выше; отклик даёт токен роли `master`, заявку — роли `customer`):

```bash
curl 'http://localhost:8080/api/orders?wrap=1&district=Сино'

curl http://localhost:8080/api/orders/1

# Заявки текущего пользователя (customer):
curl -H "Authorization: Bearer <accessToken customer>" \
  'http://localhost:8080/api/orders?mine=1&wrap=1'

curl -X POST -H "Authorization: Bearer <accessToken customer>" \
  -H 'Content-Type: application/json' \
  --data '{"title":"Собрать мебель","category":"Мебель","district":"Сино"}' \
  http://localhost:8080/api/orders

curl http://localhost:8080/api/orders/1/responses

curl -X POST -H "Authorization: Bearer <accessToken master>" \
  -H 'Content-Type: application/json' \
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

Проверка кошелька (только для роли `master`, требует `Authorization` — кошелёк принадлежит авторизованному аккаунту, а не общему demo-профилю):

```bash
curl -H "Authorization: Bearer <accessToken master>" http://localhost:8080/api/wallet

curl -H "Authorization: Bearer <accessToken master>" http://localhost:8080/api/wallet/transactions

curl -X POST -H "Authorization: Bearer <accessToken master>" \
  -H 'Content-Type: application/json' \
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

Проверка верификации (только для роли `master`, требует `Authorization`):

```bash
curl -H "Authorization: Bearer <accessToken master>" http://localhost:8080/api/verification/status

curl -X POST -H "Authorization: Bearer <accessToken master>" \
  -H 'Content-Type: application/json' \
  --data '{"documentType":"passport","fileUrl":"https://example.com/passport.jpg"}' \
  http://localhost:8080/api/verification/documents

curl -X POST -H "Authorization: Bearer <accessToken master>" 'http://localhost:8080/api/verification?wrap=1'
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

- вход по телефону без SMS-кода (номер + роль; анкета ФИО/город/район — только при
  первом входе нового номера), сессия сохраняется между запусками (refresh-токен в
  secure storage), реальный выход из аккаунта;
- главная сводка;
- список заявок и детали заявки, смена статуса заявки (завершить/отменить);
- создание заявки;
- просмотр откликов и отправка отклика;
- список мастеров с поиском и профиль мастера;
- чат и отправка сообщения (новые сообщения подтягиваются поллингом);
- кошелек: баланс, транзакции, пополнение;
- профиль пользователя и редактирование имени/города/района;
- для роли master — редактирование своей карточки в каталоге мастеров (имя, услуга,
  описание, навыки, портфолио);
- верификация мастера: статус, отправка документа, dev-подтверждение.
