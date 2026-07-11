const app = document.querySelector("#app");

const state = {
  bootstrap: null,
  reviews: [],
  audience: "customer",
  activeCategory: "all",
};

init();

async function init() {
  renderLoading();
  try {
    const bootstrap = await fetchJson("/api/bootstrap");
    state.bootstrap = bootstrap;
    state.reviews = await loadReviews(bootstrap.masters || []);
    render();
    bind();
  } catch (error) {
    renderError(error);
  }
}

async function loadReviews(masters) {
  const topMasters = masters.slice(0, 3);
  const reviewSets = await Promise.all(
    topMasters.map(async (master) => {
      try {
        const payload = await fetchJson(`/api/masters/${master.id}/reviews`);
        return (payload.reviews || []).map((review) => ({
          ...review,
          masterName: master.name,
          service: master.service,
        }));
      } catch (_) {
        return [];
      }
    }),
  );
  return reviewSets.flat().slice(0, 3);
}

async function fetchJson(url) {
  const response = await fetch(url, {
    headers: { Accept: "application/json" },
  });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`);
  }
  return response.json();
}

function renderLoading() {
  app.innerHTML = `
    <main class="loading">
      <section class="loading-card">
        <img src="/logo-assets/app-icon-round-512.png" alt="USTO">
        <h1>Загружаем USTO</h1>
        <p>Собираем категории, мастеров и актуальные заявки.</p>
      </section>
    </main>
  `;
}

function renderError(error) {
  app.innerHTML = `
    <main class="error">
      <section class="error-card">
        <img src="/logo-assets/app-icon-round-512.png" alt="USTO">
        <h1>Не удалось открыть сайт</h1>
        <p>${escapeHtml(error.message || "Попробуйте обновить страницу чуть позже.")}</p>
        <button class="btn" id="retryBtn">Обновить</button>
      </section>
    </main>
  `;
  document.querySelector("#retryBtn")?.addEventListener("click", init);
}

function render() {
  const customer = state.bootstrap.customer || {};
  const masterProfile = state.bootstrap.master || {};
  const categories = (state.bootstrap.categories || []).slice(0, 8);
  const masters = filterMasters((state.bootstrap.masters || []).slice(0, 6));
  const orders = filterOrders((state.bootstrap.orders || []).slice(0, 6));

  app.innerHTML = `
    ${header()}
    <main>
      <section class="hero">
        <div class="page hero-grid">
          <article class="hero-copy">
            <span class="eyebrow">Сервис мастеров в Душанбе</span>
            <h1>Найти проверенного мастера и договориться без лишней суеты</h1>
            <p>
              USTO помогает быстро опубликовать заявку, выбрать специалиста по рейтингу и цене,
              а потом продолжить общение в чате. Всё выглядит как нормальный веб-сервис, а не как растянутое мобильное приложение.
            </p>
            <div class="hero-actions">
              <a class="btn-secondary" href="#masters">Смотреть мастеров</a>
              <a class="btn-ghost" href="#orders">Посмотреть заявки</a>
            </div>
            <div class="hero-note">
              <span>${countText(categories.length, "категория", "категории", "категорий")}</span>
              <span>${countText((state.bootstrap.masters || []).length, "мастер", "мастера", "мастеров")}</span>
              <span>Чат и выбор исполнителя внутри сервиса</span>
            </div>
          </article>
          <aside class="hero-panel">
            <div class="hero-panel-head">
              <div>
                <h2>Сейчас в работе</h2>
                <p>Живые данные проекта: заявки, мастера и состояние клиентского потока.</p>
              </div>
              <span class="chip">Онлайн</span>
            </div>
            <div class="hero-stats">
              ${statCard((state.bootstrap.orders || []).length, "Заявки", "#0f172a")}
              ${statCard((state.bootstrap.masters || []).filter((item) => item.verified).length, "Проверены", "#059669")}
              ${statCard(averageRating(state.bootstrap.masters || []), "Средний рейтинг", "#2356df")}
            </div>
            <article class="live-order">
              ${featuredOrder(orders[0])}
            </article>
          </aside>
        </div>
      </section>

      <section class="section" id="categories">
        <div class="page">
          <div class="section-head">
            <div>
              <h2>Категории услуг</h2>
              <p>Основные направления, с которыми пользователь заходит в сервис. Сетка остаётся аккуратной и на телефоне, и на широком экране.</p>
            </div>
            <a class="ghost-link" href="#orders">Перейти к заявкам</a>
          </div>
          <div class="categories-grid">
            ${categories.map(categoryCard).join("")}
          </div>
        </div>
      </section>

      <section class="section" id="masters">
        <div class="page split-grid">
          <div>
            <div class="section-head">
              <div>
                <h2>Лучшие мастера</h2>
                <p>Карточки уже выглядят как веб-секция сервиса: ясный статус, цена, специализация и короткое описание без визуальной тесноты.</p>
              </div>
            </div>
            <div class="filter-row" id="categoryFilters">
              ${filterChips(categories)}
            </div>
            <div class="masters-grid">
              ${masters.map(masterCard).join("")}
            </div>
          </div>
          <aside class="feature-list">
            <article class="feature-item">
              <h3>Профиль мастера</h3>
              <p>Отзывы клиентов, портфолио, специализация, цена и рабочие действия собраны в одном месте без лишнего шума.</p>
            </article>
            <article class="feature-item">
              <h3>Выбор исполнителя</h3>
              <p>Клиент может выбрать предпочтительного мастера ещё на этапе создания заявки и продолжить согласование уже по делу.</p>
            </article>
            <article class="feature-item">
              <h3>Чаты и детали заказа</h3>
              <p>После выбора исполнителя диалог и детали заявки остаются в одном связном маршруте, без рваных переходов.</p>
            </article>
          </aside>
        </div>
      </section>

      <section class="section" id="audience">
        <div class="page">
          <div class="section-head">
            <div>
              <h2>Два режима, один сервис</h2>
              <p>Сайт объясняет продукт как веб-платформу, а не как набор мобильных экранов. При этом логика заказчика и мастера остаётся понятной и на телефоне.</p>
            </div>
          </div>
          <section class="section-panel audience-wrap">
            <div class="switcher" id="audienceSwitcher">
              <button class="${state.audience === "customer" ? "active" : ""}" data-audience="customer">Для заказчика</button>
              <button class="${state.audience === "master" ? "active" : ""}" data-audience="master">Для мастера</button>
            </div>
            ${audienceCard(customer, masterProfile)}
          </section>
        </div>
      </section>

      <section class="section" id="orders">
        <div class="page">
          <div class="section-head">
            <div>
              <h2>Актуальные заявки</h2>
              <p>Сайт показывает реальные карточки заказов и нормальную вебовую подачу: статус, район, бюджет и отклики читаются без перегруза.</p>
            </div>
            <div class="section-actions">
              <a class="btn-secondary" href="#contact">Обсудить внедрение</a>
            </div>
          </div>
          <div class="orders-grid">
            ${orders.map(orderCard).join("")}
          </div>
        </div>
      </section>

      <section class="section">
        <div class="page">
          <div class="section-head">
            <div>
              <h2>Как это работает</h2>
              <p>Чистая схема пользовательского пути без декоративной перегрузки: заявка, отклики, выбор исполнителя, чат и выполнение.</p>
            </div>
          </div>
          <div class="steps-grid">
            ${howItWorks().map(stepCard).join("")}
          </div>
        </div>
      </section>

      <section class="section">
        <div class="page">
          <div class="section-head">
            <div>
              <h2>Отзывы клиентов</h2>
              <p>Подтягиваем живые отзывы по мастерам, чтобы сайт выглядел как продукт с реальным контентом, а не как абстрактный макет.</p>
            </div>
          </div>
          <div class="reviews-grid">
            ${reviewCards(state.reviews)}
          </div>
        </div>
      </section>

      <section class="section" id="contact">
        <div class="page">
          <article class="cta-band">
            <h2>USTO уже выглядит как сервис, а не как демо мобильных экранов</h2>
            <p>
              Веб теперь подаёт проект как полноценную платформу: категории, мастера, заявки, чат и роли объясняются в понятной веб-структуре,
              а на мобильном экране всё остаётся компактным и читаемым.
            </p>
            <div class="hero-actions">
              <a class="btn-secondary" href="#categories">Категории</a>
              <a class="btn-ghost" href="#audience">Роли и сценарии</a>
            </div>
          </article>
        </div>
      </section>
    </main>
    ${footer()}
  `;
}

function bind() {
  document.querySelectorAll("[data-audience]").forEach((button) => {
    button.addEventListener("click", () => {
      state.audience = button.dataset.audience;
      render();
      bind();
    });
  });

  document.querySelectorAll("[data-category]").forEach((button) => {
    button.addEventListener("click", () => {
      state.activeCategory = button.dataset.category;
      render();
      bind();
    });
  });
}

function header() {
  return `
    <header class="site-header">
      <div class="page">
        <a class="brand" href="#top" aria-label="USTO">
          <span class="brand-mark">
            <img src="/logo-assets/glyph-mono-white-transparent-512.png" alt="USTO">
          </span>
          <span class="brand-lockup">
            <img src="/logo-assets/wordmark-horizontal-transparent-darktext-900x260.png" alt="USTO">
            <p>Сервис мастеров и заявок в Душанбе</p>
          </span>
        </a>
        <nav class="site-nav">
          <a href="#categories">Категории</a>
          <a href="#masters">Мастера</a>
          <a href="#orders">Заявки</a>
          <a href="#audience">Сценарии</a>
        </nav>
        <div class="header-actions">
          <a class="btn-secondary" href="#masters">Найти мастера</a>
          <a class="btn desktop-hide" href="#orders">Открыть</a>
        </div>
      </div>
    </header>
  `;
}

function footer() {
  return `
    <footer class="site-footer">
      <div class="page">
        <span>USTO · веб-сайт проекта · ${new Date().getFullYear()}</span>
        <nav class="site-footer-nav">
          <a href="#categories">Категории</a>
          <a href="#masters">Мастера</a>
          <a href="#orders">Заявки</a>
        </nav>
      </div>
    </footer>
  `;
}

function statCard(value, label, color) {
  return `
    <article class="stat-card">
      <div class="stat-dot" style="background:${color}"></div>
      <strong>${escapeHtml(String(value))}</strong>
      <span>${escapeHtml(label)}</span>
    </article>
  `;
}

function featuredOrder(order) {
  if (!order) {
    return `<p>Заявки появятся здесь, как только backend вернёт актуальные данные.</p>`;
  }
  return `
    <div class="live-order-top">
      <div>
        <h3>${escapeHtml(order.title)}</h3>
        <div class="chip-row">
          <span class="chip">${escapeHtml(order.category)}</span>
          <span class="meta-pill">${escapeHtml(order.district)}</span>
        </div>
      </div>
      <span class="meta-pill">${escapeHtml(order.status)}</span>
    </div>
    <p>${escapeHtml(order.desc || "Новая заявка клиента")}</p>
    <div class="meta-row" style="margin-top:14px">
      <span class="meta-pill">Бюджет: ${escapeHtml(order.budget || "По договорённости")}</span>
      <span class="meta-pill">Когда: ${escapeHtml(order.when || "Скоро")}</span>
      <span class="meta-pill">${escapeHtml(String(order.responses || 0))} отклика</span>
    </div>
  `;
}

function categoryCard(category) {
  return `
    <article class="category-card">
      <div class="category-icon" style="background:${categoryTint(category.name)}">${escapeHtml(category.icon || "•")}</div>
      <h3>${escapeHtml(category.name)}</h3>
      <p>${categoryDescription(category.name)}</p>
    </article>
  `;
}

function filterChips(categories) {
  return [
    { name: "all", label: "Все категории" },
    ...categories.map((category) => ({ name: category.name, label: category.name })),
  ]
    .map(
      (item) => `
        <button
          class="filter-chip ${state.activeCategory === item.name ? "active" : ""}"
          data-category="${escapeHtml(item.name)}"
        >
          ${escapeHtml(item.label)}
        </button>
      `,
    )
    .join("");
}

function filterMasters(masters) {
  if (state.activeCategory === "all") {
    return masters;
  }
  return masters.filter((master) => master.service === state.activeCategory);
}

function filterOrders(orders) {
  if (state.activeCategory === "all") {
    return orders;
  }
  return orders.filter((order) => order.category === state.activeCategory);
}

function masterCard(master) {
  return `
    <article class="master-card">
      <div class="master-top">
        <div class="avatar-square" style="background:${masterGradient(master.name)}">
          ${escapeHtml(initials(master.name))}
        </div>
        <div class="master-main">
          <h3>${escapeHtml(master.name)}</h3>
          <p>${escapeHtml(master.service)}</p>
          <div class="master-badges chip-row">
            ${master.verified ? `<span class="chip">Проверен</span>` : `<span class="meta-pill">Без проверки</span>`}
            <span class="meta-pill">★ ${escapeHtml(String(master.rating))} (${escapeHtml(String(master.reviews || 0))})</span>
            <span class="meta-pill">${escapeHtml(master.price || "По договорённости")}</span>
          </div>
        </div>
      </div>
      <p class="master-bio">${escapeHtml(master.bio || "")}</p>
      <div class="master-footer">
        <div class="chip-row">
          ${(master.skills || []).slice(0, 3).map((skill) => `<span class="meta-pill">${escapeHtml(skill)}</span>`).join("")}
        </div>
        <a class="ghost-link" href="#orders">Выбрать мастера</a>
      </div>
    </article>
  `;
}

function audienceCard(customer, master) {
  if (state.audience === "master") {
    return `
      <article class="audience-card">
        <h3>${escapeHtml(master.name || "Мастер")} видит только важное</h3>
        <p>
          Профиль мастера, баланс, активные чаты и подходящие заявки собраны в короткий рабочий маршрут.
          Интерфейс не перегружает мастера лишними блоками и ведёт к отклику и общению по заказу.
        </p>
        <div class="audience-points">
          <div class="audience-point">
            <strong>${escapeHtml(String(master.walletBalance || 0))} TJS на балансе</strong>
            <span>Понятная зона для откликов и контроля доступных средств.</span>
          </div>
          <div class="audience-point">
            <strong>${escapeHtml(master.isVerified ? "Профиль проверен" : "Требуется проверка")}</strong>
            <span>Статус виден сразу, без лишних переходов по экрану.</span>
          </div>
          <div class="audience-point">
            <strong>Чаты и заявки рядом</strong>
            <span>Основные действия мастера находятся в одном коротком потоке.</span>
          </div>
          <div class="audience-point">
            <strong>Без лишнего шума</strong>
            <span>Веб рассказывает продукт как сервис, а не как набор мобильных вкладок.</span>
          </div>
        </div>
      </article>
    `;
  }

  return `
    <article class="audience-card">
      <h3>${escapeHtml(customer.name || "Заказчик")} быстро находит исполнителя</h3>
      <p>
        Заказчик создаёт заявку, сравнивает цены и рейтинги мастеров, читает отзывы и выбирает исполнителя
        без визуальной перегрузки. Сайт объясняет этот путь как понятный сервисный сценарий.
      </p>
      <div class="audience-points">
        <div class="audience-point">
          <strong>${escapeHtml(String(customer.publishedCount || 0))} заявок уже в системе</strong>
          <span>История обращений и статусы не прячутся за случайными переходами.</span>
        </div>
        <div class="audience-point">
          <strong>Предпочтительный мастер</strong>
          <span>Можно выбрать мастера заранее и привязать к нему новую заявку.</span>
        </div>
        <div class="audience-point">
          <strong>Отзывы и чат рядом</strong>
          <span>Сначала оценка мастера, потом выбор и согласование деталей в диалоге.</span>
        </div>
        <div class="audience-point">
          <strong>Удобно с телефона</strong>
          <span>На мобильном экране секции не ломаются и остаются читаемыми.</span>
        </div>
      </div>
    </article>
  `;
}

function orderCard(order) {
  return `
    <article class="order-card">
      <div class="order-top">
        <div>
          <h3>${escapeHtml(order.title)}</h3>
          <div class="chip-row" style="margin-top:10px">
            <span class="chip">${escapeHtml(order.category)}</span>
            <span class="meta-pill">${escapeHtml(order.district)}</span>
          </div>
        </div>
        <span class="meta-pill">${escapeHtml(order.status)}</span>
      </div>
      <p>${escapeHtml(order.desc || "Описание заявки появится здесь.")}</p>
      <div class="meta-row" style="margin-top:14px">
        <span class="meta-pill">${escapeHtml(order.budget || "Без бюджета")}</span>
        <span class="meta-pill">${escapeHtml(order.when || "Срок не указан")}</span>
        <span class="meta-pill">${escapeHtml(String(order.responses || 0))} отклика</span>
      </div>
    </article>
  `;
}

function howItWorks() {
  return [
    {
      index: "01",
      title: "Клиент создаёт заявку",
      text: "Описание задачи, район, бюджет и удобное время задают понятный старт для мастеров.",
    },
    {
      index: "02",
      title: "Мастера отправляют предложения",
      text: "Цена, комментарий, рейтинг и статус проверки помогают быстро отсечь слабые варианты.",
    },
    {
      index: "03",
      title: "Выбор и чат",
      text: "После выбора исполнителя детали уже обсуждаются в рабочем чате по конкретной заявке.",
    },
  ];
}

function stepCard(step) {
  return `
    <article class="step-card">
      <div class="step-index">${escapeHtml(step.index)}</div>
      <h3>${escapeHtml(step.title)}</h3>
      <p>${escapeHtml(step.text)}</p>
    </article>
  `;
}

function reviewCards(reviews) {
  if (!reviews.length) {
    return `
      <article class="review-card">
        <h3>Отзывы скоро появятся</h3>
        <p>Секция уже готова под реальные данные мастеров и отзывов клиентов.</p>
      </article>
    `;
  }

  return reviews
    .map(
      (review) => `
        <article class="review-card">
          <h3>${escapeHtml(review.authorName || "Клиент")} · ${escapeHtml(review.masterName || "Мастер")}</h3>
          <div class="stars">${"★".repeat(Number(review.rating || 5))}</div>
          <p>${escapeHtml(review.text || "")}</p>
        </article>
      `,
    )
    .join("");
}

function averageRating(masters) {
  if (!masters.length) {
    return "0.0";
  }
  const total = masters.reduce((sum, master) => sum + Number(master.rating || 0), 0);
  return (total / masters.length).toFixed(1);
}

function countText(value, one, two, many) {
  const mod10 = value % 10;
  const mod100 = value % 100;
  let word = many;
  if (mod10 === 1 && mod100 !== 11) {
    word = one;
  } else if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
    word = two;
  }
  return `${value} ${word}`;
}

function initials(name = "") {
  return name
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0])
    .join("")
    .toUpperCase();
}

function categoryTint(name) {
  const map = {
    "Сантехника": "rgba(59,130,246,0.12)",
    "Электрика": "rgba(245,158,11,0.14)",
    "Ремонт квартир": "rgba(244,114,182,0.12)",
    "Сборка мебели": "rgba(16,185,129,0.12)",
    "Уборка": "rgba(139,92,246,0.12)",
    "Кондиционеры": "rgba(34,211,238,0.14)",
    "Бытовая техника": "rgba(148,163,184,0.14)",
  };
  return map[name] || "rgba(35,86,223,0.12)";
}

function categoryDescription(name) {
  const map = {
    "Сантехника": "Смесители, трубы, бойлеры и быстрый выезд по городу.",
    "Электрика": "Розетки, щиты, освещение и диагностика.",
    "Ремонт квартир": "Отделка, плитка, локальный и комплексный ремонт.",
    "Сборка мебели": "Шкафы, кухни, кровати и аккуратный монтаж.",
    "Уборка": "Квартиры, офисы и генеральная уборка после ремонта.",
    "Кондиционеры": "Установка, чистка, заправка и диагностика.",
    "Бытовая техника": "Стиральные машины, духовки, посудомойки и сервис.",
    "Малярные работы": "Подготовка стен, покраска и аккуратная финишная отделка.",
  };
  return map[name] || "Подходящие мастера и реальные заявки по категории.";
}

function masterGradient(seed = "") {
  const colors = [
    ["#2356df", "#4d83f6"],
    ["#7c3aed", "#a855f7"],
    ["#0f766e", "#14b8a6"],
    ["#ea580c", "#f59e0b"],
  ];
  const index = [...seed].reduce((sum, char) => sum + char.charCodeAt(0), 0) % colors.length;
  const [start, end] = colors[index];
  return `linear-gradient(135deg, ${start}, ${end})`;
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}
