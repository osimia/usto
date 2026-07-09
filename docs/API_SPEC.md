# USTO API Specification

## Общие Правила

Base URL для разработки:

```text
http://localhost:8080/api
```

Формат:

- request/response: JSON;
- auth: `Authorization: Bearer <access_token>`;
- ошибки: единый JSON-формат.

Пример ошибки:

```json
{
  "error": {
    "code": "validation_error",
    "message": "phone is required",
    "fields": {
      "phone": "required"
    }
  }
}
```

## Auth

### POST `/auth/request-code`

Запрос SMS-кода.

Dev-режим текущего backend: код задается через `DEV_SMS_CODE`, по умолчанию `1234`.

Request:

```json
{
  "phone": "+992900000000"
}
```

Response:

```json
{
  "requestId": "sms_request_id",
  "ttlSeconds": 120
}
```

### POST `/auth/verify-code`

Проверка SMS-кода и выдача токенов.

Request:

```json
{
  "phone": "+992900000000",
  "code": "1234",
  "role": "customer"
}
```

Response:

```json
{
  "accessToken": "jwt",
  "refreshToken": "jwt",
  "user": {
    "id": "user_id",
    "phone": "+992900000000",
    "role": "customer",
    "name": "Акрам Осими",
    "city": "Душанбе"
  }
}
```

### POST `/auth/refresh`

Обновление access token.

### POST `/auth/logout`

Выход с устройства.

## Profile

### GET `/me`

Возвращает текущего пользователя и профиль.

Response:

```json
{
  "user": {
    "id": "user_id",
    "phone": "+992900000000",
    "role": "customer",
    "name": "Акрам Осими",
    "city": "Душанбе"
  },
  "profile": {
    "id": "profile_id",
    "role": "customer",
    "name": "Акрам Осими",
    "phone": "+992900000000",
    "city": "Душанбе",
    "district": "Сино",
    "avatarUrl": ""
  }
}
```

### PATCH `/me/profile`

Обновляет имя, город, район, аватар и базовые данные.

Request:

```json
{
  "name": "Акрам Осими",
  "city": "Душанбе",
  "district": "Сино",
  "avatarUrl": "https://example.com/avatar.jpg"
}
```

## Categories

### GET `/categories`

Список категорий услуг.

Для совместимости `GET /api/categories` возвращает массив. Для Flutter используем:

```text
GET /api/categories?wrap=1
```

Response:

```json
{
  "categories": [
    {
      "id": 1,
      "name": "Сантехника",
      "icon": "🔧",
      "theme": "blue"
    }
  ]
}
```

### GET `/categories/{id}/services`

Список услуг внутри категории.

Response:

```json
{
  "services": ["Краны", "Трубы", "Бойлеры"]
}
```

## Orders

### POST `/orders`

Создание заявки заказчиком.

Request:

```json
{
  "title": "Починить кран",
  "desc": "Течет смеситель на кухне",
  "category": "Сантехника",
  "district": "Сино",
  "address": "ул. Рудаки 45",
  "budget": "до 300 TJS",
  "when": "Сегодня"
}
```

Response:

```json
{
  "order": {
    "id": 1,
    "title": "Починить кран",
    "desc": "Течет смеситель на кухне",
    "category": "Сантехника",
    "district": "Сино",
    "address": "ул. Рудаки 45",
    "budget": "до 300 TJS",
    "when": "Сегодня",
    "status": "Активная"
  }
}
```

### GET `/orders`

Список заявок. Для мастера возвращает ленту доступных заявок.

Query:

- `categoryId`;
- `category`;
- `district`;
- `status`;
- `q`;
- `limit`;
- `cursor`.

Для совместимости старого web-прототипа `GET /api/orders` возвращает массив. Для Flutter используем wrapper:

```text
GET /api/orders?wrap=1
```

Response:

```json
{
  "orders": []
}
```

### GET `/orders/{id}`

Детали заявки.

Response:

```json
{
  "order": {},
  "responses": []
}
```

### PATCH `/orders/{id}`

Редактирование заявки заказчиком до выбора мастера.

### POST `/orders/{id}/cancel`

Отмена заявки.

### POST `/orders/{id}/select-master`

Выбор мастера по отклику.

Request:

```json
{
  "responseId": "uuid"
}
```

### POST `/orders/{id}/complete`

Завершение заказа.

## Responses

### POST `/orders/{id}/responses`

Отклик мастера на заявку.

Request:

```json
{
  "price": 250,
  "comment": "Могу приехать сегодня после 17:00"
}
```

Response:

```json
{
  "response": {
    "id": 1,
    "orderId": 1,
    "masterId": 1,
    "price": 250,
    "comment": "Могу приехать сегодня после 17:00"
  },
  "order": {}
}
```

### GET `/orders/{id}/responses`

Список откликов по заявке.

Response:

```json
{
  "responses": []
}
```

### DELETE `/responses/{id}`

Удаление отклика мастером, если мастер еще не выбран.

## Masters

### GET `/masters`

Список мастеров.

Query:

- `service`;
- `q`;
- `limit`.

Для совместимости старого web-прототипа `GET /api/masters` возвращает массив. Для Flutter используем:

```text
GET /api/masters?wrap=1
```

Response:

```json
{
  "masters": [
    {
      "id": 1,
      "name": "Фаррух Турсунов",
      "service": "Сантехника",
      "rating": 4.9,
      "reviews": 127,
      "price": "от 120 TJS",
      "verified": true,
      "bio": "Занимаюсь сантехникой 8 лет.",
      "skills": ["краны"],
      "portfolio": []
    }
  ]
}
```

### GET `/masters/{id}`

Публичный профиль мастера.

Response:

```json
{
  "master": {}
}
```

### PATCH `/masters/me`

Обновление профиля мастера.

### POST `/masters/me/services`

Добавление услуги мастера.

### POST `/masters/me/portfolio`

Добавление фото работы.

## Verification

### POST `/verification/documents`

Загрузка документов мастера.

Request:

```json
{
  "documentType": "passport",
  "fileUrl": "https://example.com/passport.jpg"
}
```

Response:

```json
{
  "document": {
    "id": 1,
    "masterProfileId": 2,
    "documentType": "passport",
    "fileUrl": "https://example.com/passport.jpg",
    "status": "pending"
  },
  "status": "pending_verification"
}
```

### GET `/verification/status`

Текущий статус проверки.

Response:

```json
{
  "status": "pending_verification",
  "verified": false,
  "documents": []
}
```

Для совместимости старого web-прототипа `POST /api/verification` подтверждает мастера и возвращает snapshot. Для Flutter можно использовать:

```text
POST /api/verification?wrap=1
```

## Chats

### GET `/chats`

Список чатов пользователя.

Response:

```json
{
  "chats": [
    {
      "id": 1,
      "orderId": 1,
      "orderTitle": "Починить кран",
      "customer": "Акрам Осими",
      "master": "Фаррух Турсунов",
      "lastMessage": "Да, после 17:00 буду свободен.",
      "lastTime": "15:04",
      "unreadCount": 0
    }
  ]
}
```

### GET `/chats/{id}/messages`

Сообщения чата.

Response:

```json
{
  "messages": []
}
```

### POST `/chats/{id}/messages`

Отправка сообщения.

Request:

```json
{
  "text": "Здравствуйте, когда сможете приехать?",
  "fromRole": "customer"
}
```

Response:

```json
{
  "message": {
    "id": 1,
    "chatId": 1,
    "fromRole": "customer",
    "text": "Здравствуйте, когда сможете приехать?",
    "createdAt": "15:04"
  }
}
```

## Wallet

### GET `/wallet`

Баланс и последние транзакции.

Response:

```json
{
  "wallet": {
    "balance": 85,
    "currency": "TJS",
    "transactions": []
  }
}
```

### POST `/wallet/topup`

Пополнение баланса.

Request:

```json
{
  "amount": 100
}
```

Для совместимости старого web-прототипа `POST /api/wallet/topup` возвращает snapshot. Для Flutter используем:

```text
POST /api/wallet/topup?wrap=1
```

Response:

```json
{
  "wallet": {
    "balance": 185,
    "currency": "TJS"
  }
}
```

### GET `/wallet/transactions`

История транзакций.

Response:

```json
{
  "transactions": []
}
```

## Reviews

### POST `/orders/{id}/review`

Отзыв после завершения заказа.

Request:

```json
{
  "rating": 5,
  "text": "Работа выполнена аккуратно"
}
```

### GET `/masters/{id}/reviews`

Отзывы мастера.

## Admin API

Все admin endpoint требуют роль `admin`.

- `GET /admin/users`;
- `GET /admin/masters/pending`;
- `POST /admin/masters/{id}/approve`;
- `POST /admin/masters/{id}/reject`;
- `GET /admin/orders`;
- `GET /admin/transactions`;
- `GET /admin/complaints`;
- `POST /admin/users/{id}/block`;
- `POST /admin/users/{id}/unblock`.
