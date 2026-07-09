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

## Сборка exe для Windows

```bash
go build -o usto.exe .
```

После этого можно запускать:

```bash
.\usto.exe
```
