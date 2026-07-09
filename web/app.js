const state = {
  screen: "splash",
  role: "customer",
  tab: "home",
  onboard: 0,
  phone: "",
  otp: "",
  query: "",
  selectedOrderId: 1,
  selectedMasterId: 1,
  wizard: { step: 0, title: "", desc: "", category: "Сантехника", district: "Сино", address: "", budget: "до 300 TJS", when: "Сегодня" },
  responseDraft: { price: 300, comment: "Готов выполнить сегодня. Инструменты с собой, гарантия на работу." },
  chatDraft: "",
  data: null,
};

const app = document.querySelector("#app");
const slides = [
  ["📋", "Опишите задачу", "Вазифаро тавсиф кунед", "Укажите что нужно сделать, район, бюджет и удобное время."],
  ["💬", "Получите отклики", "Ҷавобҳоро бо нарх гиред", "Мастера отправят цену, срок и комментарий прямо в приложении."],
  ["⭐", "Выберите лучшего", "Беҳтаринро интихоб кунед", "Смотрите рейтинг, портфолио, отзывы и переходите в чат."],
];

boot();

async function boot() {
  await loadData();
  render();
  setTimeout(() => {
    if (state.screen === "splash") {
      state.screen = "onboarding";
      render();
    }
  }, 700);
}

async function loadData() {
  const res = await fetch("/api/bootstrap");
  state.data = await res.json();
}

async function refreshFrom(payload) {
  state.data = payload || await (await fetch("/api/bootstrap")).json();
  render();
}

function render() {
  if (!state.data) {
    app.innerHTML = splash();
    return;
  }
  if (state.screen === "splash") app.innerHTML = splash();
  else if (state.screen === "onboarding") app.innerHTML = onboarding();
  else if (state.screen === "auth") app.innerHTML = auth();
  else app.innerHTML = shell();
  bind();
}

function bind() {
  document.querySelectorAll("[data-action]").forEach((el) => {
    el.addEventListener("click", () => actions[el.dataset.action]?.(el));
  });
  document.querySelectorAll("[data-tab]").forEach((el) => {
    el.addEventListener("click", () => {
      state.tab = el.dataset.tab;
      render();
    });
  });
  document.querySelectorAll("[data-value]").forEach((el) => {
    el.addEventListener("input", () => {
      setPath(el.dataset.value, el.value);
      if (el.dataset.value === "query") render();
    });
  });
}

const actions = {
  nextOnboard() {
    if (state.onboard < slides.length - 1) state.onboard += 1;
    else state.screen = "auth";
    render();
  },
  skipOnboard() {
    state.screen = "auth";
    render();
  },
  digit(el) {
    if (state.phone.length < 9) state.phone += el.dataset.digit;
    render();
  },
  backspace() {
    state.phone = state.phone.slice(0, -1);
    render();
  },
  authBack() {
    state.authStep = "phone";
    state.otp = "";
    render();
  },
  otpBackspace() {
    state.otp = state.otp.slice(0, -1);
    render();
  },
  sendOtp() {
    state.otp = "";
    state.screen = "auth";
    state.authStep = "otp";
    render();
  },
  otp(el) {
    if (state.otp.length < 4) state.otp += el.dataset.digit;
    if (state.otp === "1234") {
      state.screen = "app";
      state.tab = "home";
    }
    render();
  },
  switchRole() {
    state.role = state.role === "customer" ? "master" : "customer";
    state.tab = state.role === "customer" ? "home" : "feed";
    render();
  },
  openWizard() {
    state.screen = "wizard";
    render();
  },
  wizardPrev() {
    if (state.wizard.step > 0) state.wizard.step -= 1;
    else state.screen = "app";
    render();
  },
  wizardNext() {
    if (state.wizard.step < 4) state.wizard.step += 1;
    render();
  },
  publishOrder: publishOrder,
  openResponses(el) {
    state.selectedOrderId = Number(el.dataset.id || state.selectedOrderId);
    state.screen = "responses";
    render();
  },
  openOrderDetail(el) {
    state.selectedOrderId = Number(el.dataset.id || state.selectedOrderId);
    state.screen = "orderDetail";
    render();
  },
  openMaster(el) {
    state.selectedMasterId = Number(el.dataset.id || state.selectedMasterId);
    state.screen = "masterProfile";
    render();
  },
  openChat() {
    state.screen = "chat";
    render();
  },
  sendMessage: sendMessage,
  respond: createResponse,
  topup(el) {
    topUp(Number(el.dataset.amount));
  },
  verify: verifyMaster,
  back() {
    state.screen = "app";
    render();
  },
};

function splash() {
  return `<main class="single dark-screen">
    <div class="logo-mark">u</div>
    <h1>usto</h1>
    <p>Найди мастера за 2 минуты</p>
    <span class="loader"></span>
  </main>`;
}

function onboarding() {
  const s = slides[state.onboard];
  return `<main class="single dark-screen">
    <div class="onboard-icon">${s[0]}</div>
    <h1>${s[1]}</h1>
    <em>${s[2]}</em>
    <p>${s[3]}</p>
    <div class="dots">${slides.map((_, i) => `<span class="${i === state.onboard ? "active" : ""}"></span>`).join("")}</div>
    <div class="split-actions">
      <button class="ghost dark" data-action="skipOnboard">Пропустить</button>
      <button class="primary" data-action="nextOnboard">${state.onboard === slides.length - 1 ? "Начать" : "Далее"}</button>
    </div>
  </main>`;
}

function auth() {
  const step = state.authStep || "phone";
  if (step === "otp") {
    return `<main class="single auth-screen">
      <button class="icon light left" data-action="authBack">←</button>
      <h1>Введите код</h1>
      <p>SMS отправлена на <b>+992 ${phoneView()}</b></p>
      <div class="otp-boxes">${[0,1,2,3].map((i) => `<span>${state.otp[i] || ""}</span>`).join("")}</div>
      <p class="hint">Демо-код: <b>1234</b></p>
      ${numPad("otp", "otpBackspace")}
    </main>`;
  }
  return `<main class="single auth-screen">
    <div class="brand-row"><div class="logo tiny">u</div><strong>usto</strong></div>
    <h1>Войти в аккаунт</h1>
    <p>Даромадан ба аккаунт</p>
    <div class="phone-field"><span>🇹🇯 +992</span><b>${phoneView()}</b></div>
    ${numPad("digit", "backspace")}
    <button class="primary wide" ${state.phone.length < 7 ? "disabled" : ""} data-action="sendOtp">Получить SMS-код</button>
  </main>`;
}

function shell() {
  const profile = state.role === "customer" ? state.data.customer : state.data.master;
  return `<main class="app-shell">
    <section class="phone">
      <header class="topbar">
        <div>
          <p>${state.role === "customer" ? "Режим: заказчик" : "Режим: мастер"}</p>
          <h1>${state.role === "customer" ? "Найди мастера" : "Новые заказы рядом"}</h1>
        </div>
        <button class="icon" data-action="switchRole" title="Сменить режим">⇄</button>
      </header>
      <label class="search"><span>⌕</span><input data-value="query" value="${esc(state.query)}" placeholder="Поиск услуг, мастеров и заявок"></label>
      <section class="content">${screenContent()}</section>
      ${bottomNav()}
    </section>
    <aside class="desktop-panel">
      <section class="panel">
        <p class="overline">Сводка</p>
        <h2>${profile.name}</h2>
        <div class="metrics">
          <span><b>${state.data.orders.length}</b> заявок</span>
          <span><b>${profile.walletBalance}</b> TJS</span>
          <span><b>${profile.isVerified ? "✓" : "!"}</b> проверка</span>
        </div>
      </section>
      <section class="panel">${feedOrders(true)}</section>
    </aside>
  </main>`;
}

function screenContent() {
  if (state.screen === "wizard") return wizard();
  if (state.screen === "responses") return responsesScreen();
  if (state.screen === "orderDetail") return orderDetail();
  if (state.screen === "chat") return chatScreen();
  if (state.screen === "masterProfile") return masterProfile();
  if (state.role === "master") return masterHome();
  return customerHome();
}

function customerHome() {
  if (state.tab === "orders") return `<div class="head"><h2>Мои заявки</h2><button class="primary sm" data-action="openWizard">Создать</button></div>${ordersList(state.data.orders)}`;
  if (state.tab === "chats") return chatsList();
  if (state.tab === "profile") return profileScreen(state.data.customer);
  if (state.tab === "masters") return mastersList();
  return `<section class="hero">
    <p>Нужна помощь по дому?</p><h2>Создай заявку и получи отклики с ценами</h2>
    <button class="white-btn" data-action="openWizard">+ Создать заявку</button>
  </section>
  <div class="head"><h2>Категории</h2><button data-tab="masters">Все</button></div>
  <div class="grid4">${filteredCategories().map(categoryCard).join("")}</div>
  <div class="head"><h2>Лучшие мастера</h2><button data-tab="masters">Все</button></div>
  <div class="hscroll">${filteredMasters().map(masterMini).join("")}</div>
  <div class="head"><h2>Активные заявки</h2></div>${ordersList(state.data.orders.slice(0, 1))}`;
}

function masterHome() {
  if (state.tab === "responses") return `<div class="head"><h2>Мои отклики</h2></div>${responsesList(state.data.responses)}`;
  if (state.tab === "chats") return chatsList();
  if (state.tab === "wallet") return walletScreen();
  if (state.tab === "profile") return profileScreen(state.data.master);
  return feedOrders(false);
}

function feedOrders(compact) {
  return `<div class="head"><h2>${compact ? "Новые заказы" : "Лента заказов"}</h2></div>${ordersList(filteredOrders(), true)}`;
}

function ordersList(orders, forMaster = false) {
  if (!orders.length) return `<div class="empty">Пока ничего не найдено</div>`;
  return `<div class="stack">${orders.map((o) => `<article class="card clickable" data-action="${forMaster ? "openOrderDetail" : "openResponses"}" data-id="${o.id}">
    <div class="row"><h3>${o.title}</h3><span class="badge">${o.responses} отклика</span></div>
    <p>${o.category} · ${o.district} · ${o.createdAt}</p>
    <div class="tags"><span>${o.budget}</span><span>${o.when}</span><span>${o.status}</span></div>
  </article>`).join("")}</div>`;
}

function responsesScreen() {
  const order = selectedOrder();
  return `<button class="back" data-action="back">← Назад</button>
    <div class="head"><h2>Отклики</h2><span class="muted">${order.title}</span></div>
    ${responsesList(state.data.responses)}
    <button class="primary wide" data-action="openChat">Открыть чат</button>`;
}

function responsesList(items) {
  if (!items.length) return `<div class="empty">Откликов пока нет</div>`;
  return `<div class="stack">${items.map((r) => `<article class="card">
    <div class="row"><h3>${r.master}</h3><span class="price">${r.price} TJS</span></div>
    <p>★ ${r.rating} · ${r.createdAt}</p>
    <p>${r.comment}</p>
    <div class="split-actions"><button class="ghost" data-action="openMaster" data-id="${r.masterId}">Профиль</button><button class="primary" data-action="openChat">Чат</button></div>
  </article>`).join("")}</div>`;
}

function orderDetail() {
  const order = selectedOrder();
  return `<button class="back" data-action="back">← Назад</button>
    <article class="card detail">
      <span class="badge">${order.category}</span>
      <h2>${order.title}</h2>
      <p>${order.desc}</p>
      <div class="info-grid"><span>${order.district}</span><span>${order.budget}</span><span>${order.when}</span><span>${order.views} просмотров</span></div>
    </article>
    <article class="card">
      <h3>Откликнуться</h3>
      <label>Цена, TJS<input type="number" data-value="responseDraft.price" value="${state.responseDraft.price}"></label>
      <label>Комментарий<textarea data-value="responseDraft.comment">${state.responseDraft.comment}</textarea></label>
      <p class="muted">С баланса спишется 4 TJS</p>
      <button class="primary wide" data-action="respond">Подтвердить отклик</button>
    </article>`;
}

function chatScreen() {
  return `<button class="back" data-action="back">← Назад</button>
    <div class="chat">${state.data.messages.map((m) => `<div class="bubble ${m.fromRole === state.role ? "me" : ""}"><p>${m.text}</p><time>${m.createdAt}</time></div>`).join("")}</div>
    <div class="composer"><input data-value="chatDraft" value="${esc(state.chatDraft)}" placeholder="Сообщение"><button class="primary" data-action="sendMessage">↑</button></div>`;
}

function masterProfile() {
  const m = state.data.masters.find((item) => item.id === state.selectedMasterId) || state.data.masters[0];
  return `<button class="back" data-action="back">← Назад</button>
    <section class="profile-hero">
      <div class="avatar">${initials(m.name)}</div>
      <h2>${m.name}</h2>
      <p>${m.service} · ★ ${m.rating} (${m.reviews})</p>
      <button class="primary" data-action="openChat">Написать</button>
    </section>
    <article class="card"><h3>О мастере</h3><p>${m.bio}</p><div class="tags">${m.skills.map((s) => `<span>${s}</span>`).join("")}</div></article>
    <div class="portfolio">${m.portfolio.map((p) => `<span>${p}</span>`).join("")}</div>
    <article class="card"><h3>Отзывы</h3><p>Работа выполнена быстро и аккуратно. Мастер приехал вовремя, цена как договорились.</p></article>`;
}

function wizard() {
  const w = state.wizard;
  const steps = [
    `<h2>Что нужно сделать?</h2><label>Описание<textarea data-value="wizard.desc" placeholder="Опишите задачу">${esc(w.desc)}</textarea></label>`,
    `<h2>Категория</h2><div class="grid2">${state.data.categories.map((c) => `<button class="${w.category === c.name ? "selected" : ""}" data-action="pickCategory" data-cat="${c.name}">${c.icon} ${c.name}</button>`).join("")}</div>`,
    `<h2>Где выполнить?</h2><label>Район<input data-value="wizard.district" value="${esc(w.district)}"></label><label>Адрес<input data-value="wizard.address" value="${esc(w.address)}"></label>`,
    `<h2>Когда и бюджет</h2><label>Когда<select data-value="wizard.when">${["Сегодня","Завтра","На неделе","Не срочно"].map((x) => `<option ${w.when === x ? "selected" : ""}>${x}</option>`).join("")}</select></label><label>Бюджет<input data-value="wizard.budget" value="${esc(w.budget)}"></label>`,
    `<h2>Проверка</h2><label>Название заявки<input data-value="wizard.title" value="${esc(w.title || w.desc)}"></label><div class="summary">${w.category} · ${w.district} · ${w.budget}</div>`,
  ];
  setTimeout(() => {
    document.querySelectorAll("[data-action='pickCategory']").forEach((b) => b.addEventListener("click", () => {
      state.wizard.category = b.dataset.cat;
      render();
    }));
  });
  return `<button class="back" data-action="wizardPrev">← Назад</button>
    <div class="progress"><span style="width:${(w.step + 1) * 20}%"></span></div>
    <article class="card wizard">${steps[w.step]}</article>
    <div class="split-actions">${w.step < 4 ? `<button class="primary wide" data-action="wizardNext">Далее</button>` : `<button class="primary wide" data-action="publishOrder">Опубликовать</button>`}</div>`;
}

function mastersList() {
  return `<div class="head"><h2>Мастера рядом</h2></div><div class="stack">${filteredMasters().map(masterCard).join("")}</div>`;
}

function walletScreen() {
  const p = state.data.master;
  return `<section class="wallet"><p>Баланс</p><h2>${p.walletBalance} <span>TJS</span></h2></section>
    <div class="grid4">${[20,50,100,200].map((a) => `<button class="amount" data-action="topup" data-amount="${a}">${a}<small>TJS</small></button>`).join("")}</div>
    <div class="head"><h2>История</h2></div><div class="stack">${state.data.transactions.map((t) => `<article class="tx"><span>${t.amount > 0 ? "↑" : "↓"}</span><p>${t.label}<small>${t.createdAt}</small></p><b>${t.amount > 0 ? "+" : ""}${t.amount}</b></article>`).join("")}</div>`;
}

function profileScreen(profile) {
  return `<section class="profile-hero">
    <div class="avatar">${initials(profile.name)}</div>
    <h2>${profile.name}</h2>
    <p>${profile.role === "master" ? "Мастер" : "Заказчик"} · ${profile.city}</p>
  </section>
  <div class="metrics"><span><b>${profile.publishedCount || profile.completedJobs}</b>${profile.role === "master" ? "работ" : "заявок"}</span><span><b>${profile.walletBalance}</b>TJS</span><span><b>${profile.isVerified ? "✓" : "!"}</b>проверка</span></div>
  ${profile.role === "master" && !profile.isVerified ? `<button class="primary wide" data-action="verify">Пройти верификацию</button>` : ""}
  <button class="ghost wide" data-action="switchRole">${profile.role === "master" ? "Режим заказчика" : "Режим мастера"}</button>`;
}

function chatsList() {
  const last = state.data.messages.at(-1);
  return `<div class="head"><h2>Чаты</h2></div><article class="card clickable" data-action="openChat"><h3>Фаррух Турсунов</h3><p>${last ? last.text : "Нет сообщений"}</p></article>`;
}

function bottomNav() {
  const tabs = state.role === "customer"
    ? [["home","⌂","Главная"],["orders","□","Заявки"],["chats","◌","Чаты"],["profile","●","Профиль"]]
    : [["feed","⌕","Лента"],["responses","□","Отклики"],["chats","◌","Чаты"],["wallet","▣","Кошелёк"],["profile","●","Профиль"]];
  return `<nav class="bottom">${tabs.map(([id, icon, label]) => `<button class="${state.tab === id ? "active" : ""}" data-tab="${id}"><span>${icon}</span>${label}</button>`).join("")}</nav>`;
}

function categoryCard(c) {
  return `<button class="cat" data-action="openWizard"><span>${c.icon}</span><b>${c.name}</b></button>`;
}

function masterMini(m) {
  return `<article class="mini clickable" data-action="openMaster" data-id="${m.id}"><div class="avatar">${initials(m.name)}</div><h3>${m.name}</h3><p>${m.service}</p><b>★ ${m.rating}</b></article>`;
}

function masterCard(m) {
  return `<article class="card clickable" data-action="openMaster" data-id="${m.id}"><div class="row"><div><h3>${m.name}</h3><p>${m.service} · ${m.price}</p></div><span class="badge">★ ${m.rating}</span></div><div class="tags">${m.skills.map((s) => `<span>${s}</span>`).join("")}</div></article>`;
}

function numPad(action, backAction) {
  return `<div class="numpad">${["1","2","3","4","5","6","7","8","9"].map((n) => `<button data-action="${action}" data-digit="${n}">${n}</button>`).join("")}<i></i><button data-action="${action}" data-digit="0">0</button><button data-action="${backAction}">⌫</button></div>`;
}

async function publishOrder() {
  const w = state.wizard;
  const payload = { ...w, title: w.title || w.desc || "Новая заявка" };
  const res = await fetch("/api/orders", { method: "POST", headers: jsonHeaders(), body: JSON.stringify(payload) });
  if (res.ok) {
    state.screen = "app";
    state.tab = "orders";
    state.wizard = { step: 0, title: "", desc: "", category: "Сантехника", district: "Сино", address: "", budget: "до 300 TJS", when: "Сегодня" };
    await refreshFrom();
  }
}

async function createResponse() {
  const res = await fetch("/api/responses", { method: "POST", headers: jsonHeaders(), body: JSON.stringify({ orderId: state.selectedOrderId, price: Number(state.responseDraft.price), comment: state.responseDraft.comment }) });
  if (res.ok) {
    state.screen = "app";
    state.tab = "responses";
    await refreshFrom(await res.json());
  }
}

async function sendMessage() {
  if (!state.chatDraft.trim()) return;
  const res = await fetch("/api/messages", { method: "POST", headers: jsonHeaders(), body: JSON.stringify({ fromRole: state.role, text: state.chatDraft }) });
  if (res.ok) {
    state.data.messages = await res.json();
    state.chatDraft = "";
    render();
  }
}

async function topUp(amount) {
  const res = await fetch("/api/wallet/topup", { method: "POST", headers: jsonHeaders(), body: JSON.stringify({ amount }) });
  if (res.ok) await refreshFrom(await res.json());
}

async function verifyMaster() {
  const res = await fetch("/api/verification", { method: "POST" });
  if (res.ok) await refreshFrom(await res.json());
}

function selectedOrder() {
  return state.data.orders.find((o) => o.id === state.selectedOrderId) || state.data.orders[0];
}

function filteredCategories() {
  return state.data.categories.filter((c) => match(c.name));
}

function filteredMasters() {
  return state.data.masters.filter((m) => match(`${m.name} ${m.service} ${m.skills.join(" ")}`));
}

function filteredOrders() {
  return state.data.orders.filter((o) => match(`${o.title} ${o.category} ${o.district} ${o.desc}`));
}

function match(text) {
  return !state.query || text.toLowerCase().includes(state.query.toLowerCase());
}

function setPath(path, value) {
  const parts = path.split(".");
  let target = state;
  while (parts.length > 1) target = target[parts.shift()];
  target[parts[0]] = value;
}

function phoneView() {
  const p = (state.phone + "·········").slice(0, 9);
  return `${p.slice(0, 3)} ${p.slice(3, 6)} ${p.slice(6, 8)} ${p.slice(8)}`;
}

function initials(name) {
  return name.split(" ").filter(Boolean).slice(0, 2).map((x) => x[0]).join("").toUpperCase();
}

function jsonHeaders() {
  return { "Content-Type": "application/json" };
}

function esc(value) {
  return String(value ?? "").replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
}
