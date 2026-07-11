package main

import (
	"context"
	"database/sql"
	"embed"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	_ "github.com/lib/pq"
	_ "modernc.org/sqlite"
)

//go:embed web/*
var webFS embed.FS

type App struct {
	db  *sql.DB
	cfg Config
}

type Category struct {
	ID    int    `json:"id"`
	Name  string `json:"name"`
	Icon  string `json:"icon"`
	Theme string `json:"theme"`
}

type Master struct {
	ID        int      `json:"id"`
	Name      string   `json:"name"`
	Service   string   `json:"service"`
	Rating    float64  `json:"rating"`
	Reviews   int      `json:"reviews"`
	Price     string   `json:"price"`
	Verified  bool     `json:"verified"`
	Bio       string   `json:"bio"`
	Skills    []string `json:"skills"`
	Portfolio []string `json:"portfolio"`
}

type MasterReview struct {
	ID         int    `json:"id"`
	MasterID   int    `json:"masterId"`
	AuthorName string `json:"authorName"`
	Rating     int    `json:"rating"`
	Text       string `json:"text"`
	CreatedAt  string `json:"createdAt"`
}

type Order struct {
	ID                int          `json:"id"`
	CustomerID        int          `json:"customerId,omitempty"`
	SelectedMasterID  int          `json:"selectedMasterId,omitempty"`
	PreferredMasterID int          `json:"preferredMasterId,omitempty"`
	Title             string       `json:"title"`
	Desc              string       `json:"desc"`
	Category          string       `json:"category"`
	District          string       `json:"district"`
	Address           string       `json:"address"`
	Budget            string       `json:"budget"`
	When              string       `json:"when"`
	Status            string       `json:"status"`
	Views             int          `json:"views"`
	Responses         int          `json:"responses"`
	CreatedAt         string       `json:"createdAt"`
	Photos            []OrderPhoto `json:"photos,omitempty"`
}

type OrderPhoto struct {
	ID          int    `json:"id"`
	OrderID     int    `json:"orderId"`
	ContentHash string `json:"contentHash"`
	ThumbURL    string `json:"thumbUrl"`
	MediumURL   string `json:"mediumUrl"`
	FullURL     string `json:"fullUrl"`
	Width       int    `json:"width"`
	Height      int    `json:"height"`
	Blurhash    string `json:"blurhash,omitempty"`
	SortOrder   int    `json:"sortOrder"`
	CreatedAt   string `json:"createdAt"`
}

type Response struct {
	ID        int    `json:"id"`
	OrderID   int    `json:"orderId"`
	MasterID  int    `json:"masterId"`
	Master    string `json:"master"`
	Rating    string `json:"rating"`
	Price     int    `json:"price"`
	Comment   string `json:"comment"`
	CreatedAt string `json:"createdAt"`
}

type Message struct {
	ID        int    `json:"id"`
	ChatID    int    `json:"chatId"`
	FromRole  string `json:"fromRole"`
	Text      string `json:"text"`
	CreatedAt string `json:"createdAt"`
}

type Chat struct {
	ID          int       `json:"id"`
	OrderID     int       `json:"orderId"`
	OrderTitle  string    `json:"orderTitle"`
	Customer    string    `json:"customer"`
	Master      string    `json:"master"`
	LastMessage string    `json:"lastMessage"`
	LastTime    string    `json:"lastTime"`
	UnreadCount int       `json:"unreadCount"`
	Order       *Order    `json:"order,omitempty"`
	Messages    []Message `json:"messages,omitempty"`
}

type Transaction struct {
	ID        int    `json:"id"`
	Label     string `json:"label"`
	Amount    int    `json:"amount"`
	CreatedAt string `json:"createdAt"`
}

type Profile struct {
	ID             int    `json:"id"`
	Role           string `json:"role"`
	Name           string `json:"name"`
	Phone          string `json:"phone"`
	City           string `json:"city"`
	District       string `json:"district"`
	AvatarURL      string `json:"avatarUrl"`
	WalletBalance  int    `json:"walletBalance"`
	IsVerified     bool   `json:"isVerified"`
	CompletedJobs  int    `json:"completedJobs"`
	PublishedCount int    `json:"publishedCount"`
}

type User struct {
	ID        int
	Phone     string
	PhoneNorm string
	Role      string
	Status    string
	ProfileID int
}

type Bootstrap struct {
	Customer     Profile       `json:"customer"`
	Master       Profile       `json:"master"`
	Categories   []Category    `json:"categories"`
	Masters      []Master      `json:"masters"`
	Orders       []Order       `json:"orders"`
	Responses    []Response    `json:"responses"`
	Messages     []Message     `json:"messages"`
	Transactions []Transaction `json:"transactions"`
}

type ErrorResponse struct {
	Error APIError `json:"error"`
}

type APIError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func main() {
	cfg := loadConfig()

	db, err := openDB(cfg)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	app := &App{db: db, cfg: cfg}
	server := newHTTPServer(cfg, app.routes())

	startPprofServer(cfg.PprofAddr)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	serverErr := make(chan error, 1)
	go func() {
		log.Printf("USTO started: %s", cfg.publicURL())
		serverErr <- server.ListenAndServe()
	}()

	select {
	case err := <-serverErr:
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatal(err)
		}
	case <-ctx.Done():
		log.Println("shutdown signal received, draining in-flight requests")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdownCtx); err != nil {
			log.Printf("graceful shutdown error: %v", err)
		}
		log.Println("server stopped cleanly")
	}
}

func openDB(cfg Config) (*sql.DB, error) {
	setSQLDriver(cfg.DBDriver)

	var (
		db  *sql.DB
		err error
	)
	switch strings.ToLower(strings.TrimSpace(cfg.DBDriver)) {
	case "", "sqlite":
		if err := ensureDBPath(cfg.DBPath); err != nil {
			return nil, err
		}
		db, err = sql.Open("sqlite", cfg.DBPath)
		if err != nil {
			return nil, err
		}
		// SQLite only allows one writer at a time regardless of connection count,
		// and PRAGMAs like busy_timeout are per-connection — database/sql's
		// pool would otherwise hand out fresh connections that never got the
		// PRAGMA applied. Capping the pool at one connection means every
		// request serializes through the same configured connection, which also
		// matches SQLite's actual concurrency model.
		db.SetMaxOpenConns(1)
		// busy_timeout makes concurrent writers block-and-retry for up to 5s
		// instead of failing immediately with SQLITE_BUSY.
		if _, err := db.Exec(`PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA busy_timeout = 5000;`); err != nil {
			return nil, err
		}
	case "postgres":
		if strings.TrimSpace(cfg.DatabaseURL) == "" {
			return nil, errors.New("DATABASE_URL is required when DB_DRIVER=postgres")
		}
		db, err = sql.Open("postgres", cfg.DatabaseURL)
		if err != nil {
			return nil, err
		}
		db.SetMaxOpenConns(10)
		db.SetMaxIdleConns(5)
		db.SetConnMaxLifetime(30 * time.Minute)
	default:
		return nil, errors.New("unsupported DB_DRIVER: " + cfg.DBDriver)
	}
	if err := db.Ping(); err != nil {
		return nil, err
	}
	if err := migrate(db); err != nil {
		return nil, err
	}
	if err := seed(db); err != nil {
		return nil, err
	}
	if err := ensureDemoUsers(db); err != nil {
		return nil, err
	}
	if err := ensureDemoChats(db); err != nil {
		return nil, err
	}
	return db, nil
}

func ensureDBPath(path string) error {
	dir := filepath.Dir(path)
	if dir == "." || dir == "" {
		return nil
	}
	return os.MkdirAll(dir, 0o755)
}

func migrate(db *sql.DB) error {
	schema := sqliteSchema()
	if activeSQLDriver == "postgres" {
		schema = postgresSchema()
	}
	for _, stmt := range schema {
		if _, err := db.Exec(stmt); err != nil {
			return err
		}
	}
	if activeSQLDriver == "sqlite" {
		if err := ensureColumn(db, "orders", "selected_master_id", `ALTER TABLE orders ADD COLUMN selected_master_id INTEGER REFERENCES masters(id)`); err != nil {
			return err
		}
		if err := ensureColumn(db, "orders", "preferred_master_id", `ALTER TABLE orders ADD COLUMN preferred_master_id INTEGER REFERENCES masters(id)`); err != nil {
			return err
		}
		if err := ensureColumn(db, "orders", "customer_id", `ALTER TABLE orders ADD COLUMN customer_id INTEGER REFERENCES profiles(id)`); err != nil {
			return err
		}
		if err := ensureColumn(db, "profiles", "district", `ALTER TABLE profiles ADD COLUMN district TEXT NOT NULL DEFAULT ''`); err != nil {
			return err
		}
		if err := ensureColumn(db, "profiles", "avatar_url", `ALTER TABLE profiles ADD COLUMN avatar_url TEXT NOT NULL DEFAULT ''`); err != nil {
			return err
		}
		if err := ensureColumn(db, "masters", "profile_id", `ALTER TABLE masters ADD COLUMN profile_id INTEGER REFERENCES profiles(id)`); err != nil {
			return err
		}
		if err := ensureColumn(db, "transactions", "profile_id", `ALTER TABLE transactions ADD COLUMN profile_id INTEGER REFERENCES profiles(id)`); err != nil {
			return err
		}
		if err := ensureColumn(db, "order_photos", "blurhash", `ALTER TABLE order_photos ADD COLUMN blurhash TEXT NOT NULL DEFAULT ''`); err != nil {
			return err
		}
	} else if activeSQLDriver == "postgres" {
		if err := ensureColumn(db, "orders", "selected_master_id", `ALTER TABLE orders ADD COLUMN selected_master_id BIGINT REFERENCES masters(id)`); err != nil {
			return err
		}
		if err := ensureColumn(db, "orders", "preferred_master_id", `ALTER TABLE orders ADD COLUMN preferred_master_id BIGINT REFERENCES masters(id)`); err != nil {
			return err
		}
		if err := ensureColumn(db, "orders", "customer_id", `ALTER TABLE orders ADD COLUMN customer_id BIGINT REFERENCES profiles(id)`); err != nil {
			return err
		}
		if err := ensureColumn(db, "masters", "profile_id", `ALTER TABLE masters ADD COLUMN profile_id BIGINT REFERENCES profiles(id)`); err != nil {
			return err
		}
		if err := ensureColumn(db, "transactions", "profile_id", `ALTER TABLE transactions ADD COLUMN profile_id BIGINT REFERENCES profiles(id)`); err != nil {
			return err
		}
		if err := ensureColumn(db, "order_photos", "blurhash", `ALTER TABLE order_photos ADD COLUMN blurhash TEXT NOT NULL DEFAULT ''`); err != nil {
			return err
		}
	}
	// idx_masters_profile is created in the CREATE TABLE path above for fresh
	// databases; for pre-existing ones the ensureColumn calls just added the
	// column, so the unique index needs to be created here too.
	if _, err := db.Exec(`CREATE UNIQUE INDEX IF NOT EXISTS idx_masters_profile ON masters(profile_id);`); err != nil {
		return err
	}
	return nil
}

func sqliteSchema() []string {
	return []string{
		`CREATE TABLE IF NOT EXISTS users (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			phone TEXT NOT NULL,
			phone_norm TEXT NOT NULL,
			role TEXT NOT NULL,
			status TEXT NOT NULL DEFAULT 'active',
			profile_id INTEGER NOT NULL REFERENCES profiles(id),
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			last_login_at DATETIME
		);`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone_role ON users(phone_norm, role);`,
		`CREATE TABLE IF NOT EXISTS profiles (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			role TEXT NOT NULL,
			name TEXT NOT NULL,
			phone TEXT NOT NULL,
			city TEXT NOT NULL,
			district TEXT NOT NULL DEFAULT '',
			avatar_url TEXT NOT NULL DEFAULT '',
			wallet_balance INTEGER NOT NULL DEFAULT 0,
			is_verified INTEGER NOT NULL DEFAULT 0,
			completed_jobs INTEGER NOT NULL DEFAULT 0
		);`,
		`CREATE TABLE IF NOT EXISTS categories (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			name TEXT NOT NULL,
			icon TEXT NOT NULL,
			theme TEXT NOT NULL
		);`,
		`CREATE TABLE IF NOT EXISTS services (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
			name TEXT NOT NULL
		);`,
		`CREATE INDEX IF NOT EXISTS idx_services_category ON services(category_id);`,
		`CREATE TABLE IF NOT EXISTS masters (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			profile_id INTEGER REFERENCES profiles(id),
			name TEXT NOT NULL,
			service TEXT NOT NULL,
			rating REAL NOT NULL,
			reviews INTEGER NOT NULL,
			price TEXT NOT NULL,
			verified INTEGER NOT NULL,
			bio TEXT NOT NULL,
			skills TEXT NOT NULL,
			portfolio TEXT NOT NULL
		);`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_masters_profile ON masters(profile_id);`,
		`CREATE TABLE IF NOT EXISTS orders (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			customer_id INTEGER REFERENCES profiles(id),
			selected_master_id INTEGER REFERENCES masters(id),
			preferred_master_id INTEGER REFERENCES masters(id),
			title TEXT NOT NULL,
			"desc" TEXT NOT NULL,
			category TEXT NOT NULL,
			district TEXT NOT NULL,
			address TEXT NOT NULL,
			budget TEXT NOT NULL,
			when_label TEXT NOT NULL,
			status TEXT NOT NULL,
			views INTEGER NOT NULL DEFAULT 0,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
		);`,
		`CREATE INDEX IF NOT EXISTS idx_orders_feed ON orders(district, created_at DESC);`,
		`CREATE TABLE IF NOT EXISTS order_photos (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
			content_hash TEXT NOT NULL,
			thumb_path TEXT NOT NULL,
			medium_path TEXT NOT NULL,
			full_path TEXT NOT NULL,
			width INTEGER NOT NULL,
			height INTEGER NOT NULL,
			blurhash TEXT NOT NULL DEFAULT '',
			sort_order INTEGER NOT NULL DEFAULT 0,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
		);`,
		`CREATE INDEX IF NOT EXISTS idx_order_photos_order ON order_photos(order_id, sort_order, id);`,
		`CREATE TABLE IF NOT EXISTS responses (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
			master_id INTEGER NOT NULL REFERENCES masters(id),
			price INTEGER NOT NULL,
			comment TEXT NOT NULL,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
		);`,
		`CREATE TABLE IF NOT EXISTS chats (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
			master_id INTEGER NOT NULL REFERENCES masters(id),
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			UNIQUE(order_id, master_id)
		);`,
		`CREATE TABLE IF NOT EXISTS messages (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			chat_id INTEGER NOT NULL DEFAULT 1,
			from_role TEXT NOT NULL,
			text TEXT NOT NULL,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
		);`,
		`CREATE TABLE IF NOT EXISTS transactions (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			profile_id INTEGER REFERENCES profiles(id),
			label TEXT NOT NULL,
			amount INTEGER NOT NULL,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
		);`,
		`CREATE TABLE IF NOT EXISTS idempotency_keys (
			key TEXT PRIMARY KEY,
			response_body TEXT NOT NULL,
			status_code INTEGER NOT NULL,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
		);`,
		`CREATE TABLE IF NOT EXISTS verification_documents (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			master_profile_id INTEGER NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
			document_type TEXT NOT NULL,
			file_url TEXT NOT NULL,
			status TEXT NOT NULL DEFAULT 'pending',
			rejection_reason TEXT NOT NULL DEFAULT '',
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
			reviewed_at DATETIME
		);`,
		`CREATE TABLE IF NOT EXISTS master_reviews (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			master_id INTEGER NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
			author_name TEXT NOT NULL,
			rating INTEGER NOT NULL,
			text TEXT NOT NULL,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
		);`,
	}
}

func postgresSchema() []string {
	return []string{
		`CREATE TABLE IF NOT EXISTS profiles (
			id BIGSERIAL PRIMARY KEY,
			role TEXT NOT NULL,
			name TEXT NOT NULL,
			phone TEXT NOT NULL,
			city TEXT NOT NULL,
			district TEXT NOT NULL DEFAULT '',
			avatar_url TEXT NOT NULL DEFAULT '',
			wallet_balance INTEGER NOT NULL DEFAULT 0,
			is_verified INTEGER NOT NULL DEFAULT 0,
			completed_jobs INTEGER NOT NULL DEFAULT 0
		);`,
		`CREATE TABLE IF NOT EXISTS users (
			id BIGSERIAL PRIMARY KEY,
			phone TEXT NOT NULL,
			phone_norm TEXT NOT NULL,
			role TEXT NOT NULL,
			status TEXT NOT NULL DEFAULT 'active',
			profile_id BIGINT NOT NULL REFERENCES profiles(id),
			created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
			updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
			last_login_at TIMESTAMPTZ
		);`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone_role ON users(phone_norm, role);`,
		`CREATE TABLE IF NOT EXISTS categories (
			id BIGSERIAL PRIMARY KEY,
			name TEXT NOT NULL,
			icon TEXT NOT NULL,
			theme TEXT NOT NULL
		);`,
		`CREATE TABLE IF NOT EXISTS services (
			id BIGSERIAL PRIMARY KEY,
			category_id BIGINT NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
			name TEXT NOT NULL
		);`,
		`CREATE INDEX IF NOT EXISTS idx_services_category ON services(category_id);`,
		`CREATE TABLE IF NOT EXISTS masters (
			id BIGSERIAL PRIMARY KEY,
			profile_id BIGINT REFERENCES profiles(id),
			name TEXT NOT NULL,
			service TEXT NOT NULL,
			rating DOUBLE PRECISION NOT NULL,
			reviews INTEGER NOT NULL,
			price TEXT NOT NULL,
			verified INTEGER NOT NULL,
			bio TEXT NOT NULL,
			skills TEXT NOT NULL,
			portfolio TEXT NOT NULL
		);`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_masters_profile ON masters(profile_id);`,
		`CREATE TABLE IF NOT EXISTS orders (
			id BIGSERIAL PRIMARY KEY,
			customer_id BIGINT REFERENCES profiles(id),
			selected_master_id BIGINT REFERENCES masters(id),
			preferred_master_id BIGINT REFERENCES masters(id),
			title TEXT NOT NULL,
			"desc" TEXT NOT NULL,
			category TEXT NOT NULL,
			district TEXT NOT NULL,
			address TEXT NOT NULL,
			budget TEXT NOT NULL,
			when_label TEXT NOT NULL,
			status TEXT NOT NULL,
			views INTEGER NOT NULL DEFAULT 0,
			created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
		);`,
		`CREATE INDEX IF NOT EXISTS idx_orders_feed ON orders(district, created_at DESC);`,
		`CREATE TABLE IF NOT EXISTS order_photos (
			id BIGSERIAL PRIMARY KEY,
			order_id BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
			content_hash TEXT NOT NULL,
			thumb_path TEXT NOT NULL,
			medium_path TEXT NOT NULL,
			full_path TEXT NOT NULL,
			width INTEGER NOT NULL,
			height INTEGER NOT NULL,
			blurhash TEXT NOT NULL DEFAULT '',
			sort_order INTEGER NOT NULL DEFAULT 0,
			created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
		);`,
		`CREATE INDEX IF NOT EXISTS idx_order_photos_order ON order_photos(order_id, sort_order, id);`,
		`CREATE TABLE IF NOT EXISTS responses (
			id BIGSERIAL PRIMARY KEY,
			order_id BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
			master_id BIGINT NOT NULL REFERENCES masters(id),
			price INTEGER NOT NULL,
			comment TEXT NOT NULL,
			created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
		);`,
		`CREATE TABLE IF NOT EXISTS chats (
			id BIGSERIAL PRIMARY KEY,
			order_id BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
			master_id BIGINT NOT NULL REFERENCES masters(id),
			created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
			UNIQUE(order_id, master_id)
		);`,
		`CREATE TABLE IF NOT EXISTS messages (
			id BIGSERIAL PRIMARY KEY,
			chat_id BIGINT NOT NULL DEFAULT 1,
			from_role TEXT NOT NULL,
			text TEXT NOT NULL,
			created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
		);`,
		`CREATE TABLE IF NOT EXISTS transactions (
			id BIGSERIAL PRIMARY KEY,
			profile_id BIGINT REFERENCES profiles(id),
			label TEXT NOT NULL,
			amount INTEGER NOT NULL,
			created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
		);`,
		`CREATE TABLE IF NOT EXISTS idempotency_keys (
			key TEXT PRIMARY KEY,
			response_body TEXT NOT NULL,
			status_code INTEGER NOT NULL,
			created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
		);`,
		`CREATE TABLE IF NOT EXISTS verification_documents (
			id BIGSERIAL PRIMARY KEY,
			master_profile_id BIGINT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
			document_type TEXT NOT NULL,
			file_url TEXT NOT NULL,
			status TEXT NOT NULL DEFAULT 'pending',
			rejection_reason TEXT NOT NULL DEFAULT '',
			created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
			reviewed_at TIMESTAMPTZ
		);`,
		`CREATE TABLE IF NOT EXISTS master_reviews (
			id BIGSERIAL PRIMARY KEY,
			master_id BIGINT NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
			author_name TEXT NOT NULL,
			rating INTEGER NOT NULL,
			text TEXT NOT NULL,
			created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
		);`,
	}
}

func ensureColumn(db *sql.DB, table, column, alterSQL string) error {
	if activeSQLDriver == "postgres" {
		var exists bool
		err := db.QueryRow(`
			SELECT EXISTS (
				SELECT 1
				FROM information_schema.columns
				WHERE table_schema = current_schema()
				  AND table_name = $1
				  AND column_name = $2
			)
		`, table, column).Scan(&exists)
		if err != nil {
			return err
		}
		if exists {
			return nil
		}
		_, err = db.Exec(alterSQL)
		return err
	}
	rows, err := db.Query(`PRAGMA table_info(` + table + `)`)
	if err != nil {
		return err
	}
	defer rows.Close()

	for rows.Next() {
		var cid int
		var name, dataType string
		var notNull int
		var defaultValue any
		var pk int
		if err := rows.Scan(&cid, &name, &dataType, &notNull, &defaultValue, &pk); err != nil {
			return err
		}
		if name == column {
			return nil
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	_, err = db.Exec(alterSQL)
	return err
}

func seed(db *sql.DB) error {
	var count int
	if err := db.QueryRow(sqlf(`SELECT COUNT(*) FROM categories`)).Scan(&count); err != nil {
		return err
	}
	if count > 0 {
		return nil
	}

	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	mustExec := func(q string, args ...any) {
		if err != nil {
			return
		}
		_, err = tx.Exec(sqlf(q), args...)
	}

	mustExec(`INSERT INTO profiles(role,name,phone,city,wallet_balance,is_verified,completed_jobs) VALUES
		('customer','Акрам Осими','+992 900 11 22 33','Душанбе',0,1,0),
		('master','Фаррух Турсунов','+992 918 44 55 66','Душанбе',85,1,42);`)

	categories := []Category{
		{Name: "Сантехника", Icon: "🔧", Theme: "blue"},
		{Name: "Электрика", Icon: "⚡", Theme: "yellow"},
		{Name: "Ремонт", Icon: "🏗️", Theme: "pink"},
		{Name: "Мебель", Icon: "🪑", Theme: "green"},
		{Name: "Уборка", Icon: "🧹", Theme: "indigo"},
		{Name: "Грузчики", Icon: "📦", Theme: "red"},
		{Name: "Кондиционеры", Icon: "❄️", Theme: "cyan"},
		{Name: "Техника", Icon: "💻", Theme: "gray"},
	}
	for _, c := range categories {
		mustExec(`INSERT INTO categories(name,icon,theme) VALUES(?,?,?)`, c.Name, c.Icon, c.Theme)
	}

	servicesByCategory := map[string][]string{
		"Сантехника":   {"Краны", "Трубы", "Бойлеры", "Засоры"},
		"Электрика":    {"Розетки", "Проводка", "Освещение", "Щитки"},
		"Ремонт":       {"Плитка", "Покраска", "Штукатурка", "Косметический ремонт"},
		"Мебель":       {"Сборка", "Ремонт", "Установка", "Разборка"},
		"Уборка":       {"Квартира", "Офис", "После ремонта", "Генеральная"},
		"Грузчики":     {"Переезд", "Погрузка/разгрузка", "Вынос мусора", "Такелаж"},
		"Кондиционеры": {"Установка", "Обслуживание", "Ремонт", "Чистка"},
		"Техника":      {"Ремонт техники", "Настройка", "Установка", "Диагностика"},
	}
	for _, c := range categories {
		for _, service := range servicesByCategory[c.Name] {
			mustExec(`INSERT INTO services(category_id,name) VALUES((SELECT id FROM categories WHERE name=?),?)`, c.Name, service)
		}
	}

	masters := []Master{
		{Name: "Фаррух Турсунов", Service: "Сантехника", Rating: 4.9, Reviews: 127, Price: "от 120 TJS", Verified: true, Bio: "Занимаюсь сантехникой 8 лет. Работаю быстро, даю гарантию на все виды работ.", Skills: []string{"краны", "бойлеры", "трубы"}, Portfolio: []string{"🚿", "🚰", "🛁"}},
		{Name: "Рустам Исмоилов", Service: "Электрика", Rating: 4.8, Reviews: 89, Price: "от 90 TJS", Verified: true, Bio: "Монтаж розеток, щитков и освещения. Выезд по Душанбе в день обращения.", Skills: []string{"розетки", "щитки", "проводка"}, Portfolio: []string{"💡", "🔌", "⚡"}},
		{Name: "Диловар Рахимов", Service: "Ремонт", Rating: 4.7, Reviews: 64, Price: "от 150 TJS", Verified: false, Bio: "Косметический ремонт, плитка, покраска и мелкие работы по квартире.", Skills: []string{"плитка", "штукатурка", "покраска"}, Portfolio: []string{"🏠", "🧱", "🎨"}},
	}
	for _, m := range masters {
		mustExec(`INSERT INTO masters(name,service,rating,reviews,price,verified,bio,skills,portfolio) VALUES(?,?,?,?,?,?,?,?,?)`,
			m.Name, m.Service, m.Rating, m.Reviews, m.Price, boolInt(m.Verified), m.Bio, strings.Join(m.Skills, ","), strings.Join(m.Portfolio, ","))
	}
	// Link the demo master directory row to the demo master profile, so the
	// existing single-tenant demo flow keeps working unchanged now that
	// responses/wallet resolve master identity through this link instead of
	// hardcoded IDs.
	mustExec(`UPDATE masters SET profile_id=(SELECT id FROM profiles WHERE role='master' LIMIT 1) WHERE name=?`, "Фаррух Турсунов")
	now := time.Now()
	ordersSeed := []Order{
		{Title: "Починить кран на кухне", Desc: "Течёт смеситель, нужна замена картриджа", Category: "Сантехника", District: "Сино", Address: "ул. Рудаки 45", Budget: "до 300 TJS", When: "Сегодня", Status: "Активная", Views: 38, CreatedAt: now.Add(-2 * time.Hour).Format(time.RFC3339Nano)},
		{Title: "Установить розетки", Desc: "Нужно установить 4 двойные розетки в новой квартире", Category: "Электрика", District: "Фирдавси", Address: "Нусратулло Махсум 12", Budget: "200-400 TJS", When: "Завтра", Status: "Новая", Views: 8, CreatedAt: now.Add(-12 * time.Minute).Format(time.RFC3339Nano)},
		{Title: "Собрать шкаф в спальне", Desc: "Шкаф куплен, нужна аккуратная сборка", Category: "Мебель", District: "Шохмансур", Address: "Айни 7", Budget: "жду цену", When: "На неделе", Status: "Выбор мастера", Views: 22, CreatedAt: now.Add(-24 * time.Hour).Format(time.RFC3339Nano)},
	}
	for _, order := range ordersSeed {
		mustExec(`INSERT INTO orders(title,"desc",category,district,address,budget,when_label,status,views,created_at,customer_id) VALUES(?,?,?,?,?,?,?,?,?,?,(SELECT id FROM profiles WHERE role='customer' LIMIT 1))`,
			order.Title, order.Desc, order.Category, order.District, order.Address, order.Budget, order.When, order.Status, order.Views, order.CreatedAt)
	}
	responseSeeds := []struct {
		orderID   int
		masterID  int
		price     int
		comment   string
		createdAt string
	}{
		{1, 1, 350, "Добрый день! Опыт 8 лет, гарантия 1 год. Могу приехать сегодня.", now.Add(-90 * time.Minute).Format(time.RFC3339Nano)},
		{1, 2, 280, "Могу сегодня после 14:00. Все инструменты при себе.", now.Add(-70 * time.Minute).Format(time.RFC3339Nano)},
		{1, 3, 320, "Качественно, гарантия 6 месяцев. Портфолио есть в профиле.", now.Add(-45 * time.Minute).Format(time.RFC3339Nano)},
	}
	for _, item := range responseSeeds {
		mustExec(`INSERT INTO responses(order_id,master_id,price,comment,created_at) VALUES(?,?,?,?,?)`,
			item.orderID, item.masterID, item.price, item.comment, item.createdAt)
	}
	mustExec(`INSERT INTO chats(id,order_id,master_id,created_at) VALUES(?,?,?,?)`,
		1, 1, 1, now.Add(-35*time.Minute).Format(time.RFC3339Nano))
	messageSeeds := []struct {
		chatID    int
		fromRole  string
		text      string
		createdAt string
	}{
		{1, "master", "Ассалому алейкум! Готов помочь с краном. Опыт 8 лет.", now.Add(-35 * time.Minute).Format(time.RFC3339Nano)},
		{1, "customer", "Здравствуйте. Сможете приехать сегодня?", now.Add(-32 * time.Minute).Format(time.RFC3339Nano)},
		{1, "master", "Да, после 17:00 буду свободен.", now.Add(-30 * time.Minute).Format(time.RFC3339Nano)},
	}
	for _, item := range messageSeeds {
		mustExec(`INSERT INTO messages(chat_id,from_role,text,created_at) VALUES(?,?,?,?)`,
			item.chatID, item.fromRole, item.text, item.createdAt)
	}
	transactionSeeds := []struct {
		label     string
		amount    int
		createdAt string
	}{
		{"Пополнение картой", 100, now.Add(-24 * time.Hour).Format(time.RFC3339Nano)},
		{"Отклик: ремонт крана", -4, now.Add(-2 * time.Hour).Format(time.RFC3339Nano)},
		{"Стартовый бонус", 5, now.Add(-72 * time.Hour).Format(time.RFC3339Nano)},
	}
	for _, item := range transactionSeeds {
		mustExec(`INSERT INTO transactions(label,amount,created_at,profile_id) VALUES(?,?,?,(SELECT id FROM profiles WHERE role='master' LIMIT 1))`,
			item.label, item.amount, item.createdAt)
	}
	reviewSeeds := []struct {
		masterID   int
		authorName string
		rating     int
		text       string
		createdAt  string
	}{
		{1, "Алишер Назаров", 5, "Приехал вовремя, быстро устранил протечку и всё оставил чисто.", now.Add(-48 * time.Hour).Format(time.RFC3339Nano)},
		{1, "Мухаммад Р.", 5, "Хорошо объяснил причину поломки и сделал аккуратно.", now.Add(-96 * time.Hour).Format(time.RFC3339Nano)},
		{2, "Саида К.", 5, "Розетки установлены ровно, мастер вежливый и пунктуальный.", now.Add(-36 * time.Hour).Format(time.RFC3339Nano)},
		{2, "Фирдавс Т.", 4, "Работа выполнена качественно, немного задержался в пути.", now.Add(-120 * time.Hour).Format(time.RFC3339Nano)},
		{3, "Нозим А.", 5, "Плитка уложена аккуратно, всё совпало по срокам.", now.Add(-168 * time.Hour).Format(time.RFC3339Nano)},
	}
	for _, item := range reviewSeeds {
		mustExec(`INSERT INTO master_reviews(master_id,author_name,rating,text,created_at) VALUES(?,?,?,?,?)`,
			item.masterID, item.authorName, item.rating, item.text, item.createdAt)
	}

	if err != nil {
		return err
	}
	return tx.Commit()
}

func ensureDemoUsers(db *sql.DB) error {
	rows, err := db.Query(sqlf(`SELECT id,role,phone FROM profiles`))
	if err != nil {
		return err
	}

	type demoProfile struct {
		id    int
		role  string
		phone string
	}
	var profiles []demoProfile

	for rows.Next() {
		var profileID int
		var role, phone string
		if err := rows.Scan(&profileID, &role, &phone); err != nil {
			rows.Close()
			return err
		}
		profiles = append(profiles, demoProfile{id: profileID, role: role, phone: phone})
	}
	if err := rows.Close(); err != nil {
		return err
	}
	if err := rows.Err(); err != nil {
		return err
	}

	for _, profile := range profiles {
		if _, err := db.Exec(sqlf(`INSERT INTO users(phone,phone_norm,role,status,profile_id)
			VALUES(?,?,?,?,?)
			ON CONFLICT(phone_norm,role) DO UPDATE SET phone=excluded.phone, profile_id=excluded.profile_id, updated_at=CURRENT_TIMESTAMP`),
			profile.phone, normalizePhone(profile.phone), profile.role, "active", profile.id); err != nil {
			return err
		}
	}
	return nil
}

func ensureDemoChats(db *sql.DB) error {
	var count int
	if err := db.QueryRow(sqlf(`SELECT COUNT(*) FROM chats WHERE id=1`)).Scan(&count); err != nil {
		return err
	}
	if count > 0 {
		return nil
	}
	var messageCount int
	if err := db.QueryRow(sqlf(`SELECT COUNT(*) FROM messages WHERE chat_id=1`)).Scan(&messageCount); err != nil {
		return err
	}
	if messageCount == 0 {
		return nil
	}
	_, err := db.Exec(sqlf(`INSERT INTO chats(id,order_id,master_id,created_at) VALUES(?,?,?,CURRENT_TIMESTAMP) ON CONFLICT(id) DO NOTHING`), 1, 1, 1)
	return err
}

func (a *App) bootstrap(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodGet) {
		return
	}
	customer, _ := a.profile("customer")
	master, _ := a.profile("master")
	writeJSON(w, Bootstrap{
		Customer:     customer,
		Master:       master,
		Categories:   a.categories(),
		Masters:      a.masters(),
		Orders:       a.orders(),
		Responses:    a.responsesForOrder(1),
		Messages:     a.messagesForChat(1),
		Transactions: transactionsFrom(a.db, master.ID),
	})
}

func (a *App) snapshot() Bootstrap {
	customer, _ := a.profile("customer")
	master, _ := a.profile("master")
	return Bootstrap{
		Customer:     customer,
		Master:       master,
		Categories:   a.categories(),
		Masters:      a.masters(),
		Orders:       a.orders(),
		Responses:    a.responsesForOrder(1),
		Messages:     a.messagesForChat(1),
		Transactions: transactionsFrom(a.db, master.ID),
	}
}

// queryer is satisfied by both *sql.DB and *sql.Tx. Read helpers accept it so
// they can be reused unchanged inside a transaction (to see uncommitted
// writes made earlier in that same transaction) or against the pool directly.
type queryer interface {
	QueryRow(query string, args ...any) *sql.Row
	Query(query string, args ...any) (*sql.Rows, error)
}

func (a *App) profile(role string) (Profile, error) {
	return profileFrom(a.db, role)
}

func profileFrom(q queryer, role string) (Profile, error) {
	var p Profile
	var verified int
	err := q.QueryRow(sqlf(`SELECT id,role,name,phone,city,district,avatar_url,wallet_balance,is_verified,completed_jobs FROM profiles WHERE role=?`), role).
		Scan(&p.ID, &p.Role, &p.Name, &p.Phone, &p.City, &p.District, &p.AvatarURL, &p.WalletBalance, &verified, &p.CompletedJobs)
	if err != nil {
		return p, err
	}
	p.IsVerified = verified == 1
	if role == "customer" {
		_ = q.QueryRow(sqlf(`SELECT COUNT(*) FROM orders WHERE customer_id=?`), p.ID).Scan(&p.PublishedCount)
	}
	return p, nil
}

func (a *App) profileByID(id int) (Profile, error) {
	return profileByIDFrom(a.db, id)
}

func profileByIDFrom(q queryer, id int) (Profile, error) {
	var p Profile
	var verified int
	err := q.QueryRow(sqlf(`SELECT id,role,name,phone,city,district,avatar_url,wallet_balance,is_verified,completed_jobs FROM profiles WHERE id=?`), id).
		Scan(&p.ID, &p.Role, &p.Name, &p.Phone, &p.City, &p.District, &p.AvatarURL, &p.WalletBalance, &verified, &p.CompletedJobs)
	if err != nil {
		return p, err
	}
	p.IsVerified = verified == 1
	if p.Role == "customer" {
		_ = q.QueryRow(sqlf(`SELECT COUNT(*) FROM orders WHERE customer_id=?`), p.ID).Scan(&p.PublishedCount)
	}
	return p, nil
}

func (a *App) categories() []Category {
	rows, err := a.db.Query(sqlf(`SELECT id,name,icon,theme FROM categories ORDER BY id`))
	if err != nil {
		return nil
	}
	defer rows.Close()
	var items []Category
	for rows.Next() {
		var c Category
		if rows.Scan(&c.ID, &c.Name, &c.Icon, &c.Theme) == nil {
			items = append(items, c)
		}
	}
	return items
}

func (a *App) masters() []Master {
	return a.queryMasters(MasterFilters{})
}

func (a *App) orders() []Order {
	return a.queryOrders(OrderFilters{})
}

func (a *App) orderByID(id int) (Order, bool) {
	return orderByIDFrom(a.db, id)
}

func orderByIDFrom(q queryer, id int) (Order, bool) {
	row := q.QueryRow(sqlf(`SELECT o.id,o.customer_id,o.selected_master_id,o.preferred_master_id,o.title,o."desc",o.category,o.district,o.address,o.budget,o.when_label,o.status,o.views,o.created_at,COUNT(r.id)
		FROM orders o LEFT JOIN responses r ON r.order_id=o.id
		WHERE o.id=?
		GROUP BY o.id`), id)
	var o Order
	var customerID sql.NullInt64
	var selectedMasterID sql.NullInt64
	var preferredMasterID sql.NullInt64
	var created string
	if err := row.Scan(&o.ID, &customerID, &selectedMasterID, &preferredMasterID, &o.Title, &o.Desc, &o.Category, &o.District, &o.Address, &o.Budget, &o.When, &o.Status, &o.Views, &created, &o.Responses); err != nil {
		return Order{}, false
	}
	if customerID.Valid {
		o.CustomerID = int(customerID.Int64)
	}
	if selectedMasterID.Valid {
		o.SelectedMasterID = int(selectedMasterID.Int64)
	}
	if preferredMasterID.Valid {
		o.PreferredMasterID = int(preferredMasterID.Int64)
	}
	o.CreatedAt = relativeTime(created)
	o.Photos = orderPhotosFor(q, []int{o.ID})[o.ID]
	return o, true
}

func orderPhotosFor(q queryer, orderIDs []int) map[int][]OrderPhoto {
	result := make(map[int][]OrderPhoto, len(orderIDs))
	if len(orderIDs) == 0 {
		return result
	}
	placeholders := make([]string, 0, len(orderIDs))
	args := make([]any, 0, len(orderIDs))
	for _, id := range orderIDs {
		if id <= 0 {
			continue
		}
		placeholders = append(placeholders, "?")
		args = append(args, id)
	}
	if len(args) == 0 {
		return result
	}
	query := `SELECT id,order_id,content_hash,thumb_path,medium_path,full_path,width,height,blurhash,sort_order,created_at
		FROM order_photos WHERE order_id IN (` + strings.Join(placeholders, ",") + `)
		ORDER BY order_id,sort_order,id`
	rows, err := q.Query(sqlf(query), args...)
	if err != nil {
		return result
	}
	defer rows.Close()
	for rows.Next() {
		var item OrderPhoto
		var thumbPath, mediumPath, fullPath, created string
		if rows.Scan(&item.ID, &item.OrderID, &item.ContentHash, &thumbPath, &mediumPath, &fullPath, &item.Width, &item.Height, &item.Blurhash, &item.SortOrder, &created) == nil {
			item.ThumbURL = mediaURL(thumbPath)
			item.MediumURL = mediaURL(mediumPath)
			item.FullURL = mediaURL(fullPath)
			item.CreatedAt = relativeTime(created)
			result[item.OrderID] = append(result[item.OrderID], item)
		}
	}
	return result
}

func attachPhotosToOrders(orders []Order, photos map[int][]OrderPhoto) {
	for i := range orders {
		orders[i].Photos = photos[orders[i].ID]
	}
}

func mediaURL(path string) string {
	clean := strings.TrimLeft(filepath.ToSlash(strings.TrimSpace(path)), "/")
	if clean == "" {
		return ""
	}
	return "/media/" + clean
}

func (a *App) responsesForOrder(orderID int) []Response {
	rows, err := a.db.Query(sqlf(`SELECT r.id,r.order_id,r.master_id,m.name,m.rating,r.price,r.comment,r.created_at
		FROM responses r JOIN masters m ON m.id=r.master_id
		WHERE r.order_id=? ORDER BY r.created_at DESC`), orderID)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var items []Response
	for rows.Next() {
		var item Response
		var rating float64
		var created string
		if rows.Scan(&item.ID, &item.OrderID, &item.MasterID, &item.Master, &rating, &item.Price, &item.Comment, &created) == nil {
			item.Rating = strconv.FormatFloat(rating, 'f', 1, 64)
			item.CreatedAt = relativeTime(created)
			items = append(items, item)
		}
	}
	return items
}

func (a *App) messagesForChat(chatID int) []Message {
	rows, err := a.db.Query(sqlf(`SELECT id,chat_id,from_role,text,created_at FROM messages WHERE chat_id=? ORDER BY created_at,id`), chatID)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var items []Message
	for rows.Next() {
		var item Message
		var created string
		if rows.Scan(&item.ID, &item.ChatID, &item.FromRole, &item.Text, &created) == nil {
			item.CreatedAt = clock(created)
			items = append(items, item)
		}
	}
	return items
}

// messagesForChatSince supports polling: only messages newer than sinceID,
// so a client can merge them into what it already has instead of re-fetching
// (and re-rendering) the whole history on every poll tick.
func (a *App) messagesForChatSince(chatID, sinceID int) []Message {
	rows, err := a.db.Query(sqlf(`SELECT id,chat_id,from_role,text,created_at FROM messages WHERE chat_id=? AND id>? ORDER BY created_at,id`), chatID, sinceID)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var items []Message
	for rows.Next() {
		var item Message
		var created string
		if rows.Scan(&item.ID, &item.ChatID, &item.FromRole, &item.Text, &created) == nil {
			item.CreatedAt = clock(created)
			items = append(items, item)
		}
	}
	return items
}

func transactionsFrom(q queryer, profileID int) []Transaction {
	rows, err := q.Query(sqlf(`SELECT id,label,amount,created_at FROM transactions WHERE profile_id=? ORDER BY created_at DESC,id DESC LIMIT 20`), profileID)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var items []Transaction
	for rows.Next() {
		var item Transaction
		var created string
		if rows.Scan(&item.ID, &item.Label, &item.Amount, &created) == nil {
			item.CreatedAt = relativeTime(created)
			items = append(items, item)
		}
	}
	return items
}

func staticHandler(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/")
	if path == "" {
		path = "index.html"
	}
	if _, err := webFS.Open("web/" + path); err != nil {
		path = "index.html"
	}
	http.ServeFileFS(w, r, webFS, "web/"+path)
}

func decode(r *http.Request, v any) error {
	defer r.Body.Close()
	return json.NewDecoder(r.Body).Decode(v)
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	if err := json.NewEncoder(w).Encode(v); err != nil {
		writeError(w, http.StatusInternalServerError, "json_encode_failed", "json encode failed")
	}
}

func method(w http.ResponseWriter, r *http.Request, expected string) bool {
	if r.Method == expected {
		return true
	}
	writeError(w, http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed")
	return false
}

func badRequest(w http.ResponseWriter, err error) {
	writeError(w, http.StatusBadRequest, "bad_request", err.Error())
}

func serverError(w http.ResponseWriter, err error) {
	log.Println("server error:", err)
	writeError(w, http.StatusInternalServerError, "server_error", "server error")
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(ErrorResponse{
		Error: APIError{
			Code:    code,
			Message: message,
		},
	})
}

func boolInt(v bool) int {
	if v {
		return 1
	}
	return 0
}

func splitList(v string) []string {
	if strings.TrimSpace(v) == "" {
		return nil
	}
	return strings.Split(v, ",")
}

// joinList is splitList's inverse for writes: trims each item and drops
// empties before joining, so repeated saves (e.g. a master re-submitting
// their skills list) can't accumulate blank entries or stray commas.
func joinList(items []string) string {
	cleaned := make([]string, 0, len(items))
	for _, item := range items {
		if trimmed := strings.TrimSpace(item); trimmed != "" {
			cleaned = append(cleaned, trimmed)
		}
	}
	return strings.Join(cleaned, ",")
}

func relativeTime(value string) string {
	t, err := parseSQLiteTime(value)
	if err != nil {
		return value
	}
	d := time.Since(t)
	switch {
	case d < time.Minute:
		return "только что"
	case d < time.Hour:
		return strconv.Itoa(int(d.Minutes())) + " мин назад"
	case d < 24*time.Hour:
		return strconv.Itoa(int(d.Hours())) + " ч. назад"
	default:
		return strconv.Itoa(int(d.Hours()/24)) + " дн. назад"
	}
}

func clock(value string) string {
	t, err := parseSQLiteTime(value)
	if err != nil {
		return value
	}
	return t.Format("15:04")
}

func parseSQLiteTime(value string) (time.Time, error) {
	layouts := []string{
		"2006-01-02 15:04:05",
		time.RFC3339Nano,
	}
	for _, layout := range layouts {
		if t, err := time.ParseInLocation(layout, value, time.Local); err == nil {
			return t, nil
		}
	}
	return time.Time{}, errors.New("unknown time format")
}
