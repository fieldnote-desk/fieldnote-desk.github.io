"""Fetch approved publisher feeds and build the current seven-day edition."""

import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from email.utils import parsedate_to_datetime
from html import unescape
from html.parser import HTMLParser
import json
from pathlib import Path
import re
from urllib.error import HTTPError
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit
from urllib.request import Request, urlopen
from xml.etree.ElementTree import ParseError

from defusedxml import ElementTree
from defusedxml.common import DefusedXmlException
from opencc import OpenCC

from news_analysis import prepare_analyses

ROOT = Path(__file__).resolve().parents[1]
WINDOW = timedelta(days=7)
USER_AGENT = "FieldnoteDesk/1.0 (noncommercial RSS reader)"
ATOM = "{http://www.w3.org/2005/Atom}"
RSS1 = "{http://purl.org/rss/1.0/}"
CONTENT = "{http://purl.org/rss/1.0/modules/content/}encoded"
DC = "{http://purl.org/dc/elements/1.1/}"
SIMPLIFIED = OpenCC("t2s")
TOPICS = [
    ("港澳台", r"港澳|香港|澳门|マカオ|台湾|臺灣|台海|台湾海峡|两岸|台北|台积电|金门|澎湖|Taiwan|Taipei|Hong Kong|Macau|Macao|TSMC"),
    ("中国大陆", r"中国|中共|北京|习近平|中国共产党|中南海|新疆|西藏|人权|六四|中国外交|中国政府|解放军|南海|秦城|中国政府|中国共産党|習近平|China|Chinese|Beijing|Shanghai|Shenzhen|Xinjiang|Tibet|Xi Jinping|Uyghur|South China Sea"),
    ("中东", r"中东|以色列|伊朗|加沙|巴勒斯坦|黎巴嫩|叙利亚|伊拉克|约旦|也门|阿富汗|胡塞|土耳其|沙特|中东|霍尔木兹|中東|イスラエル|パレスチナ|イラン|レバノン|ヨルダン|シリア|イラク|トルコ|ホルムズ|Middle East|Israel|Gaza|Iran|Palestin|Lebanon|Syria|Iraq|Jordan|Yemen|Afghan|Houthi|Turkey|Turkish|Saudi|Hormuz"),
    ("欧洲", r"乌克兰|俄罗斯|普京|泽连斯基|莫斯科|基辅|北约|欧盟|欧洲|格鲁吉亚|波兰|德国|法国|英国|Ukraine|Russia|Moscow|Kyiv|Putin|Zelensky|NATO|European Union|Europe|Georgia|Poland|German|France|French|Britain|British|ウクライナ|ロシア|ゼレンスキー|プーチン|モスクワ|ドイツ|フランス|イギリス|欧州|London|Frankfurt|Spain|Italy|Brussels|\bECB\b|\bUK\b"),
    ("亚太", r"日本|韩国|朝鲜|印度|东盟|缅甸|菲律宾|新加坡|马来西亚|印尼|越南|泰国|环太|巴基斯坦|澳大利亚|新西兰|所罗门|南亚|印太|东亚|东南亚|フィリピン|シンガポール|パキスタン|インド|モンゴル|オーストラリア|Japan|Korea|India|Nikkei|Tokyo|Seoul|ASEAN|Myanmar|Philippines|Singapore|Malaysia|Indonesia|Vietnam|Thailand|Pakistan|Australia|New Zealand|Solomon|South Asia|Indo.Pacific|East Asia|Southeast Asia"),
    ("美洲", r"美国|华盛顿|国会山|白宫|特朗普|拜登|川普|加拿大|委内瑞拉|墨西哥|巴西|古巴|哥伦比亚|秘鲁|海地|阿根廷|Trump|Washington|White House|United States|U\.S\.|\bUS\b|Wall Street|Federal Reserve|\bFed\b|Nasdaq|米国|米大統領|トランプ|ホワイトハウス|カナダ|メキシコ|ブラジル|ベネズエラ|Canada|Venezuela|Mexico|Brazil|Cuba|Colombia|Peru|Haiti|Argentina"),
]
TOPICS = [(label, re.compile(pattern, re.I)) for label, pattern in TOPICS]
MAINLAND_PATTERN = dict(TOPICS)["中国大陆"]
NEWS = re.compile(
    r"政治|政府|议会|外交|国务院|选举|执政|军事|制裁|冲突|情报|诉讼|抗议|"
    r"芯片|军|贸易|关税|国安|禁令|逮捕|镇压|移民|恐袭|危机|灾难|援助|维和|人道|"
    r"联盟|抗战|监狱|法院|选举|部长|领导人|总统|峰会|安保|协议|航母|卫星|国债|"
    r"government|election|president|diplomac|sanction|conflict|military|politic|protest|"
    r"rescue|tariff|trade|security|parliament|minister|summit|court|aid|crisis|"
    r"defen[cs]e|Ceasefire|missile|strike|invasion|detention|arrest|rights|border|militia|"
    r"attack|refugee|nuclear|troops|visa|agrees|deal|agreement|semiconductor|export|"
    r"earthquake|flood|killed|hunger|famine|peace|elected|spy|spying|airspace|police",
    re.I,
)
LIGHT = re.compile(
    r"体育|娱乐|旅游指南|美食|影评|赛事|星座|游戏攻略|跑分|折扣|开箱|影剧|片单|食谱|"
    r"\b(?:football|soccer|cricket|premier league|horoscope|recipe|recipes|celebrity|reality show)\b",
    re.I,
)
JAPAN_CHUGOKU = re.compile(
    r"中国(?:地方|[運运][輸输]局|四国|[経经][済济][産产][業业]局|[電电]力|管区警察局|新聞|新闻)"
)
JAPAN_NEWS = re.compile(
    r"首相|官房長官|外相|防衛相|閣僚|国会|衆院|参院|衆議院|参議院|内閣|政府|政権|選挙|"
    r"外交|大統領|会談|首脳|条約|戦争|和平|核兵器|ミサイル|半導体|日銀|株価|相場|経済|関税|"
    r"輸出|貿易|物価|金利|日経平均|金融|景気|メガバンク|安全保障|通商|国防|防衛|海峡|制裁|停戦|"
    r"紛争|侵攻|災害|地震|テロ|サイバー攻撃|停戦|拘束|人権|裁判|会議|予算|自民|立憲|与党|野党|"
    r"解散|国連|原発|円安|円高|賃上げ|人事|決算|企業統治|市場|規制|国土交通|鉄道|交通政策",
)
FINANCE = re.compile(
    r"markets?|trade|tariffs?|inflation|GDP|econom|bank|bonds?|stocks?|shares?|securities|"
    r"corporate|companies|investment|jobs|currency|rates?|policy|pension|gold|crude|"
    r"treasur|housing|property|merger|earnings|semiconductor|chips?|revenue|funds?|"
    r"central bank|monetary|fiscal|ai boom|sales|retailers",
    re.I,
)
REGIONAL_PATHS = {
    "china": "中国大陆", "europe": "欧洲", "middle-east": "中东",
    "asia": "亚太", "americas": "美洲",
}
OPINION = re.compile(r"评论|專欄|专栏|观点|社论|社評|社评|\bopinion\b|\beditorial\b", re.I)
THIRD_PARTY = re.compile(
    r"all rights reserved|used with permission|republish(?:ed|ing)? (?:from|with)|"
    r"reposted from|produced in partnership|originally (?:published|appeared) "
    r"(?:on|at|by)(?!\s+(?:Global Voices|https?://[^ ]*globalvoices\.org))|"
    r"香港自由新聞|香港自由新闻|Hong Kong Free Press|共同發表|合作刊出|授權轉載|"
    r"授权转载|转载自|轉載自|原刊於|版权所有|版權所有",
    re.I,
)


class PlainText(HTMLParser):
    blocks = {"p", "div", "br", "li", "h1", "h2", "h3", "h4", "ul", "ol", "blockquote", "section", "table"}
    hidden = {"script", "style", "noscript", "iframe", "figure", "figcaption", "svg", "video", "audio", "aside", "footer"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
        self.ignored = []

    def handle_starttag(self, name, attrs):
        if name in self.hidden:
            self.ignored.append(name)
        elif not self.ignored and name in self.blocks:
            self.parts.append("\n")

    def handle_endtag(self, name):
        if self.ignored:
            if name == self.ignored[-1]:
                self.ignored.pop()
        elif name in self.blocks:
            self.parts.append("\n")

    def handle_data(self, data):
        if not self.ignored:
            self.parts.append(data)


def paragraphs(raw):
    parser = PlainText()
    parser.feed(raw)
    lines = [" ".join(line.split()) for line in unescape("".join(parser.parts)).splitlines()]
    return [line for line in lines if line]


def short_summary(raw, title, lang):
    lines = paragraphs(raw)
    useful = [
        line for line in lines if line != title and not re.match(
            r"^(continue reading|read more|click here|阅读全文|阅读更多|閱讀更多|The post )",
            line, re.I
        )
    ]
    text = " ".join(useful)
    limit = 170 if lang in {"zh", "ja"} else 235
    if len(text) <= limit:
        return text
    opening = text[:limit]
    ends = list(re.finditer(r"[。！？]|[.!?](?=\s|$)", opening))
    if ends and ends[-1].end() > limit * .45:
        return opening[:ends[-1].end()]
    if lang == "en":
        opening = opening.rsplit(" ", 1)[0]
    return opening.rstrip("，、,; ") + "…"


def read_url(url, limit, headers=None):
    request = Request(url, headers={"User-Agent": USER_AGENT, **(headers or {})})
    with urlopen(request, timeout=14) as response:
        data = response.read(limit + 1)
        if len(data) > limit:
            raise ValueError("response too large")
        return data


def clean_url(url, domains):
    try:
        parsed = urlsplit(url.strip())
        host = parsed.hostname
        port = parsed.port
    except ValueError:
        return ""
    if parsed.scheme not in {"https", "http"} or not host or parsed.username or parsed.password or port:
        return ""
    if not any(host == domain or host.endswith("." + domain) for domain in domains):
        return ""
    tracking = {"fbclid", "gclid", "ocid", "at_medium", "at_campaign", "cmp", "ref", "ICID", "guccounter", "maca", "ito", "mod", "srnd"}
    query = [(key, value) for key, value in parse_qsl(parsed.query) if not key.startswith("utm_") and key not in tracking]
    return urlunsplit(("https", host, parsed.path.rstrip("/") or "/", urlencode(sorted(query)), ""))


def field(item, *names):
    for name in names:
        element = item.find(name)
        if element is not None and element.text:
            return element.text.strip()
    return ""


def publication(item):
    raw = field(item, "pubDate", DC + "date", ATOM + "published", ATOM + "updated")
    if not raw:
        return None
    try:
        timestamp = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        try:
            timestamp = parsedate_to_datetime(raw)
        except (ValueError, TypeError, OverflowError):
            return None
    return timestamp.replace(tzinfo=timestamp.tzinfo or timezone.utc).astimezone(timezone.utc)


def atom_link(item):
    for link in item.findall(ATOM + "link"):
        if link.get("rel", "alternate") == "alternate":
            return link.get("href", "")
    return ""


def full_text(source, item, title):
    license_kind = source.get("full")
    if not license_kind:
        return None
    raw = field(item, CONTENT)
    author = field(item, "author", DC + "creator")
    if not raw or not author or len(raw) > 120000:
        return None
    body = paragraphs(raw)
    if len(body) < 3 or sum(map(len, body)) < 300:
        return None

    if license_kind == "rfa":
        if not re.match(r"^(?:記者|记者|本台记者|本台記者)", author):
            return None
        if THIRD_PARTY.search(" ".join(body)):
            return None
        return {
            "body": body, "byline": author, "title": title,
            "credit": "Copyright © 1998-2023, RFA.\nUsed with the permission of Radio Free Asia,\n2025 M St. NW, Suite 300, Washington, D.C. 20036.\nhttps://www.rfa.org.",
            "license": source["terms"], "licenseLabel": "RFA 转载条款",
        }

    if THIRD_PARTY.search(" ".join(body)) or THIRD_PARTY.search(author):
        return None
    # Partner content can carry its own restrictions even on the same feed.
    if re.search(r"partner|repost|syndicat|license-notice|copyright-notice", raw, re.I):
        return None
    return {
        "body": body, "byline": author, "title": title,
        "credit": "本文原刊于 Global Voices。保留原语种文字，改为纯文本排版并省略媒体附件。",
        "license": "https://creativecommons.org/licenses/by/3.0/", "licenseLabel": "CC BY 3.0",
    }


def to_article(source, item, now):
    if source.get("requiredAuthor") and field(item, "author", DC + "creator").casefold() != source["requiredAuthor"].casefold():
        return None
    url = clean_url(field(item, "link", RSS1 + "link") or atom_link(item), source["domains"])
    date = publication(item)
    raw_title = field(item, "title", RSS1 + "title", ATOM + "title")
    title = " ".join(paragraphs(raw_title))[:400]
    if not url or not date or not title or not now - WINDOW <= date <= now + timedelta(minutes=15):
        return None
    raw_summary = field(item, "description", RSS1 + "description", ATOM + "summary")
    summary = short_summary(raw_summary, title, source["lang"])

    category = " ".join(tag.text or "" for tag in item.findall("category"))
    simplified_title = SIMPLIFIED.convert(title)
    simplified_summary = SIMPLIFIED.convert(summary)
    classification = simplified_title + " " + simplified_summary + " " + SIMPLIFIED.convert(category)
    topic_title = simplified_title
    if source["lang"] == "ja":
        # 中国地方 is Chugoku in western Japan. Keep its name intact in the display.
        topic_title = JAPAN_CHUGOKU.sub("日本西部", topic_title)
        classification = JAPAN_CHUGOKU.sub("日本西部", classification)
    matched = [topic for topic, pattern in TOPICS if pattern.search(topic_title)]
    segments = urlsplit(url).path.split("/")
    if source["id"] == "wsj" and len(segments) > 2 and segments[1] == "world":
        section = REGIONAL_PATHS.get(segments[2])
        if section and section not in matched:
            matched.insert(0, section)
    matched += [topic for topic, pattern in TOPICS if topic not in matched and pattern.search(classification)]
    priority = bool(set(matched) & {"中国大陆", "港澳台", "中东", "欧洲"})
    if source.get("internationalOnly") and not matched:
        return None
    if source["lang"] != "ja" and LIGHT.search(simplified_title) and not NEWS.search(simplified_title):
        return None
    if source["scope"] == "日本":
        if not (JAPAN_NEWS.search(title + " " + summary + " " + category) or priority):
            return None
        if not matched:
            matched = ["亚太"]
    elif source["scope"] == "财经":
        if not (priority or NEWS.search(classification) or FINANCE.search(classification)):
            return None
    elif not NEWS.search(classification) and not priority:
        if source["scope"] != "国际" or not matched or LIGHT.search(classification):
            return None

    article = {
        "url": url, "publishedAt": iso(date), "source": source["id"],
        "title": simplified_title, "summary": simplified_summary, "topics": matched[:3] or ["国际"],
        "kind": "评论" if OPINION.search(simplified_title + " " + category) else "报道",
        "lang": source["lang"], "originalTitle": title, "originalSummary": summary,
    }
    revised = field(item, "lastUpdated", ATOM + "updated")
    if revised:
        article["updatedBySource"] = revised
    body = full_text(source, item, title)
    if body:
        article["full"] = body
    return article


def fetch_source(source, url, now):
    try:
        root = ElementTree.fromstring(read_url(url, 8 * 1024 * 1024))
        if root.tag == ATOM + "feed":
            items = root.findall(ATOM + "entry")
        elif root.tag == "rss":
            items = root.findall("./channel/item")
        elif root.tag.endswith("}RDF"):
            items = [item for item in root if item.tag.endswith("}item")]
        else:
            raise ValueError("unrecognized feed")
        articles = [article for item in items if (article := to_article(source, item, now))]
        if source["scope"] == "日本":
            articles = sorted(articles, key=lambda article: article["publishedAt"], reverse=True)[:35]
        newest = max((date for item in items if (date := publication(item))), default=None)
        return source["id"], url, articles, newest, None
    except (OSError, ValueError, ParseError, DefusedXmlException) as error:
        if isinstance(error, HTTPError):
            reason = f"HTTP {error.code}"
        elif isinstance(error, TimeoutError):
            reason = "请求超时"
        else:
            reason = "暂不可用"
        return source["id"], url, [], None, reason


def iso(value):
    return value.isoformat(timespec="seconds").replace("+00:00", "Z")


def previous_edition(url, path):
    if path:
        return json.loads(path.read_text(encoding="utf-8"))
    if not url:
        return {}
    try:
        return json.loads(read_url(url, 18 * 1024 * 1024, {"Cache-Control": "no-cache"}))
    except HTTPError as error:
        if error.code == 404:
            return {}
        raise


def make_edition(sources, previous, now):
    source_by_id = {source["id"]: source for source in sources}
    timeline = {}
    for article in previous.get("items", []):
        source = source_by_id.get(article["source"])
        if source and now - WINDOW <= datetime.fromisoformat(article["publishedAt"]) <= now + timedelta(minutes=15):
            if not source.get("full"):
                article.pop("full", None)
            old_topics = {"中国政治": "中国大陆", "俄乌与欧洲": "欧洲"}
            article["topics"] = [old_topics.get(topic, topic) for topic in article.get("topics", [])]
            if article.get("lang") == "ja" and "中国大陆" in article["topics"]:
                original = (article.get("originalTitle", "") + " " + article.get("originalSummary", ""))
                topic_text = JAPAN_CHUGOKU.sub("日本西部", SIMPLIFIED.convert(original))
                if JAPAN_CHUGOKU.search(SIMPLIFIED.convert(original)) and not MAINLAND_PATTERN.search(topic_text):
                    article["topics"] = [topic for topic in article["topics"] if topic != "中国大陆"] or ["亚太"]
            article.pop("translation", None)
            timeline[article["url"]] = article
    jobs = [(source, url, now) for source in sources for url in source["feeds"]]
    health = {source["id"]: [] for source in sources}
    fetched = {}
    with ThreadPoolExecutor(max_workers=10) as pool:
        for source, url, articles, newest, error in pool.map(lambda args: fetch_source(*args), jobs):
            health[source].append({"feed": url, "newestAt": iso(newest) if newest else None, "error": error})
            for article in articles:
                key = article["url"]
                # The same publisher may include the same link in several sections.
                if key in fetched:
                    prior = fetched[key]
                    prior["topics"] = list(dict.fromkeys(prior["topics"] + article["topics"]))[:3]
                    continue
                fetched[key] = article
    for key, article in fetched.items():
        previous_article = timeline.get(key, {})
        if (
            previous_article.get("originalTitle") == article["originalTitle"]
            and previous_article.get("originalSummary", previous_article.get("summary")) == article["originalSummary"]
            and previous_article.get("full") == article.get("full")
            and previous_article.get("analysis")
        ):
            article["analysis"] = previous_article["analysis"]
        timeline[key] = article
    ordered = sorted(timeline.values(), key=lambda row: (row["publishedAt"], row["url"]), reverse=True)
    prepare_analyses(ordered)
    visible_sources = [
        {key: source[key] for key in ("id", "name", "region", "site", "lang", "terms", "credit", "full") if key in source}
        | {"health": health[source["id"]]} for source in sources
    ]
    return {"version": 1, "updatedAt": iso(now), "windowDays": WINDOW.days, "items": ordered, "sources": visible_sources}


def build_site(edition, output, page_name="offline.html"):
    output.mkdir(parents=True, exist_ok=True)
    base = ROOT / "site"
    data = json.dumps(edition, ensure_ascii=False, separators=(",", ":"))
    (output / "feed.json").write_text(data, encoding="utf-8")
    html = (base / "index.html").read_text(encoding="utf-8")
    css = (base / "style.css").read_text(encoding="utf-8")
    js = (base / "app.js").read_text(encoding="utf-8")
    safe = data.replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")
    html = html.replace("<!--STYLE-->", f"<style>{css}</style>")
    html = html.replace("<!--DATA-->", f'<script id="edition" type="application/json">{safe}</script>')
    html = html.replace("<!--SCRIPT-->", f"<script>{js}</script>")
    (output / page_name).write_text(html, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    parser.add_argument("--previous", type=Path)
    parser.add_argument("--previous-url")
    args = parser.parse_args()
    sources = json.loads((ROOT / "sources.json").read_text(encoding="utf-8"))
    previous = previous_edition(args.previous_url, args.previous)
    edition = make_edition(sources, previous, datetime.now(timezone.utc))
    healthy = sum(any(not feed["error"] for feed in source["health"]) for source in edition["sources"])
    if healthy == 0 and not previous:
        raise SystemExit("No publisher feed responded, so there is no edition to publish.")
    build_site(edition, args.output)
    print(f"{len(edition['items'])} articles; {healthy}/{len(sources)} publisher groups responded.")


if __name__ == "__main__":
    main()
