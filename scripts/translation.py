"""Translate published titles and summaries through Google Cloud Translation Basic."""

from html import unescape
import json
from urllib.request import Request, urlopen

GOOGLE_TRANSLATE = "https://translation.googleapis.com/language/translate/v2"


def google_translate(texts, key):
    payload = json.dumps({"q": texts, "source": "en", "target": "zh-CN", "format": "text"})
    request = Request(
        GOOGLE_TRANSLATE, data=payload.encode("utf-8"),
        headers={"Content-Type": "application/json", "X-Goog-Api-Key": key},
    )
    with urlopen(request, timeout=15) as response:
        items = json.load(response)["data"]["translations"]
    if len(items) != len(texts):
        raise ValueError("Unexpected translation response length")
    return [unescape(item["translatedText"]) for item in items]


def translate_english(items, key, budget):
    if not key or budget <= 0:
        return
    selected = []
    remaining = budget
    for item in items:
        if item["lang"] != "en" or item.get("translation"):
            continue
        title = item.get("originalTitle", item["title"])
        summary = item.get("originalSummary", item["summary"])
        length = len(title) + len(summary)
        if length <= remaining:
            selected.append((item, title, summary))
            remaining -= length
    try:
        for start in range(0, len(selected), 40):
            batch = selected[start:start + 40]
            texts = [text for _, title, summary in batch for text in (title, summary) if text]
            translated = iter(google_translate(texts, key))
            for item, original_title, original_summary in batch:
                title = next(translated) if original_title else ""
                summary = next(translated) if original_summary else ""
                if title:
                    item["translation"] = {"provider": "google", "title": title, "summary": summary}
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Google Cloud Translation unavailable ({type(error).__name__}); retaining originals.")
