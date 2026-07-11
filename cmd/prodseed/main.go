package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	_ "github.com/lib/pq"
)

type profileSeed struct {
	Role          string
	Name          string
	Phone         string
	City          string
	District      string
	AvatarURL     string
	WalletBalance int
	IsVerified    bool
	CompletedJobs int
}

type categorySeed struct {
	Name  string
	Icon  string
	Thema string
}

type masterSeed struct {
	Name      string
	Service   string
	Rating    float64
	Reviews   int
	Price     string
	Verified  bool
	Bio       string
	Skills    []string
	Portfolio []string
}

type orderSeed struct {
	Title            string
	Desc             string
	Category         string
	District         string
	Address          string
	Budget           string
	WhenLabel        string
	Status           string
	Views            int
	CreatedAt        time.Time
	SelectedMasterIx int
}

type responseSeed struct {
	OrderIx    int
	MasterIx   int
	Price      int
	Comment    string
	CreatedAt  time.Time
	CreateChat bool
	Messages   []messageSeed
}

type messageSeed struct {
	FromRole  string
	Text      string
	CreatedAt time.Time
}

type transactionSeed struct {
	Label     string
	Amount    int
	CreatedAt time.Time
}

func main() {
	apply := flag.Bool("apply", false, "truncate and load production starter data")
	printJSON := flag.Bool("print-json", false, "print a short summary as JSON")
	flag.Parse()

	databaseURL := strings.TrimSpace(os.Getenv("DATABASE_URL"))
	if databaseURL == "" {
		log.Fatal("DATABASE_URL is required")
	}

	db, err := sql.Open("postgres", databaseURL)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		log.Fatal(err)
	}

	if *apply {
		if err := applySeed(ctx, db); err != nil {
			log.Fatal(err)
		}
	}

	summary, err := summarize(ctx, db)
	if err != nil {
		log.Fatal(err)
	}
	if *printJSON {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		if err := enc.Encode(summary); err != nil {
			log.Fatal(err)
		}
		return
	}

	fmt.Printf("profiles=%d users=%d categories=%d masters=%d orders=%d responses=%d chats=%d messages=%d transactions=%d\n",
		summary.Profiles, summary.Users, summary.Categories, summary.Masters, summary.Orders,
		summary.Responses, summary.Chats, summary.Messages, summary.Transactions)
}

type dbSummary struct {
	Profiles     int `json:"profiles"`
	Users        int `json:"users"`
	Categories   int `json:"categories"`
	Masters      int `json:"masters"`
	Orders       int `json:"orders"`
	Responses    int `json:"responses"`
	Chats        int `json:"chats"`
	Messages     int `json:"messages"`
	Transactions int `json:"transactions"`
}

func summarize(ctx context.Context, db *sql.DB) (dbSummary, error) {
	queries := []struct {
		field *int
		sql   string
	}{
		{sql: `SELECT COUNT(*) FROM profiles`},
		{sql: `SELECT COUNT(*) FROM users`},
		{sql: `SELECT COUNT(*) FROM categories`},
		{sql: `SELECT COUNT(*) FROM masters`},
		{sql: `SELECT COUNT(*) FROM orders`},
		{sql: `SELECT COUNT(*) FROM responses`},
		{sql: `SELECT COUNT(*) FROM chats`},
		{sql: `SELECT COUNT(*) FROM messages`},
		{sql: `SELECT COUNT(*) FROM transactions`},
	}
	var out dbSummary
	queries[0].field = &out.Profiles
	queries[1].field = &out.Users
	queries[2].field = &out.Categories
	queries[3].field = &out.Masters
	queries[4].field = &out.Orders
	queries[5].field = &out.Responses
	queries[6].field = &out.Chats
	queries[7].field = &out.Messages
	queries[8].field = &out.Transactions
	for _, item := range queries {
		if err := db.QueryRowContext(ctx, item.sql).Scan(item.field); err != nil {
			return out, err
		}
	}
	return out, nil
}

func applySeed(ctx context.Context, db *sql.DB) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	if err := ensureSchema(ctx, tx); err != nil {
		return err
	}

	if _, err := tx.ExecContext(ctx, `
		TRUNCATE TABLE
			idempotency_keys,
			verification_documents,
			messages,
			chats,
			responses,
			orders,
			masters,
			transactions,
			users,
			categories,
			profiles
		RESTART IDENTITY CASCADE
	`); err != nil {
		return err
	}

	customerProfileID, err := insertProfile(ctx, tx, profileSeed{
		Role:          "customer",
		Name:          "Алишер Назаров",
		Phone:         "+992 900 11 22 33",
		City:          "Душанбе",
		District:      "Исмоили Сомони",
		WalletBalance: 0,
		IsVerified:    true,
	})
	if err != nil {
		return err
	}
	masterProfileID, err := insertProfile(ctx, tx, profileSeed{
		Role:          "master",
		Name:          "Умар Саидов",
		Phone:         "+992 918 44 55 66",
		City:          "Душанбе",
		District:      "Сино",
		WalletBalance: 240,
		IsVerified:    true,
		CompletedJobs: 86,
	})
	if err != nil {
		return err
	}

	if err := insertUser(ctx, tx, customerProfileID, "+992 900 11 22 33", "customer"); err != nil {
		return err
	}
	if err := insertUser(ctx, tx, masterProfileID, "+992 918 44 55 66", "master"); err != nil {
		return err
	}

	for _, category := range productionCategories() {
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO categories(name, icon, theme)
			VALUES($1, $2, $3)
		`, category.Name, category.Icon, category.Thema); err != nil {
			return err
		}
	}

	masterIDs := make([]int, 0, len(productionMasters()))
	for _, master := range productionMasters() {
		var id int
		err := tx.QueryRowContext(ctx, `
			INSERT INTO masters(name, service, rating, reviews, price, verified, bio, skills, portfolio)
			VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9)
			RETURNING id
		`, master.Name, master.Service, master.Rating, master.Reviews, master.Price, boolToInt(master.Verified),
			master.Bio, strings.Join(master.Skills, ","), strings.Join(master.Portfolio, ",")).Scan(&id)
		if err != nil {
			return err
		}
		masterIDs = append(masterIDs, id)
	}

	orderIDs := make([]int, 0, len(productionOrders()))
	for _, order := range productionOrders() {
		selectedMasterID := any(nil)
		if order.SelectedMasterIx > 0 {
			if order.SelectedMasterIx > len(masterIDs) {
				return fmt.Errorf("selected master index out of range for order %q", order.Title)
			}
			selectedMasterID = masterIDs[order.SelectedMasterIx-1]
		}

		var id int
		err := tx.QueryRowContext(ctx, `
			INSERT INTO orders(selected_master_id, preferred_master_id, title, "desc", category, district, address, budget, when_label, status, views, created_at)
			VALUES($1, NULL, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
			RETURNING id
		`, selectedMasterID, order.Title, order.Desc, order.Category, order.District, order.Address,
			order.Budget, order.WhenLabel, order.Status, order.Views, order.CreatedAt).Scan(&id)
		if err != nil {
			return err
		}
		orderIDs = append(orderIDs, id)
	}

	for _, response := range productionResponses() {
		if response.OrderIx > len(orderIDs) || response.MasterIx > len(masterIDs) {
			return errors.New("response seed references missing order or master")
		}
		var responseID int
		err := tx.QueryRowContext(ctx, `
			INSERT INTO responses(order_id, master_id, price, comment, created_at)
			VALUES($1, $2, $3, $4, $5)
			RETURNING id
		`, orderIDs[response.OrderIx-1], masterIDs[response.MasterIx-1], response.Price, response.Comment, response.CreatedAt).Scan(&responseID)
		if err != nil {
			return err
		}

		if !response.CreateChat {
			continue
		}
		var chatID int
		err = tx.QueryRowContext(ctx, `
			INSERT INTO chats(order_id, master_id, created_at)
			VALUES($1, $2, $3)
			RETURNING id
		`, orderIDs[response.OrderIx-1], masterIDs[response.MasterIx-1], response.CreatedAt).Scan(&chatID)
		if err != nil {
			return err
		}
		for _, message := range response.Messages {
			if _, err := tx.ExecContext(ctx, `
				INSERT INTO messages(chat_id, from_role, text, created_at)
				VALUES($1, $2, $3, $4)
			`, chatID, message.FromRole, message.Text, message.CreatedAt); err != nil {
				return err
			}
		}
	}

	for _, transaction := range productionTransactions() {
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO transactions(label, amount, created_at)
			VALUES($1, $2, $3)
		`, transaction.Label, transaction.Amount, transaction.CreatedAt); err != nil {
			return err
		}
	}

	if _, err := tx.ExecContext(ctx, `
		INSERT INTO verification_documents(master_profile_id, document_type, file_url, status, created_at, reviewed_at)
		VALUES($1, $2, $3, $4, $5, $6)
	`, masterProfileID, "Паспорт", "https://usto-production.up.railway.app/static/docs/master-passport.pdf",
		"approved", time.Now().Add(-14*24*time.Hour), time.Now().Add(-13*24*time.Hour)); err != nil {
		return err
	}

	reviews := []struct {
		masterIx   int
		authorName string
		rating     int
		text       string
		createdAt  time.Time
	}{
		{0, "Саида Н.", 5, "Приехал вовремя, быстро устранил протечку и аккуратно всё убрал после работы.", time.Now().Add(-72 * time.Hour)},
		{0, "Мухаммад Р.", 5, "Хорошо объяснил причину поломки и заменил смеситель без лишних расходов.", time.Now().Add(-120 * time.Hour)},
		{1, "Зебо К.", 5, "Переустановил автомат и проверил все линии. Работает стабильно.", time.Now().Add(-96 * time.Hour)},
		{2, "Фирдавс А.", 4, "Ремонт сделали аккуратно, сроки почти совпали с договорённостью.", time.Now().Add(-168 * time.Hour)},
		{3, "Манижа С.", 5, "Шкаф и кровать собрал чисто и быстро, ничего не поцарапал.", time.Now().Add(-48 * time.Hour)},
	}
	for _, review := range reviews {
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO master_reviews(master_id, author_name, rating, text, created_at)
			VALUES($1, $2, $3, $4, $5)
		`, masterIDs[review.masterIx], review.authorName, review.rating, review.text, review.createdAt); err != nil {
			return err
		}
	}

	return tx.Commit()
}

func ensureSchema(ctx context.Context, tx *sql.Tx) error {
	statements := []string{
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
		)`,
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
		)`,
		`CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone_role ON users(phone_norm, role)`,
		`CREATE TABLE IF NOT EXISTS categories (
			id BIGSERIAL PRIMARY KEY,
			name TEXT NOT NULL,
			icon TEXT NOT NULL,
			theme TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS masters (
			id BIGSERIAL PRIMARY KEY,
			name TEXT NOT NULL,
			service TEXT NOT NULL,
			rating DOUBLE PRECISION NOT NULL,
			reviews INTEGER NOT NULL,
			price TEXT NOT NULL,
			verified INTEGER NOT NULL,
			bio TEXT NOT NULL,
			skills TEXT NOT NULL,
			portfolio TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS orders (
			id BIGSERIAL PRIMARY KEY,
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
		)`,
		`CREATE INDEX IF NOT EXISTS idx_orders_feed ON orders(district, created_at DESC)`,
		`CREATE TABLE IF NOT EXISTS responses (
			id BIGSERIAL PRIMARY KEY,
			order_id BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
			master_id BIGINT NOT NULL REFERENCES masters(id),
			price INTEGER NOT NULL,
			comment TEXT NOT NULL,
			created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS chats (
			id BIGSERIAL PRIMARY KEY,
			order_id BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
			master_id BIGINT NOT NULL REFERENCES masters(id),
			created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
			UNIQUE(order_id, master_id)
		)`,
		`CREATE TABLE IF NOT EXISTS messages (
			id BIGSERIAL PRIMARY KEY,
			chat_id BIGINT NOT NULL DEFAULT 1,
			from_role TEXT NOT NULL,
			text TEXT NOT NULL,
			created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS transactions (
			id BIGSERIAL PRIMARY KEY,
			label TEXT NOT NULL,
			amount INTEGER NOT NULL,
			created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS idempotency_keys (
			key TEXT PRIMARY KEY,
			response_body TEXT NOT NULL,
			status_code INTEGER NOT NULL,
			created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
		)`,
		`CREATE TABLE IF NOT EXISTS verification_documents (
			id BIGSERIAL PRIMARY KEY,
			master_profile_id BIGINT NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
			document_type TEXT NOT NULL,
			file_url TEXT NOT NULL,
			status TEXT NOT NULL DEFAULT 'pending',
			rejection_reason TEXT NOT NULL DEFAULT '',
			created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
			reviewed_at TIMESTAMPTZ
		)`,
		`CREATE TABLE IF NOT EXISTS master_reviews (
			id BIGSERIAL PRIMARY KEY,
			master_id BIGINT NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
			author_name TEXT NOT NULL,
			rating INTEGER NOT NULL,
			text TEXT NOT NULL,
			created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
		)`,
	}
	for _, statement := range statements {
		if _, err := tx.ExecContext(ctx, statement); err != nil {
			return err
		}
	}
	return nil
}

func insertProfile(ctx context.Context, tx *sql.Tx, profile profileSeed) (int, error) {
	var id int
	err := tx.QueryRowContext(ctx, `
		INSERT INTO profiles(role, name, phone, city, district, avatar_url, wallet_balance, is_verified, completed_jobs)
		VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9)
		RETURNING id
	`, profile.Role, profile.Name, profile.Phone, profile.City, profile.District, profile.AvatarURL,
		profile.WalletBalance, boolToInt(profile.IsVerified), profile.CompletedJobs).Scan(&id)
	return id, err
}

func insertUser(ctx context.Context, tx *sql.Tx, profileID int, phone, role string) error {
	_, err := tx.ExecContext(ctx, `
		INSERT INTO users(phone, phone_norm, role, status, profile_id, created_at, updated_at, last_login_at)
		VALUES($1, $2, $3, 'active', $4, NOW(), NOW(), NOW())
	`, phone, normalizePhone(phone), role, profileID)
	return err
}

func normalizePhone(phone string) string {
	replacer := strings.NewReplacer(" ", "", "-", "", "(", "", ")", "", "+", "")
	return replacer.Replace(strings.TrimSpace(phone))
}

func boolToInt(value bool) int {
	if value {
		return 1
	}
	return 0
}

func productionCategories() []categorySeed {
	return []categorySeed{
		{Name: "Сантехника", Icon: "🔧", Thema: "blue"},
		{Name: "Электрика", Icon: "⚡", Thema: "yellow"},
		{Name: "Ремонт квартир", Icon: "🛠️", Thema: "pink"},
		{Name: "Сборка мебели", Icon: "🪑", Thema: "green"},
		{Name: "Уборка", Icon: "🧹", Thema: "indigo"},
		{Name: "Кондиционеры", Icon: "❄️", Thema: "cyan"},
		{Name: "Бытовая техника", Icon: "🧰", Thema: "gray"},
		{Name: "Малярные работы", Icon: "🎨", Thema: "orange"},
	}
}

func productionMasters() []masterSeed {
	return []masterSeed{
		{
			Name:      "Умар Саидов",
			Service:   "Сантехника",
			Rating:    4.9,
			Reviews:   184,
			Price:     "от 120 TJS",
			Verified:  true,
			Bio:       "Замена смесителей, бойлеров, фильтров и разводка труб. Работаю по Душанбе без задержек, даю гарантию на выполненные работы.",
			Skills:    []string{"смесители", "бойлеры", "разводка труб"},
			Portfolio: []string{"Санузел", "Кухня", "Замена узлов"},
		},
		{
			Name:      "Шерзод Каримов",
			Service:   "Электрика",
			Rating:    4.8,
			Reviews:   139,
			Price:     "от 90 TJS",
			Verified:  true,
			Bio:       "Монтаж розеток, щитов, освещения и диагностика коротких замыканий. Приезжаю со своим инструментом.",
			Skills:    []string{"розетки", "щитки", "освещение"},
			Portfolio: []string{"Квартира", "Офис", "Щитовая"},
		},
		{
			Name:      "Фируз Мухторов",
			Service:   "Ремонт квартир",
			Rating:    4.7,
			Reviews:   98,
			Price:     "от 180 TJS",
			Verified:  true,
			Bio:       "Косметический ремонт, шпаклёвка, укладка плитки и чистовая отделка под ключ.",
			Skills:    []string{"плитка", "шпаклёвка", "отделка"},
			Portfolio: []string{"Студия", "Ванная", "Кухня"},
		},
		{
			Name:      "Далер Икромов",
			Service:   "Сборка мебели",
			Rating:    4.9,
			Reviews:   76,
			Price:     "от 110 TJS",
			Verified:  true,
			Bio:       "Собираю шкафы, кухни, кровати и офисную мебель. Аккуратно работаю с новой фурнитурой и фасадами.",
			Skills:    []string{"шкафы", "кухни", "кровати"},
			Portfolio: []string{"Шкаф", "Кухня", "Детская"},
		},
		{
			Name:      "Саидмурод Хамидов",
			Service:   "Уборка",
			Rating:    4.8,
			Reviews:   63,
			Price:     "от 80 TJS",
			Verified:  true,
			Bio:       "Генеральная уборка квартир и офисов после ремонта, уборка кухни и санузлов в день обращения.",
			Skills:    []string{"генеральная уборка", "после ремонта", "офисы"},
			Portfolio: []string{"Квартира", "Офис", "После ремонта"},
		},
		{
			Name:      "Комрон Юсуфов",
			Service:   "Кондиционеры",
			Rating:    4.8,
			Reviews:   91,
			Price:     "от 150 TJS",
			Verified:  true,
			Bio:       "Установка, чистка и заправка кондиционеров. Диагностика шума и слабого охлаждения.",
			Skills:    []string{"монтаж", "чистка", "заправка"},
			Portfolio: []string{"Сплит-система", "Офис", "Сервис"},
		},
		{
			Name:      "Рустам Набиев",
			Service:   "Бытовая техника",
			Rating:    4.6,
			Reviews:   57,
			Price:     "от 130 TJS",
			Verified:  true,
			Bio:       "Ремонт стиральных машин, духовок и посудомоек. Быстрая диагностика, выезд по районам города.",
			Skills:    []string{"стиральные машины", "духовки", "посудомойки"},
			Portfolio: []string{"Сервис", "Диагностика", "Запчасти"},
		},
		{
			Name:      "Бехруз Сафаров",
			Service:   "Малярные работы",
			Rating:    4.7,
			Reviews:   70,
			Price:     "от 140 TJS",
			Verified:  false,
			Bio:       "Покраска стен и потолков, подготовка поверхностей, локальное восстановление после протечек.",
			Skills:    []string{"покраска стен", "потолки", "подготовка"},
			Portfolio: []string{"Спальня", "Гостиная", "Потолок"},
		},
	}
}

func productionOrders() []orderSeed {
	now := time.Now()
	return []orderSeed{
		{
			Title:            "Починить протечку под кухонной мойкой",
			Desc:             "После включения воды течёт соединение под мойкой. Нужна диагностика и замена гибкой подводки, если потребуется.",
			Category:         "Сантехника",
			District:         "Исмоили Сомони",
			Address:          "ул. Рудаки, 118",
			Budget:           "до 250 TJS",
			WhenLabel:        "Сегодня до 20:00",
			Status:           "Активная",
			Views:            42,
			CreatedAt:        now.Add(-2 * time.Hour),
			SelectedMasterIx: 0,
		},
		{
			Title:            "Установить 5 новых розеток в гостиной",
			Desc:             "Нужно аккуратно вывести точки и установить рамки. Дом жилой, важно без пыли и с уборкой после работы.",
			Category:         "Электрика",
			District:         "Сино",
			Address:          "ул. Айни, 42",
			Budget:           "300-450 TJS",
			WhenLabel:        "Завтра утром",
			Status:           "Новая",
			Views:            18,
			CreatedAt:        now.Add(-95 * time.Minute),
			SelectedMasterIx: 0,
		},
		{
			Title:            "Собрать шкаф-купе после доставки",
			Desc:             "Шкаф 2.4 м, новая упаковка. Нужна аккуратная сборка и выравнивание дверей.",
			Category:         "Сборка мебели",
			District:         "Фирдавси",
			Address:          "проспект Хофизи Шерози, 15",
			Budget:           "жду предложения",
			WhenLabel:        "На этой неделе",
			Status:           "Выбор мастера",
			Views:            27,
			CreatedAt:        now.Add(-6 * time.Hour),
			SelectedMasterIx: 4,
		},
		{
			Title:            "Генеральная уборка квартиры 68 м2",
			Desc:             "Нужно убрать две комнаты, кухню и санузел после арендаторов. Средства можно привезти свои.",
			Category:         "Уборка",
			District:         "Шохмансур",
			Address:          "ул. Мирзо Турсунзаде, 9",
			Budget:           "до 350 TJS",
			WhenLabel:        "В субботу",
			Status:           "Активная",
			Views:            16,
			CreatedAt:        now.Add(-11 * time.Hour),
			SelectedMasterIx: 0,
		},
		{
			Title:            "Почистить кондиционер и проверить охлаждение",
			Desc:             "Сплит-система стала хуже охлаждать. Нужна чистка внутреннего блока и проверка давления.",
			Category:         "Кондиционеры",
			District:         "Сино",
			Address:          "ул. Бухоро, 27",
			Budget:           "до 220 TJS",
			WhenLabel:        "Сегодня после 18:00",
			Status:           "Активная",
			Views:            31,
			CreatedAt:        now.Add(-14 * time.Hour),
			SelectedMasterIx: 6,
		},
		{
			Title:            "Подкрасить потолок после небольшой протечки",
			Desc:             "Пятно уже высохло, нужна локальная подготовка и аккуратная покраска без отличия по цвету.",
			Category:         "Малярные работы",
			District:         "Исмоили Сомони",
			Address:          "ул. Исмоили Сомони, 21",
			Budget:           "100-180 TJS",
			WhenLabel:        "В течение 2 дней",
			Status:           "Новая",
			Views:            12,
			CreatedAt:        now.Add(-20 * time.Hour),
			SelectedMasterIx: 0,
		},
		{
			Title:            "Диагностика стиральной машины Samsung",
			Desc:             "Машина набирает воду, но не запускает стирку. Нужна первичная диагностика на месте.",
			Category:         "Бытовая техника",
			District:         "Фирдавси",
			Address:          "мкр 82, дом 4",
			Budget:           "до 150 TJS",
			WhenLabel:        "Сегодня",
			Status:           "Активная",
			Views:            23,
			CreatedAt:        now.Add(-26 * time.Hour),
			SelectedMasterIx: 7,
		},
		{
			Title:            "Уложить плитку на кухонный фартук",
			Desc:             "Площадь около 4 м2, плитка уже куплена. Нужна аккуратная укладка и затирка.",
			Category:         "Ремонт квартир",
			District:         "Шохмансур",
			Address:          "ул. Н. Карабаева, 33",
			Budget:           "от 500 TJS",
			WhenLabel:        "На следующей неделе",
			Status:           "Завершена",
			Views:            64,
			CreatedAt:        now.Add(-72 * time.Hour),
			SelectedMasterIx: 3,
		},
	}
}

func productionResponses() []responseSeed {
	now := time.Now()
	return []responseSeed{
		{
			OrderIx:    1,
			MasterIx:   1,
			Price:      220,
			Comment:    "Могу подъехать сегодня после 16:00, сразу возьму расходники. Если проблема только в подводке, уложимся в этот бюджет.",
			CreatedAt:  now.Add(-90 * time.Minute),
			CreateChat: true,
			Messages: []messageSeed{
				{FromRole: "master", Text: "Здравствуйте. Посмотрел описание, похоже на замену подводки или сифона.", CreatedAt: now.Add(-85 * time.Minute)},
				{FromRole: "customer", Text: "Да, течёт именно под мойкой. Сможете приехать сегодня?", CreatedAt: now.Add(-82 * time.Minute)},
				{FromRole: "master", Text: "Да, буду в вашем районе после 16:00. Перед выездом напишу ещё раз.", CreatedAt: now.Add(-78 * time.Minute)},
			},
		},
		{
			OrderIx:    1,
			MasterIx:   2,
			Price:      260,
			Comment:    "Если нужен срочный выезд до обеда, смогу перестроить график. Гарантия на работу 30 дней.",
			CreatedAt:  now.Add(-70 * time.Minute),
			CreateChat: false,
		},
		{
			OrderIx:    2,
			MasterIx:   2,
			Price:      380,
			Comment:    "Сделаю монтаж аккуратно по уровню, с проверкой нагрузки и уборкой после сверления.",
			CreatedAt:  now.Add(-40 * time.Minute),
			CreateChat: true,
			Messages: []messageSeed{
				{FromRole: "customer", Text: "Важно сделать без пыли, в квартире уже живём.", CreatedAt: now.Add(-37 * time.Minute)},
				{FromRole: "master", Text: "Понял, использую пылесборник и накрытие. После монтажа всё уберу.", CreatedAt: now.Add(-34 * time.Minute)},
			},
		},
		{
			OrderIx:    3,
			MasterIx:   4,
			Price:      180,
			Comment:    "Есть опыт со шкафами-купе и фасадами. Могу приехать с напарником, если коробки тяжёлые.",
			CreatedAt:  now.Add(-5 * time.Hour),
			CreateChat: false,
		},
		{
			OrderIx:    4,
			MasterIx:   5,
			Price:      320,
			Comment:    "Генеральная уборка займёт около 5 часов. Привезём свои средства и пароочиститель для кухни.",
			CreatedAt:  now.Add(-9 * time.Hour),
			CreateChat: false,
		},
		{
			OrderIx:    5,
			MasterIx:   6,
			Price:      200,
			Comment:    "Сделаю чистку и проверю давление хладагента. Если понадобится дозаправка, согласуем отдельно.",
			CreatedAt:  now.Add(-12 * time.Hour),
			CreateChat: false,
		},
		{
			OrderIx:    7,
			MasterIx:   7,
			Price:      140,
			Comment:    "Начну с диагностики платы и замка люка. Частые причины именно там, постараюсь решить за один визит.",
			CreatedAt:  now.Add(-23 * time.Hour),
			CreateChat: false,
		},
		{
			OrderIx:    8,
			MasterIx:   3,
			Price:      650,
			Comment:    "Могу показать примеры кухонных фартуков и помочь с раскладкой плитки перед стартом работ.",
			CreatedAt:  now.Add(-70 * time.Hour),
			CreateChat: false,
		},
	}
}

func productionTransactions() []transactionSeed {
	now := time.Now()
	return []transactionSeed{
		{Label: "Пополнение баланса", Amount: 250, CreatedAt: now.Add(-10 * 24 * time.Hour)},
		{Label: "Отклик на заявку: протечка под мойкой", Amount: -4, CreatedAt: now.Add(-90 * time.Minute)},
		{Label: "Отклик на заявку: розетки в гостиной", Amount: -4, CreatedAt: now.Add(-40 * time.Minute)},
		{Label: "Отклик на заявку: уборка квартиры", Amount: -4, CreatedAt: now.Add(-9 * time.Hour)},
		{Label: "Бонус за подтверждение профиля", Amount: 2, CreatedAt: now.Add(-14 * 24 * time.Hour)},
	}
}
