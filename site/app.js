"use strict";

const byId = (id) => document.getElementById(id);
const store = byId("edition");
let edition = JSON.parse(store.textContent);
const originalShell = "<!doctype html>\n" + document.documentElement.outerHTML;
const pageSize = 45;
let visible = pageSize;
let topic = "";
const search = byId("search");
const sourceFilter = byId("source-filter");
const fullFilter = byId("full-filter");
const stories = byId("stories");
const loadMore = byId("load-more");
const reader = byId("reader");
const sourcesDialog = byId("sources-dialog");
const themeDialog = byId("theme-dialog");
const refreshButton = byId("refresh");
const refreshNote = byId("refresh-note");
const showEdition = byId("show-edition");
const chineseTime = new Intl.DateTimeFormat("zh-CN", {
  timeZone: "Asia/Hong_Kong", hour: "2-digit", minute: "2-digit", hourCycle: "h23",
});
const chineseDate = new Intl.DateTimeFormat("zh-CN", {
  timeZone: "Asia/Hong_Kong", month: "long", day: "numeric", weekday: "long",
});
const topicOrder = ["中国大陆", "港澳台", "亚太", "欧洲", "中东", "美洲", "国际"];

function node(tag, className, text) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  if (text) element.textContent = text;
  return element;
}

function link(text, href) {
  const element = node("a", "", text);
  const url = new URL(href);
  if (url.protocol !== "https:") throw new Error("Unexpected link protocol");
  element.href = url.href;
  element.target = "_blank";
  element.rel = "noopener noreferrer";
  return element;
}

function available() {
  const cutoff = Date.now() - edition.windowDays * 24 * 60 * 60 * 1000;
  return edition.items.filter((item) => Date.parse(item.publishedAt) >= cutoff);
}

function currentPublisher(id) {
  return edition.sources.find((publisher) => publisher.id === id);
}

function includesSearch(item, query) {
  const pieces = [
    item.title, item.originalTitle, item.summary, item.translation?.title,
    item.translation?.summary, currentPublisher(item.source)?.name, ...item.topics,
  ];
  const haystack = pieces.filter(Boolean).join(" ").toLocaleLowerCase();
  return query.every((term) => haystack.includes(term));
}

function applyFilters() {
  visible = pageSize;
  render();
}

function renderTopics(items) {
  const topicNav = byId("topics");
  const priorFocus = document.activeElement?.dataset?.topic;
  const counts = new Map();
  for (const item of items) {
    for (const label of item.topics) counts.set(label, (counts.get(label) || 0) + 1);
  }
  const buttons = [];
  for (const label of ["", ...topicOrder]) {
    const button = node("button", "topic");
    button.type = "button";
    button.dataset.topic = label;
    button.setAttribute("aria-pressed", String(label === topic));
    button.append(node("span", "", label || "全部报道"));
    button.append(node("span", "", String(label ? counts.get(label) || 0 : items.length)));
    button.addEventListener("click", () => {
      topic = label;
      applyFilters();
    });
    buttons.push(button);
  }
  topicNav.replaceChildren(...buttons);
  if (priorFocus !== undefined) buttons.find((button) => button.dataset.topic === priorFocus)?.focus();
}

function articleRow(item) {
  const source = currentPublisher(item.source);
  const row = node("article", "story");
  const published = node("time", "", chineseTime.format(new Date(item.publishedAt)));
  published.dateTime = item.publishedAt;
  const content = node("div");
  const meta = node("div", "story-meta");
  meta.append(node("span", "publisher", source.name), node("span", "", item.topics.join(" · ")));
  if (item.kind === "评论") meta.append(node("span", "", "评论"));
  const title = node("h3", "", item.originalTitle || item.title);
  title.lang = item.lang;
  content.append(meta, title);
  const originalSummary = item.originalSummary ?? item.summary;
  if (originalSummary) {
    const summary = node("p", "", originalSummary);
    summary.lang = item.lang;
    content.append(summary);
  }
  const actions = node("div", "story-actions");
  if (item.full) {
    const button = node("button", "text-button", "站内读全文");
    button.type = "button";
    button.addEventListener("click", () => openArticle(item, source));
    actions.append(button);
  }
  actions.append(link("查看原文", item.url));
  if (source.credit) actions.append(node("span", "", source.credit));
  const analysis = node("button", "text-button analysis-action", "AI 分析");
  analysis.type = "button";
  analysis.addEventListener("click", () => openAnalysis(item, source));
  actions.append(analysis);
  content.append(actions);
  if (!item.lang.toLowerCase().startsWith("zh")) {
    const details = node("details");
    details.append(node("summary", "text-button", "翻译"));
    const url = new URL("https://translate.google.com/");
    const material = [item.originalTitle || item.title, originalSummary].filter(Boolean).join("\n\n");
    url.search = new URLSearchParams({sl: item.lang, tl: "zh-CN", text: material, op: "translate"});
    const translated = node("p", "", "");
    details.append(translated, link("在 Google 翻译中打开", url.href));
    details.addEventListener("toggle", async () => {
      if (!details.open || translated.dataset.attempted || !window.Translator) return;
      translated.dataset.attempted = "true";
      try {
        const options = {sourceLanguage: item.lang, targetLanguage: "zh"};
        const model = await window.Translator.create(options);
        try { translated.textContent = await model.translate(material); }
        finally { model.destroy(); }
      } catch { /* The link remains available on browsers without a usable model. */ }
    });
    content.append(details);
  }
  row.append(published, content);
  return row;
}

const analysisProviders = [
  ["grok", "Grok", "https://grok.com/"],
  ["chatgpt", "ChatGPT", "https://chatgpt.com/"],
  ["gemini", "Gemini", "https://gemini.google.com/app"],
  ["claude", "Claude", "https://claude.ai/new"],
  ["deepseek", "DeepSeek", "https://chat.deepseek.com/"],
];

function openAnalysis(item, source) {
  const select = byId("analysis-provider");
  const notes = item.originalSummary ?? item.summary;
  const authorizedText = item.full?.body?.join("\n\n");
  const prompt = "用简体中文分析以下新闻，概述事实和不确定性，只参考提供的资料。\n\n" +
    source.name + " · " + (item.originalTitle || item.title) + "\n" + item.url + "\n" +
    ((authorizedText || notes || "来源仅提供标题").slice(0, 12000));
  byId("analysis-title").textContent = item.originalTitle || item.title;
  byId("analysis-source").textContent = source.name;
  select.replaceChildren(...analysisProviders.map(([id, name]) => new Option(name, id)));
  byId("analysis-prompt").hidden = true;
  byId("analysis-prompt").value = prompt;
  const copy = byId("analysis-copy");
  async function copyPrompt() {
    try {
      await navigator.clipboard.writeText(prompt);
      copy.textContent = "已复制提问";
    } catch {
      byId("analysis-prompt").hidden = false;
      byId("analysis-prompt").select();
    }
  }
  function selectProvider() {
    const [id, name, base] = analysisProviders.find(([id]) => id === select.value);
    const result = item.analysis?.[id];
    byId("analysis-note").textContent = result ? name + " 分析 · 依据媒体资料" : name + " 暂无站内分析 · 以下来自媒体";
    byId("analysis-text").textContent = result || notes || item.full?.body?.[0] || "来源只提供标题。";
    const external = byId("analysis-open");
    const url = new URL(base);
    const prefill = (id === "grok" || id === "chatgpt") && prompt.length < 1600;
    if (prefill) url.searchParams.set("q", prompt);
    external.href = url.href;
    external.textContent = "打开 " + name;
    external.onclick = prefill ? null : () => void copyPrompt();
    copy.textContent = "复制分析提问";
  }
  copy.onclick = copyPrompt;
  select.onchange = selectProvider;
  selectProvider();
  byId("analysis-dialog").showModal();
}

function openArticle(item, source) {
  const { body, byline, credit, title, license, licenseLabel } = item.full;
  byId("reader-source").textContent = source.name + " · " + chineseDate.format(new Date(item.publishedAt));
  byId("reader-title").textContent = title || item.originalTitle;
  const creditBlock = byId("reader-credit");
  creditBlock.replaceChildren(
    node("p", "", byline), link("原文", item.url), document.createTextNode(" · "),
    link(licenseLabel, license), node("p", "", credit),
  );
  const bodyBlock = byId("reader-body");
  bodyBlock.lang = item.lang === "en" ? "en" : "zh";
  bodyBlock.replaceChildren(...body.map((paragraph) => node("p", "", paragraph)));
  reader.showModal();
  reader.scrollTop = 0;
}

function render() {
  const items = available();
  const query = search.value.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
  const source = sourceFilter.value;
  const usingFull = fullFilter.checked;
  const eligible = items.filter((item) => (!source || item.source === source) &&
    (!usingFull || item.full) && (!query.length || includesSearch(item, query)));
  const matching = topic ? eligible.filter((item) => item.topics.includes(topic)) : eligible;
  byId("feed-heading").textContent = topic || "全部报道";
  byId("result-count").textContent = matching.length + " 条报道";
  renderEditionTime();
  renderTopics(eligible);
  loadMore.hidden = visible >= matching.length;
  if (!matching.length) {
    stories.replaceChildren(node("p", "empty", items.length ? "没有符合筛选条件的报道。" : "当前快照中没有最近七天的报道。"));
    return;
  }
  const groups = [];
  let lastDate;
  for (const item of matching.slice(0, visible)) {
    const date = chineseDate.format(new Date(item.publishedAt));
    if (date !== lastDate) {
      const group = node("section", "date-group");
      group.append(node("h2", "date-heading", date));
      groups.push(group);
      lastDate = date;
    }
    groups[groups.length - 1].append(articleRow(item));
  }
  stories.replaceChildren(...groups);
}

function renderEditionTime() {
  const lastUpdate = new Date(edition.updatedAt);
  const update = byId("update-time");
  update.textContent = (location.protocol === "file:" ? "快照 " : "发布 ") +
    chineseDate.format(lastUpdate).replace(/星期[一二三四五六日]/, "").trim() + " " +
    chineseTime.format(lastUpdate);
  update.title = "香港时间";
  update.dateTime = edition.updatedAt;
}

function renderPublishers() {
  const currentSource = sourceFilter.value;
  const options = [new Option("全部媒体", "")];
  const rows = [];
  for (const source of edition.sources) {
    options.push(new Option(source.name, source.id));
    const row = node("section", "source-row");
    const title = node("h3");
    title.append(link(source.name, source.site));
    row.append(title);
    const healthy = source.health.filter((feed) => !feed.error);
    const status = healthy.length === source.health.length ? "订阅可用" :
      (healthy.length ? "部分订阅可用" : "订阅暂不可用");
    const newest = healthy.map((feed) => feed.newestAt).filter(Boolean).sort().at(-1);
    const recent = newest ? " · 最新 " + chineseDate.format(new Date(newest)) + " " + chineseTime.format(new Date(newest)) : "";
    row.append(node("p", "", source.region + " · " + status + recent));
    if (source.terms) row.append(link("媒体使用条款", source.terms));
    rows.push(row);
  }
  sourceFilter.replaceChildren(...options);
  sourceFilter.value = currentSource;
  byId("sources-list").replaceChildren(...rows);
}

function saveEdition() {
  const data = JSON.stringify(edition).replace(/</g, "\\u003c").replace(/>/g, "\\u003e").replace(/&/g, "\\u0026");
  const html = originalShell.replace(
    /(<script id="edition" type="application\/json">)[\s\S]*?(<\/script>)/,
    (_full, start, end) => start + data + end,
  );
  const objectUrl = URL.createObjectURL(new Blob([html], { type: "text/html;charset=utf-8" }));
  const anchor = node("a");
  anchor.href = objectUrl;
  anchor.download = "fieldnote-" + edition.updatedAt.slice(0, 10) + ".html";
  document.body.append(anchor);
  anchor.click();
  anchor.remove();
  setTimeout(() => URL.revokeObjectURL(objectUrl), 1000);
}

const themes = [
  { id: "red", label: "新闻红", swatch: "#b80000" },
  { id: "navy", label: "海军蓝", swatch: "#175472" },
  { id: "forest", label: "森林绿", swatch: "#17654b" },
  { id: "plum", label: "梅子紫", swatch: "#713b83" },
  { id: "night", label: "夜间", swatch: "#28283d" },
];
const themeKey = "fieldnote-theme";
const refreshKey = "fieldnote-last-manual-refresh";
const halfHour = 30 * 60 * 1000;
const retryDelays = [20, 45, 90, 180, 360];
const isOnlinePage = location.protocol === "https:" || location.protocol === "http:";
let pendingEdition;
let manualInProgress = false;
let lastManual = Number(readPreference(refreshKey)) || 0;
let cooldownTimer;
let activeSlot;
let slotTimer;
let retryTimer;
let autoDeferred = false;

function readPreference(key) {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function savePreference(key, value) {
  try {
    localStorage.setItem(key, value);
  } catch {
    // The current tab still works when storage is disabled.
  }
}

function setTheme(theme, remember = false) {
  const selected = themes.some((option) => option.id === theme) ? theme : "red";
  document.documentElement.dataset.theme = selected;
  if (remember) savePreference(themeKey, selected);
  for (const button of byId("theme-options").children) {
    const active = button.dataset.theme === selected;
    button.setAttribute("aria-pressed", String(active));
    button.lastElementChild.textContent = active ? "已选" : "";
  }
}

function buildThemeChooser() {
  const buttons = themes.map((theme) => {
    const button = node("button", "theme-option");
    button.type = "button";
    button.dataset.theme = theme.id;
    const swatch = node("span", "swatch");
    swatch.setAttribute("aria-hidden", "true");
    swatch.style.setProperty("--swatch", theme.swatch);
    const selected = node("span", "theme-selected");
    selected.setAttribute("aria-hidden", "true");
    button.append(swatch, node("span", "", theme.label), selected);
    button.addEventListener("click", () => setTheme(theme.id, true));
    return button;
  });
  byId("theme-options").replaceChildren(...buttons);
  setTheme(readPreference(themeKey));
}

async function checkForEdition() {
  const controller = new AbortController();
  const deadline = setTimeout(() => controller.abort(), 15000);
  try {
    const response = await fetch("./feed.json", { cache: "no-store", credentials: "omit", signal: controller.signal });
    if (!response.ok) throw new Error("The edition could not be fetched");
    const next = await response.json();
    if (next.version !== 1 || !Number.isFinite(Date.parse(next.updatedAt)) ||
        !Array.isArray(next.items) || !Array.isArray(next.sources)) {
      throw new Error("The edition has an unexpected format");
    }
    if (next.updatedAt > (pendingEdition || edition).updatedAt) {
      pendingEdition = next;
      showEdition.hidden = false;
    }
    return Date.parse(next.updatedAt);
  } finally {
    clearTimeout(deadline);
  }
}

function updateRefreshButton() {
  clearTimeout(cooldownTimer);
  const remaining = lastManual + halfHour - Date.now();
  const locked = !isOnlinePage || manualInProgress || remaining > 0;
  refreshButton.setAttribute("aria-disabled", String(locked));
  refreshButton.setAttribute("aria-busy", String(manualInProgress));
  refreshButton.classList.toggle("is-refreshing", manualInProgress);
  if (remaining > 0) cooldownTimer = setTimeout(updateRefreshButton, remaining + 50);
  else if (refreshNote.dataset.cooldown) {
    delete refreshNote.dataset.cooldown;
    refreshNote.textContent = "整点、半点自动更新";
  }
}

async function manualRefresh() {
  if (!isOnlinePage || manualInProgress) return;
  // Re-read the shared timestamp before issuing a request from another tab.
  lastManual = Math.max(lastManual, Number(readPreference(refreshKey)) || 0);
  const remaining = lastManual + halfHour - Date.now();
  if (remaining > 0) {
    refreshNote.dataset.cooldown = "true";
    refreshNote.textContent = "约 " + Math.ceil(remaining / 60000) + " 分钟后可再次刷新";
    updateRefreshButton();
    return;
  }
  lastManual = Date.now();
  savePreference(refreshKey, String(lastManual));
  manualInProgress = true;
  delete refreshNote.dataset.cooldown;
  refreshNote.textContent = "正在更新，请稍候";
  updateRefreshButton();
  try {
    await checkForEdition();
    refreshNote.textContent = pendingEdition ? "新版已就绪" : "已检查，目前是最新一期";
  } catch {
    refreshNote.textContent = "暂时无法检查更新";
  } finally {
    manualInProgress = false;
    updateRefreshButton();
  }
}

function openPendingEdition() {
  if (!pendingEdition || reader.open || sourcesDialog.open || themeDialog.open) return;
  edition = pendingEdition;
  pendingEdition = undefined;
  delete refreshNote.dataset.cooldown;
  refreshNote.textContent = "已切换到最新一期";
  refreshButton.focus({ preventScroll: true });
  showEdition.hidden = true;
  renderPublishers();
  render();
}

async function autoRefresh(slot, retry = 0) {
  if (activeSlot !== slot) return;
  if (document.hidden) {
    autoDeferred = true;
    return;
  }
  try {
    const updated = await checkForEdition();
    if (updated >= slot) return;
  } catch {
    // Keep the current list available while the next publication is pending.
  }
  if (activeSlot === slot && retry < retryDelays.length) {
    const wait = Math.max(0, slot + retryDelays[retry] * 1000 - Date.now());
    retryTimer = setTimeout(() => void autoRefresh(slot, retry + 1), wait);
  }
}

function scheduleAutoRefresh() {
  if (!isOnlinePage) return;
  clearTimeout(slotTimer);
  const now = Date.now();
  // Hong Kong is UTC+8 throughout the year. Epoch half-hours align with local :00 and :30.
  const slot = Math.floor(now / halfHour) * halfHour;
  if (!document.hidden && (slot !== activeSlot || autoDeferred)) {
    clearTimeout(retryTimer);
    activeSlot = slot;
    autoDeferred = false;
    void autoRefresh(slot);
  }
  slotTimer = setTimeout(scheduleAutoRefresh, slot + halfHour - now);
}

if (window.matchMedia("(max-width: 760px)").matches) byId("filters").open = false;
byId("sources-button").addEventListener("click", () => sourcesDialog.showModal());
byId("close-sources").addEventListener("click", () => sourcesDialog.close());
byId("close-reader").addEventListener("click", () => reader.close());
byId("close-analysis").addEventListener("click", () => byId("analysis-dialog").close());
byId("theme-button").addEventListener("click", () => themeDialog.showModal());
byId("close-theme").addEventListener("click", () => themeDialog.close());
byId("download").addEventListener("click", saveEdition);
refreshButton.addEventListener("click", () => void manualRefresh());
showEdition.addEventListener("click", openPendingEdition);
search.addEventListener("input", applyFilters);
sourceFilter.addEventListener("change", applyFilters);
fullFilter.addEventListener("change", applyFilters);
loadMore.addEventListener("click", () => {
  visible += pageSize;
  const oldCount = stories.querySelectorAll(".story").length;
  render();
  const firstNewStory = stories.querySelectorAll(".story")[oldCount];
  if (firstNewStory) {
    firstNewStory.tabIndex = -1;
    firstNewStory.focus();
  }
});
document.addEventListener("visibilitychange", scheduleAutoRefresh);
window.addEventListener("storage", (event) => {
  if (event.key === themeKey) setTheme(event.newValue);
  if (event.key === refreshKey) {
    lastManual = Number(event.newValue) || 0;
    updateRefreshButton();
  }
});
if (!isOnlinePage) {
  refreshButton.hidden = true;
  refreshNote.textContent = "离线快照";
}
buildThemeChooser();
updateRefreshButton();
renderPublishers();
render();
scheduleAutoRefresh();
