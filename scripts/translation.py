"""Prepare simplified Chinese translations for readers without a browser API."""

from concurrent.futures import ThreadPoolExecutor
from hashlib import sha256
import json
import os
from pathlib import Path
import subprocess
from urllib.request import urlopen

PROVIDER = "mozilla-bergamot-en2.2-ja2.1-numbers"
MOZILLA_ASSETS = "https://firefox-settings-attachments.cdn.mozilla.net/main-workspace/"
# The glue and WebAssembly load together. Model versions match Firefox Remote Settings.
FILES = {
    "bergamot-translator.js": (
        "https://raw.githubusercontent.com/mozilla/gecko-dev/5836a062726f715fda621338a17b51aff30d0a8c/toolkit/components/translations/bergamot-translator/bergamot-translator.js",
        "972fa0450146fe06f4006a2ba56e8c4834403e27873cfe47fb3ba85aa7b9b082",
    ),
    "bergamot-translator.wasm": ("translations-wasm/05082c31-aee8-4249-9e01-c1865afd7520.wasm",
        "a3a89d9ad0a4ed8f27bf3e403701b23f5709816f6376438503f2fa5b0182c2dc"),
    "model.enzh.intgemm.alphas.bin": ("translations-models/a7ff7d5e-e67e-406c-a34b-a7edea35b10e.bin",
        "4e5accc141373565ddc8fa1565bceaa8d0c3482a82cab8131c719ebcc6c2157c"),
    "lex.50.50.enzh.s2t.bin": ("translations-models/da8fccc0-31df-4665-9703-96d36606e019.bin",
        "4a5e5827788060f1d718a8132b69440929387514a045796e9b77f935db68c055"),
    "srcvocab.enzh.spm": ("translations-models/ea98c52c-58dc-45d5-af23-38f2b029d020.spm",
        "bd9b65504acc6d9726dd281f7defc2adb7c2c22d0688fe2f84697de25197c8c5"),
    "trgvocab.enzh.spm": ("translations-models/bddbda68-d4d2-4317-a0a1-119caa47525e.spm",
        "aded6993c36e440284d11cec3f6b8aef9c0e43188a772d80be342a713adf223d"),
    "model.jaen.intgemm.alphas.bin": ("translations-models/2b066368-11b5-4cee-92e8-e6156b334f80.bin",
        "3a603e20bfe1be86071913f9e23ab5129075bc0a8490151020ac4821e4f17302"),
    "lex.50.50.jaen.s2t.bin": ("translations-models/4e6b3270-8a2f-491d-b717-f99749328622.bin",
        "525f412f0d210536c2933c78ae395fa0bf2b5ee6cc5dda61ebc2e79410ebaee4"),
    "vocab.jaen.spm": ("translations-models/6f4898e3-ebaa-4a79-a1af-93a4f65b96fa.spm",
        "5cb217758bae05877bb3f0c2f612e4e7c1e4cb03c10db11f4a47098d7ae62919"),
}


def ensure_asset(cache, name):
    url, digest = FILES[name]
    path = cache / name
    if path.is_file() and sha256(path.read_bytes()).hexdigest() == digest:
        return
    with urlopen(url if url.startswith("https://") else MOZILLA_ASSETS + url, timeout=75) as response:
        data = response.read(55 * 1024 * 1024)
    if sha256(data).hexdigest() != digest:
        raise ValueError(f"Invalid checksum for {name}")
    temporary = path.with_suffix(".download")
    temporary.write_bytes(data)
    temporary.replace(path)


def prepare_translations(articles):
    inputs = {"en": {}, "ja": {}}
    rows = []
    for article in articles:
        language = article["lang"]
        if language not in inputs or article.get("translation"):
            continue
        title = article.get("originalTitle", article["title"])
        summary = article.get("originalSummary", article["summary"])
        if not title:
            continue
        for text in (title, summary):
            if text:
                inputs[language].setdefault(text, len(inputs[language]))
        rows.append((article, language, title, summary))
    if not rows:
        return

    cache = Path(os.environ.get("FIELDNOTE_TRANSLATION_CACHE", Path.home() / ".cache" / "fieldnote-translation"))
    cache.mkdir(parents=True, exist_ok=True)
    asset_names = [name for name in FILES if inputs["ja"] or ".jaen." not in name]
    try:
        with ThreadPoolExecutor(max_workers=5) as pool:
            list(pool.map(lambda name: ensure_asset(cache, name), asset_names))
        # Give freshly published items their translations even if one model fails.
        output = {}
        for language, texts in inputs.items():
            if not texts:
                continue
            command = ["node", str(Path(__file__).with_name("bergamot.cjs")), str(cache)]
            batch = json.dumps({code: list(texts) if code == language else [] for code in inputs}, ensure_ascii=False)
            try:
                data = subprocess.run(command, input=batch, encoding="utf-8", capture_output=True, timeout=390, check=True)
                translated = json.loads(data.stdout)[language]
                if len(translated) != len(texts):
                    raise ValueError("Unexpected translation length")
                output[language] = translated
            except (OSError, subprocess.SubprocessError, ValueError, KeyError) as error:
                print(f"Mozilla translation unavailable for {language} ({type(error).__name__}).")
        for article, language, title, summary in rows:
            if language not in output:
                continue
            texts = output[language]
            translated_title = texts[inputs[language][title]].strip()
            translated_summary = texts[inputs[language][summary]].strip() if summary else ""
            if translated_title:
                article["translation"] = {
                    "provider": PROVIDER, "title": translated_title, "summary": translated_summary,
                }
        print(f"Mozilla translations prepared for {sum('translation' in row[0] for row in rows)} reports.")
    except (OSError, ValueError) as error:
        print(f"Mozilla translation assets unavailable ({type(error).__name__}).")
