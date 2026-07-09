# USTO Database Schema

## Выбор Базы

Production-база: PostgreSQL.

SQLite можно оставить только для локального прототипа или быстрых demo-запусков.

## Основные Таблицы

### users

Пользователь и данные входа.

- `id uuid primary key`;
- `phone text not null`;
- `phone_norm text not null`;
- `role text not null`;
- `status text not null`;
- `created_at timestamptz not null`;
- `updated_at timestamptz not null`;
- `last_login_at timestamptz`.

### profiles

Общий профиль пользователя.

- `id uuid primary key`;
- `user_id uuid references users(id)`;
- `name text`;
- `city text`;
- `district text`;
- `avatar_url text`;
- `created_at timestamptz`;
- `updated_at timestamptz`.

### master_profiles

Профиль мастера.

- `id uuid primary key`;
- `user_id uuid references users(id)`;
- `bio text`;
- `experience_years int`;
- `rating numeric(3,2)`;
- `reviews_count int`;
- `completed_orders_count int`;
- `verification_status text`;
- `is_available boolean`;
- `created_at timestamptz`;
- `updated_at timestamptz`.

### categories

Категории услуг.

- `id uuid primary key`;
- `name text not null`;
- `icon text`;
- `sort_order int`;
- `is_active boolean`;

### services

Услуги внутри категорий.

- `id uuid primary key`;
- `category_id uuid references categories(id)`;
- `name text not null`;
- `is_active boolean`.

### master_services

Какие услуги выполняет мастер.

- `id uuid primary key`;
- `master_id uuid references master_profiles(id)`;
- `service_id uuid references services(id)`;
- `price_from int`;
- `price_to int`.

### orders

Заявки заказчиков.

- `id uuid primary key`;
- `customer_id uuid references users(id)`;
- `category_id uuid references categories(id)`;
- `service_id uuid references services(id)`;
- `selected_master_id uuid references users(id)`;
- `title text not null`;
- `description text`;
- `city text`;
- `district text`;
- `address text`;
- `lat numeric`;
- `lng numeric`;
- `budget_min int`;
- `budget_max int`;
- `deadline_type text`;
- `status text not null`;
- `created_at timestamptz`;
- `updated_at timestamptz`;
- `completed_at timestamptz`;
- `cancelled_at timestamptz`.

### order_photos

Фото заявки.

- `id uuid primary key`;
- `order_id uuid references orders(id)`;
- `url text not null`;
- `sort_order int`;
- `created_at timestamptz`.

### responses

Отклики мастеров.

- `id uuid primary key`;
- `order_id uuid references orders(id)`;
- `master_id uuid references users(id)`;
- `price int not null`;
- `comment text`;
- `status text not null`;
- `created_at timestamptz`;
- `updated_at timestamptz`.

### chats

Чат по заказу.

- `id uuid primary key`;
- `order_id uuid references orders(id)`;
- `customer_id uuid references users(id)`;
- `master_id uuid references users(id)`;
- `created_at timestamptz`.

### messages

Сообщения.

- `id uuid primary key`;
- `chat_id uuid references chats(id)`;
- `sender_id uuid references users(id)`;
- `text text`;
- `attachment_url text`;
- `created_at timestamptz`;
- `read_at timestamptz`.

### wallets

Кошельки пользователей.

- `id uuid primary key`;
- `user_id uuid references users(id)`;
- `balance int not null default 0`;
- `created_at timestamptz`;
- `updated_at timestamptz`.

### transactions

История баланса.

- `id uuid primary key`;
- `wallet_id uuid references wallets(id)`;
- `type text not null`;
- `amount int not null`;
- `status text not null`;
- `description text`;
- `external_id text`;
- `created_at timestamptz`.

### reviews

Отзывы.

- `id uuid primary key`;
- `order_id uuid references orders(id)`;
- `customer_id uuid references users(id)`;
- `master_id uuid references users(id)`;
- `rating int not null`;
- `text text`;
- `created_at timestamptz`.

### verification_documents

Документы мастера.

- `id uuid primary key`;
- `master_id uuid references master_profiles(id)`;
- `document_type text not null`;
- `file_url text not null`;
- `status text not null`;
- `rejection_reason text`;
- `created_at timestamptz`;
- `reviewed_at timestamptz`;
- `reviewed_by uuid references users(id)`.

### notifications

Push/in-app уведомления.

- `id uuid primary key`;
- `user_id uuid references users(id)`;
- `type text not null`;
- `title text not null`;
- `body text`;
- `payload jsonb`;
- `read_at timestamptz`;
- `created_at timestamptz`.

### complaints

Жалобы.

- `id uuid primary key`;
- `order_id uuid references orders(id)`;
- `from_user_id uuid references users(id)`;
- `against_user_id uuid references users(id)`;
- `reason text not null`;
- `text text`;
- `status text not null`;
- `created_at timestamptz`;
- `resolved_at timestamptz`.

## Индексы

Нужны индексы:

- `users(phone_norm, role)` unique;
- `users(role, status)`;
- `orders(customer_id, status)`;
- `orders(category_id, district, status)`;
- `responses(order_id)`;
- `responses(master_id)`;
- `messages(chat_id, created_at)`;
- `transactions(wallet_id, created_at)`;
- `reviews(master_id)`.

## Миграции

Рекомендуемый инструмент для Go:

- `golang-migrate/migrate`;
- или `pressly/goose`.

Для проекта USTO проще начать с `goose`: SQL-миграции понятны и удобно запускать локально.
