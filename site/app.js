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
const chineseTime = new Intl.DateTimeFormat("zh-CN", {
  timeZone: "Asia/Shanghai", hour: "2-digit", minute: "2-digit", hourCycle: "h23",
});
const chineseDate = new Intl.DateTimeFormat("zh-CN", {
  timeZone: "Asia/Shanghai", month: "long", day: "numeric", weekday: "long",
});
const topicOrder = ["中国政治", "港澳台", "中东", "俄乌与欧洲", "亚太", "美洲", "国际"];

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
  const translated = item.translation;
  const title = node("h3", "", translated?.title || item.title);
  if (item.lang === "en") {
    if (translated) title.title = item.originalTitle;
    else title.lang = "en";
  }
  content.append(meta, title);
  if (translated?.summary || item.summary) {
    const summary = node("p", "", translated?.summary || item.summary);
    if (!translated?.summary && item.lang === "en") summary.lang = "en";
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
  if (translated) actions.append(node("span", "", "机器翻译"));
  if (source.credit) actions.append(node("span", "", source.credit));
  content.append(actions);
  row.append(published, content);
  return row;
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
  const lastUpdate = new Date(edition.updatedAt);
  const stale = Date.now() - lastUpdate.getTime() > 90 * 60 * 1000;
  const update = byId("update-time");
  update.textContent = (location.protocol === "file:" || stale ? "快照 " : "更新 ") +
    chineseDate.format(lastUpdate).replace(/星期[一二三四五六日]/, "").trim() + " " +
    chineseTime.format(lastUpdate);
  update.title = "北京时间";
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

let lastCheck = Date.now();
async function checkForEdition() {
  if (!["http:", "https:"].includes(location.protocol) || Date.now() - lastCheck < 4 * 60 * 1000) return;
  lastCheck = Date.now();
  try {
    const response = await fetch("./feed.json", { cache: "no-store", credentials: "omit" });
    if (!response.ok) return;
    const next = await response.json();
    if (next.version !== 1 || next.updatedAt <= edition.updatedAt) return;
    edition = next;
    renderPublishers();
    render();
  } catch {
    // The current edition remains readable during an outage.
  }
}

if (window.matchMedia("(max-width: 760px)").matches) byId("filters").open = false;
byId("sources-button").addEventListener("click", () => sourcesDialog.showModal());
byId("close-sources").addEventListener("click", () => sourcesDialog.close());
byId("close-reader").addEventListener("click", () => reader.close());
byId("download").addEventListener("click", saveEdition);
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
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) {
    render();
    void checkForEdition();
  }
});
setInterval(() => {
  if (!document.hidden) {
    render();
    void checkForEdition();
  }
}, 5 * 60 * 1000);
renderPublishers();
render();
