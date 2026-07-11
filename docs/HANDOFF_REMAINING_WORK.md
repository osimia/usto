# USTO — передача части работы (для Codex)

## Что это за проект

USTO — маркетплейс услуг (Таджикистан): заказчики публикуют заявки, мастера откликаются,
общаются в чате, получают оплату через встроенный кошелёк. Стек:
- Backend: Go, `package main`, плоские файлы в корне репозитория (без `internal/`).
- Mobile: Flutter, почти весь UI в одном файле `mobile/lib/features/home/home_shell.dart`.
- БД: SQLite и PostgreSQL одновременно поддерживаются через дуал-диалектный слой (см. ниже).

## Что уже сделано (не трогать / не дублировать)

- Реальная per-user мультитенантность: `profiles` — своя строка на каждого пользователя
  (не общий demo-профиль), `orders.customer_id`, `masters.profile_id`, `transactions.profile_id`.
- Вход без SMS-кода: `POST /api/auth/login` (`{phone, role, name?, city?, district?}`) —
  существующий номер входит сразу, новый — просит `registrationRequired:true` и создаётся
  только когда пришли name/city/district. Старые `/auth/request-code`/`/auth/verify-code`
  удалены полностью, как и `Config.DevSMSCode`.
- Кошелёк и отклики — транзакционно безопасны (одна `tx.Begin()/Commit()` на списание+вставку),
  с идемпотентностью по заголовку `Idempotency-Key` (`idempotency.go`).
- Услуги вынесены в таблицу `services(category_id, name)` — не хардкод.
- `wrap=1` убран у `/wallet/topup` и `/verification` — они теперь всегда возвращают
  узкий JSON (`WalletResponse`/`VerificationStatusResponse`), а не полный legacy-снапшот.
- Rate limiting: `POST /api/auth/login` (жёсткий) и все money-moving эндпоинты
  (`/wallet/topup`, `*/responses`) — мягче, но тоже ограничены (`ratelimit.go`).
- CORS: allow-list через `ALLOWED_ORIGINS` (env), в dev без него — отражает любой origin.
- Легаси `GET/POST /api/messages` (хардкод chatID=1) удалён; чат теперь поллится через
  `GET /api/chats/{id}/messages?since={lastId}` (дельта-синхронизация).
- Переходы статуса заявки: `PATCH /api/orders/{id}/status` с `{"status":"completed"|"cancelled"}`
  (только владелец-заказчик, `completed` требует уже выбранного мастера) — `orders.go`.
- Flutter: `flutter_secure_storage` добавлен, сессия восстанавливается при старте
  (`AuthGate._restoreSession`, `core/session_storage.dart`), реальная кнопка «Выйти» в
  `ProfilePage`, чат поллится (`Timer.periodic` в `_ChatScreenState`, пауза в фоне через
  `WidgetsBindingObserver`).

## Архитектурные паттерны, которые нужно переиспользовать (не изобретать заново)

### Backend (Go)

- **Дуал-диалект БД** (`sql_dialect.go`): `sqlf(query)` конвертирует `?` → `$1,$2...` для
  Postgres (для SQLite — не трогает строку); `insertID(q dbRunner, query, args...)` делает
  `RETURNING id` для Postgres / `LastInsertId()` для SQLite; `equalityCI(column)` — регистронезависимое
  сравнение (`LOWER(x)=LOWER(?)` на Postgres, `x = ? COLLATE NOCASE` на SQLite). Использовать
  **везде**, не писать сырой SQL с `?` без `sqlf()`.
- **Схема в трёх местах** — при добавлении новых таблиц/колонок нужно править ВСЕ три места
  в `main.go`: `sqliteSchema()`, `postgresSchema()` (обе — списки CREATE TABLE), и `migrate()`
  добавить `ensureColumn(...)` вызовы для обоих диалектов (для уже существующих БД, которые
  создавались до этого изменения). Легко забыть одно из трёх — компилятор не поймает, только
  ручная проверка/тест.
- **`queryer` интерфейс** (main.go) — `QueryRow`/`Query`, реализован и `*sql.DB`, и `*sql.Tx`.
  Хелперы чтения пишутся на `queryer`, чтобы работать что вне транзакции, что внутри (видеть
  свои же незакоммиченные записи). Пример: `profileByIDFrom(q queryer, id int)`.
- **Auth-паттерн**: `a.currentUserProfile(w, r) (User, Profile, bool)` (`profile.go`) — резолвит
  JWT из заголовка `Authorization: Bearer`, сам пишет 401 при ошибке, возвращает `ok=false`.
  Ролезависимые варианты: `walletProfile` (`wallet.go`), `verificationMasterProfile`
  (`verification.go`) — то же самое + проверка роли (403 если не та роль). Для нового кода
  писать такой же тонкий wrapper, а не дублировать резолвинг claims.
- **Деньги**: `responseFeeTJS` (`responses.go`). Списание — ВСЕГДА одной транзакцией
  (`a.db.Begin()`), с guard `UPDATE ... SET balance=balance-? WHERE id=? AND balance>=?` и
  проверкой `RowsAffected()`, никогда не через два отдельных `Exec`. Идемпотентность —
  `idempotencyKeyFromRequest(r)` + `a.idempotentReplay(w, key)` в начале хендлера +
  `storeIdempotencyResult(tx, key, body, status)` перед `tx.Commit()`.
- **Rate limiting**: `ratelimit.go` — `rateLimitMW(limiter *ipRateLimiter, matches func(*http.Request) bool)`.
  Чтобы добавить новый защищённый путь — написать matcher-функцию (см. `isMoneyMovingPath`),
  не трогать существующие лимитеры.
- **Мастера/профили**: `masters` — публичный каталог, `masters.profile_id` (nullable, unique)
  связывает запись каталога с `profiles`. `masterIDForProfile(profileID) (int, bool)` и
  `profileIDForMaster(masterID) (int, bool)` (оба в `masters.go`) — резолвят в обе стороны.
  `ensureMasterDirectoryEntry(profileID) (int, error)` создаёт пустую запись при регистрации
  нового мастера — она уже редактируема, просто пока нет эндпоинта редактирования (это D1,
  не твоя часть).

### Flutter

- Почти всё в одном файле `mobile/lib/features/home/home_shell.dart` — экраны как классы
  (`StatelessWidget`/`StatefulWidget`), без роутера, простая навигация через
  `Navigator.push(MaterialPageRoute(...))`.
- `ApiClient` (`core/api/api_client.dart`) — на чистом `package:http`, НЕ Dio, без CancelToken.
  Методы: `getJson(path)`, `postJson(path, {body})`, `patchJson(path, {body})`. Бросает
  `ApiException` с `.message` на не-2xx.
- Паттерн экрана редактирования — `EditProfileScreen`/`_EditProfileScreenState`
  (`home_shell.dart`, класс `EditProfileScreen`): `TextEditingController`ы, засеянные из
  переданной мапы данных, один `_save()` вызывающий `patchJson`, `Navigator.pop()` при успехе,
  ошибка — простой красный `Text`. Копировать эту форму для новых экранов редактирования.
  (Для справки: сейчас это примерно в районе класса `EditProfileScreen`, но перед правками
  сделай `grep -n "class EditProfileScreen"` — номера строк сдвигаются от правок в этой же
  сессии).
- Поля для создания заявки (`CreateOrderScreen`/`_CreateOrderScreenState`) — 5-шаговый визард,
  контроллеры `_title`/`_desc`/`_address`/`_budget`, статические списки вроде `kDistricts`
  (уже вынесен в `core/constants.dart`).
- `OrderTile` — карточка заявки в списках (для превью фото, если будешь показывать миниатюру).

## ⚠️ Координация: общий файл home_shell.dart

И твоя часть (D2, если трогаешь Flutter-сторону — прикрепление фото в
`CreateOrderScreen`, отображение в `OrderTile`/деталях заявки), и моя часть (D1 — новый
экран редактирования профиля мастера) **редактируют один и тот же огромный файл**
`mobile/lib/features/home/home_shell.dart`. Это реальный риск конфликта слияния.

Рекомендация:
- Коммитить свою часть небольшими кусками и как можно чаще.
- Перед началом работы над Flutter-частью — `git pull`/проверить, не появились ли чужие
  изменения в этом файле; если да — влить их перед своими правками, а не поверх.
- Если возможно — сначала целиком сделать backend-часть (новые файлы, не конфликтуют),
  и только потом синхронизироваться перед правкой `home_shell.dart`.

## Твоя часть (Codex): D2 — пайплайн загрузки фото

### Backend

Новые файлы (по аналогии с существующими: `wallet.go`, `verification.go` — один файл на
тему, никаких вложенных пакетов):

- `media_storage.go` — сохранение файла на диск, content-hash имя, раздача.
- `media_resize.go` — декод/ресайз/энкод.
- `media_upload_handler.go` — сам HTTP-хендлер multipart-загрузки.

**Эндпоинт**: `POST /api/orders/{id}/photos`, multipart/form-data, поле `file`.
- `r.Body = http.MaxBytesReader(w, r.Body, 10<<20)` — лимит 10 МБ.
- `http.DetectContentType` на первые 512 байт + `image.Decode` (только `image/jpeg`/`image/png`,
  бланк-импорт `_ "image/jpeg"`, `_ "image/png"`) — если не декодируется, 400.
- Content-hash: `sha256` от сырых байт загрузки. Если для этого хеша уже все 3 файла
  существуют — не пересчитывать, просто вставить новую строку `order_photos`, указывающую
  на существующие пути (дедупликация).
- Ресайз через `golang.org/x/image/draw` (`draw.CatmullRom.Scale`) до 320 (thumb) / 800
  (medium) / 1600 (full) px по большей стороне, без апскейла. Кодирование — стандартный
  `image/jpeg` (quality 82 для medium/full, 75 для thumb). **Не WebP** — чистого Go
  энкодера нет, только cgo-обёртки над libwebp, которые ломают статическую сборку.
  Декод→повторный энкод попутно чистит EXIF (побочный эффект, не нужно писать отдельно).
- Blurhash: `github.com/bbrks/go-blurhash` (чистый Go) — посчитать на thumb-версии.
- Хранение: `{MEDIA_DIR}/orders/{hash[:2]}/{hash[2:4]}/{hash}_{thumb|medium|full}.jpg`.
  `MEDIA_DIR` — новая переменная в `Config` (`config.go`, паттерн как у `PprofAddr`),
  env `MEDIA_DIR`, дефолт `./uploads`. Добавь `uploads/` (или что выберешь дефолтом) в
  `.gitignore`.
- Раздача: новый route `/media/` в `server.go` через `http.FileServer(http.Dir(cfg.MediaDir))`,
  обёрнутый мидлварой, которая ставит `Cache-Control: public, max-age=31536000, immutable`
  (безопасно — имя файла = хеш содержимого, не может протухнуть).
- Авторизация загрузки: только владелец заявки (`currentUserProfile` + сверка
  `order.CustomerID == profile.ID`, тот же паттерн, что уже есть в `orderStatusHandler`,
  `orders.go`).

**Схема** (добавить в оба диалекта + `ensureColumn` — см. раздел про 3 места выше):

```sql
-- SQLite (sqliteSchema(), main.go)
CREATE TABLE IF NOT EXISTS order_photos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  content_hash TEXT NOT NULL, thumb_path TEXT NOT NULL, medium_path TEXT NOT NULL, full_path TEXT NOT NULL,
  width INTEGER NOT NULL, height INTEGER NOT NULL, blurhash TEXT NOT NULL DEFAULT '',
  sort_order INTEGER NOT NULL DEFAULT 0, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_order_photos_order ON order_photos(order_id, sort_order);

-- Postgres (postgresSchema(), main.go) — тот же смысл, BIGINT/BIGSERIAL/TIMESTAMPTZ
CREATE TABLE IF NOT EXISTS order_photos (
  id BIGSERIAL PRIMARY KEY,
  order_id BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  content_hash TEXT NOT NULL, thumb_path TEXT NOT NULL, medium_path TEXT NOT NULL, full_path TEXT NOT NULL,
  width INT NOT NULL, height INT NOT NULL, blurhash TEXT NOT NULL DEFAULT '',
  sort_order INT NOT NULL DEFAULT 0, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_order_photos_order ON order_photos(order_id, sort_order);
```

`Order` (main.go, JSON-структура) получает поле
`Photos []OrderPhoto` (json-тег `photos,omitempty`) (`OrderPhoto{ID, ThumbURL, MediumURL,
FullURL, Width, Height, Blurhash ...}`), заполняется через JOIN в `orderByIDFrom`
и `queryOrders` (`main.go`/`orders.go`) — присоединять `order_photos` по `order_id`, отдавать
URL как `/media/orders/....jpg`, не голый путь на диске.

**Верификация мастера тоже может переиспользовать этот пайплайн** — `verification.go`
сейчас принимает `fileUrl` как произвольную строку от клиента без проверки. Если время
позволит, замени на реальную загрузку через тот же `POST /api/orders/{id}/photos`-подобный
эндпоинт (или отдельный `/api/verification/documents/upload`) — не обязательно в первой
итерации, отметь в PR если не успеешь.

**Go-зависимости для добавления** (`go.mod`): `golang.org/x/image`, `github.com/bbrks/go-blurhash`.
Текущие зависимости (не трогать без необходимости): `github.com/google/uuid`,
`github.com/lib/pq`, `modernc.org/sqlite`.

### Flutter

- `pubspec.yaml`: добавить `image_picker`, `flutter_image_compress`, `cached_network_image`.
  Уже есть: `http`, `flutter_secure_storage`, `cupertino_icons`.
- В `_CreateOrderScreenState` (`home_shell.dart`) — шаг прикрепления фото: `image_picker`
  для выбора, `FlutterImageCompress.compressAndGetFile(..., minWidth: 1280, quality: 80,
  format: CompressFormat.jpeg)` перед загрузкой. Загрузка — новый метод `ApiClient.postMultipart`
  (сейчас его нет, нужно добавить в `core/api/api_client.dart` рядом с `postJson`/`patchJson`,
  на базе `http.MultipartRequest`, сохраняя тот же контракт ошибок через `ApiException`).
- Отображение: `CachedNetworkImage` с `cacheWidth`/`cacheHeight` = размер виджета ×
  `devicePixelRatio`, blurhash-плейсхолдер пока грузится. Встроить в `OrderTile` (список
  заявок) и в детали заявки (`OrderDetailScreen`).

## Проверка твоей части

- `go build ./... && go vet ./... && go test -race ./...` — должно быть зелено, включая
  уже существующие тесты (`wallet_test.go`, `auth_test.go`, `order_status_test.go`) —
  не должно ничего сломаться.
- `curl -F "file=@test.jpg" -H "Authorization: Bearer <token>" http://localhost:8080/api/orders/1/photos`
  — 3 файла нужных размеров на диске, ответ содержит URL всех трёх.
  Битый/не-картиночный файл → 400. Файл >10MB → 413.
  Повторная загрузка того же файла → дедуп (тот же content_hash, не пересоздаёт файлы).
- `flutter analyze` (весь проект) — 0 замечаний.
- Ручной прогон: создать заявку с фото → фото видно в списке заявок и в деталях с
  плейсхолдером во время загрузки.

## Моя часть (для справки, не трогать)

- Дозавершить кнопки «Завершить»/«Отменить» в `OrderDetailScreen` (backend уже готов:
  `PATCH /api/orders/{id}/status`).
- D1: `GET/PATCH /api/masters/me` (редактирование своей карточки в каталоге: name/service/
  bio/skills/portfolio), унификация `masters.verified`/`profiles.is_verified` через JOIN,
  новый Flutter-экран `EditMasterProfileScreen`, поиск в `MastersPage`.
