package main

import (
	"database/sql"
	"embed"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

//go:embed web/*
var webFS embed.FS

type App struct {
	db *sql.DB
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

type Order struct {
	ID        int    `json:"id"`
	Title     string `json:"title"`
	Desc      string `json:"desc"`
	Category  string `json:"category"`
	District  string `json:"district"`
	Address   string `json:"address"`
	Budget    string `json:"budget"`
	When      string `json:"when"`
	Status    string `json:"status"`
	Views     int    `json:"views"`
	Responses int    `json:"responses"`
	CreatedAt string `json:"createdAt"`
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
	WalletBalance  int    `json:"walletBalance"`
	IsVerified     bool   `json:"isVerified"`
	CompletedJobs  int    `json:"completedJobs"`
	PublishedCount int    `json:"publishedCount"`
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

func main() {
	db, err := openDB(env("DB_PATH", "usto.db"))
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	app := &App{db: db}
	mux := http.NewServeMux()
	mux.HandleFunc("/api/bootstrap", app.bootstrap)
	mux.HandleFunc("/api/orders", app.orders)
	mux.HandleFunc("/api/responses", app.responses)
	mux.HandleFunc("/api/messages", app.messages)
	mux.HandleFunc("/api/wallet/topup", app.topUpWallet)
	mux.HandleFunc("/api/verification", app.verifyMaster)
	mux.HandleFunc("/", staticHandler)

	addr := ":" + env("PORT", "8080")
	server := &http.Server{
		Addr:              addr,
		Handler:           logRequests(mux),
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("USTO started: http://localhost%s", addr)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
}

func openDB(path string) (*sql.DB, error) {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	if _, err := db.Exec(`PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL;`); err != nil {
		return nil, err
	}
	if err := migrate(db); err != nil {
		return nil, err
	}
	if err := seed(db); err != nil {
		return nil, err
	}
	return db, nil
}

func migrate(db *sql.DB) error {
	schema := []string{
		`CREATE TABLE IF NOT EXISTS profiles (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			role TEXT NOT NULL,
			name TEXT NOT NULL,
			phone TEXT NOT NULL,
			city TEXT NOT NULL,
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
		`CREATE TABLE IF NOT EXISTS masters (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
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
		`CREATE TABLE IF NOT EXISTS orders (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			title TEXT NOT NULL,
			desc TEXT NOT NULL,
			category TEXT NOT NULL,
			district TEXT NOT NULL,
			address TEXT NOT NULL,
			budget TEXT NOT NULL,
			when_label TEXT NOT NULL,
			status TEXT NOT NULL,
			views INTEGER NOT NULL DEFAULT 0,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
		);`,
		`CREATE TABLE IF NOT EXISTS responses (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
			master_id INTEGER NOT NULL REFERENCES masters(id),
			price INTEGER NOT NULL,
			comment TEXT NOT NULL,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
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
			label TEXT NOT NULL,
			amount INTEGER NOT NULL,
			created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
		);`,
	}
	for _, stmt := range schema {
		if _, err := db.Exec(stmt); err != nil {
			return err
		}
	}
	return nil
}

func seed(db *sql.DB) error {
	var count int
	if err := db.QueryRow(`SELECT COUNT(*) FROM categories`).Scan(&count); err != nil {
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
		_, err = tx.Exec(q, args...)
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

	masters := []Master{
		{Name: "Фаррух Турсунов", Service: "Сантехника", Rating: 4.9, Reviews: 127, Price: "от 120 TJS", Verified: true, Bio: "Занимаюсь сантехникой 8 лет. Работаю быстро, даю гарантию на все виды работ.", Skills: []string{"краны", "бойлеры", "трубы"}, Portfolio: []string{"🚿", "🚰", "🛁"}},
		{Name: "Рустам Исмоилов", Service: "Электрика", Rating: 4.8, Reviews: 89, Price: "от 90 TJS", Verified: true, Bio: "Монтаж розеток, щитков и освещения. Выезд по Душанбе в день обращения.", Skills: []string{"розетки", "щитки", "проводка"}, Portfolio: []string{"💡", "🔌", "⚡"}},
		{Name: "Диловар Рахимов", Service: "Ремонт", Rating: 4.7, Reviews: 64, Price: "от 150 TJS", Verified: false, Bio: "Косметический ремонт, плитка, покраска и мелкие работы по квартире.", Skills: []string{"плитка", "штукатурка", "покраска"}, Portfolio: []string{"🏠", "🧱", "🎨"}},
	}
	for _, m := range masters {
		mustExec(`INSERT INTO masters(name,service,rating,reviews,price,verified,bio,skills,portfolio) VALUES(?,?,?,?,?,?,?,?,?)`,
			m.Name, m.Service, m.Rating, m.Reviews, m.Price, boolInt(m.Verified), m.Bio, strings.Join(m.Skills, ","), strings.Join(m.Portfolio, ","))
	}

	mustExec(`INSERT INTO orders(title,desc,category,district,address,budget,when_label,status,views,created_at) VALUES
		('Починить кран на кухне','Течёт смеситель, нужна замена картриджа','Сантехника','Сино','ул. Рудаки 45','до 300 TJS','Сегодня','Активная',38,datetime('now','-2 hours')),
		('Установить розетки','Нужно установить 4 двойные розетки в новой квартире','Электрика','Фирдавси','Нусратулло Махсум 12','200-400 TJS','Завтра','Новая',8,datetime('now','-12 minutes')),
		('Собрать шкаф в спальне','Шкаф куплен, нужна аккуратная сборка','Мебель','Шохмансур','Айни 7','жду цену','На неделе','Выбор мастера',22,datetime('now','-1 day'));`)

	mustExec(`INSERT INTO responses(order_id,master_id,price,comment,created_at) VALUES
		(1,1,350,'Добрый день! Опыт 8 лет, гарантия 1 год. Могу приехать сегодня.',datetime('now','-90 minutes')),
		(1,2,280,'Могу сегодня после 14:00. Все инструменты при себе.',datetime('now','-70 minutes')),
		(1,3,320,'Качественно, гарантия 6 месяцев. Портфолио есть в профиле.',datetime('now','-45 minutes'));`)

	mustExec(`INSERT INTO messages(chat_id,from_role,text,created_at) VALUES
		(1,'master','Ассалому алейкум! Готов помочь с краном. Опыт 8 лет.',datetime('now','-35 minutes')),
		(1,'customer','Здравствуйте. Сможете приехать сегодня?',datetime('now','-32 minutes')),
		(1,'master','Да, после 17:00 буду свободен.',datetime('now','-30 minutes'));`)

	mustExec(`INSERT INTO transactions(label,amount,created_at) VALUES
		('Пополнение картой',100,datetime('now','-1 day')),
		('Отклик: ремонт крана',-4,datetime('now','-2 hours')),
		('Стартовый бонус',5,datetime('now','-3 days'));`)

	if err != nil {
		return err
	}
	return tx.Commit()
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
		Transactions: a.transactions(),
	})
}

func (a *App) orders(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, a.orders())
	case http.MethodPost:
		var req Order
		if err := decode(r, &req); err != nil {
			badRequest(w, err)
			return
		}
		if strings.TrimSpace(req.Title) == "" {
			badRequest(w, errors.New("title is required"))
			return
		}
		res, err := a.db.Exec(`INSERT INTO orders(title,desc,category,district,address,budget,when_label,status,views) VALUES(?,?,?,?,?,?,?,?,0)`,
			req.Title, req.Desc, req.Category, req.District, req.Address, req.Budget, req.When, "Активная")
		if err != nil {
			serverError(w, err)
			return
		}
		id, _ := res.LastInsertId()
		writeJSON(w, a.orderByID(int(id)))
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func (a *App) responses(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodPost) {
		return
	}
	var req struct {
		OrderID int    `json:"orderId"`
		Price   int    `json:"price"`
		Comment string `json:"comment"`
	}
	if err := decode(r, &req); err != nil {
		badRequest(w, err)
		return
	}
	if req.OrderID == 0 || req.Price == 0 || strings.TrimSpace(req.Comment) == "" {
		badRequest(w, errors.New("orderId, price and comment are required"))
		return
	}
	if _, err := a.db.Exec(`INSERT INTO responses(order_id,master_id,price,comment) VALUES(?,?,?,?)`, req.OrderID, 1, req.Price, req.Comment); err != nil {
		serverError(w, err)
		return
	}
	if _, err := a.db.Exec(`UPDATE profiles SET wallet_balance = wallet_balance - 4 WHERE role='master'`); err != nil {
		serverError(w, err)
		return
	}
	if _, err := a.db.Exec(`INSERT INTO transactions(label,amount) VALUES(?,?)`, "Отклик на заявку", -4); err != nil {
		serverError(w, err)
		return
	}
	writeJSON(w, a.snapshot())
}

func (a *App) messages(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, a.messagesForChat(1))
	case http.MethodPost:
		var req Message
		if err := decode(r, &req); err != nil {
			badRequest(w, err)
			return
		}
		if strings.TrimSpace(req.Text) == "" {
			badRequest(w, errors.New("message is empty"))
			return
		}
		role := req.FromRole
		if role == "" {
			role = "customer"
		}
		if _, err := a.db.Exec(`INSERT INTO messages(chat_id,from_role,text) VALUES(1,?,?)`, role, req.Text); err != nil {
			serverError(w, err)
			return
		}
		writeJSON(w, a.messagesForChat(1))
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func (a *App) topUpWallet(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodPost) {
		return
	}
	var req struct {
		Amount int `json:"amount"`
	}
	if err := decode(r, &req); err != nil {
		badRequest(w, err)
		return
	}
	if req.Amount <= 0 {
		badRequest(w, errors.New("amount must be positive"))
		return
	}
	if _, err := a.db.Exec(`UPDATE profiles SET wallet_balance = wallet_balance + ? WHERE role='master'`, req.Amount); err != nil {
		serverError(w, err)
		return
	}
	if _, err := a.db.Exec(`INSERT INTO transactions(label,amount) VALUES(?,?)`, "Пополнение кошелька", req.Amount); err != nil {
		serverError(w, err)
		return
	}
	writeJSON(w, a.snapshot())
}

func (a *App) verifyMaster(w http.ResponseWriter, r *http.Request) {
	if !method(w, r, http.MethodPost) {
		return
	}
	if _, err := a.db.Exec(`UPDATE profiles SET is_verified=1 WHERE role='master'`); err != nil {
		serverError(w, err)
		return
	}
	writeJSON(w, a.snapshot())
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
		Transactions: a.transactions(),
	}
}

func (a *App) profile(role string) (Profile, error) {
	var p Profile
	var verified int
	err := a.db.QueryRow(`SELECT id,role,name,phone,city,wallet_balance,is_verified,completed_jobs FROM profiles WHERE role=?`, role).
		Scan(&p.ID, &p.Role, &p.Name, &p.Phone, &p.City, &p.WalletBalance, &verified, &p.CompletedJobs)
	if err != nil {
		return p, err
	}
	p.IsVerified = verified == 1
	if role == "customer" {
		_ = a.db.QueryRow(`SELECT COUNT(*) FROM orders`).Scan(&p.PublishedCount)
	}
	return p, nil
}

func (a *App) categories() []Category {
	rows, err := a.db.Query(`SELECT id,name,icon,theme FROM categories ORDER BY id`)
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
	rows, err := a.db.Query(`SELECT id,name,service,rating,reviews,price,verified,bio,skills,portfolio FROM masters ORDER BY rating DESC`)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var items []Master
	for rows.Next() {
		var m Master
		var verified int
		var skills, portfolio string
		if rows.Scan(&m.ID, &m.Name, &m.Service, &m.Rating, &m.Reviews, &m.Price, &verified, &m.Bio, &skills, &portfolio) == nil {
			m.Verified = verified == 1
			m.Skills = splitList(skills)
			m.Portfolio = splitList(portfolio)
			items = append(items, m)
		}
	}
	return items
}

func (a *App) orders() []Order {
	rows, err := a.db.Query(`SELECT o.id,o.title,o.desc,o.category,o.district,o.address,o.budget,o.when_label,o.status,o.views,o.created_at,COUNT(r.id)
		FROM orders o LEFT JOIN responses r ON r.order_id=o.id
		GROUP BY o.id ORDER BY o.created_at DESC`)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var items []Order
	for rows.Next() {
		var o Order
		var created string
		if rows.Scan(&o.ID, &o.Title, &o.Desc, &o.Category, &o.District, &o.Address, &o.Budget, &o.When, &o.Status, &o.Views, &created, &o.Responses) == nil {
			o.CreatedAt = relativeTime(created)
			items = append(items, o)
		}
	}
	return items
}

func (a *App) orderByID(id int) Order {
	for _, order := range a.orders() {
		if order.ID == id {
			return order
		}
	}
	return Order{}
}

func (a *App) responsesForOrder(orderID int) []Response {
	rows, err := a.db.Query(`SELECT r.id,r.order_id,r.master_id,m.name,printf('%.1f',m.rating),r.price,r.comment,r.created_at
		FROM responses r JOIN masters m ON m.id=r.master_id
		WHERE r.order_id=? ORDER BY r.created_at DESC`, orderID)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var items []Response
	for rows.Next() {
		var item Response
		var created string
		if rows.Scan(&item.ID, &item.OrderID, &item.MasterID, &item.Master, &item.Rating, &item.Price, &item.Comment, &created) == nil {
			item.CreatedAt = relativeTime(created)
			items = append(items, item)
		}
	}
	return items
}

func (a *App) messagesForChat(chatID int) []Message {
	rows, err := a.db.Query(`SELECT id,chat_id,from_role,text,created_at FROM messages WHERE chat_id=? ORDER BY created_at,id`, chatID)
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

func (a *App) transactions() []Transaction {
	rows, err := a.db.Query(`SELECT id,label,amount,created_at FROM transactions ORDER BY created_at DESC,id DESC LIMIT 20`)
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
		http.Error(w, "json encode failed", http.StatusInternalServerError)
	}
}

func method(w http.ResponseWriter, r *http.Request, expected string) bool {
	if r.Method == expected {
		return true
	}
	http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	return false
}

func badRequest(w http.ResponseWriter, err error) {
	http.Error(w, err.Error(), http.StatusBadRequest)
}

func serverError(w http.ResponseWriter, err error) {
	log.Println("server error:", err)
	http.Error(w, "server error", http.StatusInternalServerError)
}

func logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		log.Printf("%s %s", r.Method, r.URL.Path)
		next.ServeHTTP(w, r)
	})
}

func env(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
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
