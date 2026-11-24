"""Optional local English-to-Chinese translation using the Argos model."""

import hashlib
import shutil
from urllib.request import Request, urlopen
from zipfile import ZipFile

MODEL_URL = "https://argos-net.com/v1/translate-en_zh-1_9.argosmodel"
MODEL_HASH = "433e7c4f034d87fbe2353161e05f18646d7999452f801a4e1f0378522b9850ab"
MODEL_DIRECTORY = "translate-en_zh-1_9"


def install(directory):
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / MODEL_DIRECTORY
    if (target / "model" / "model.bin").is_file() and (target / "sentencepiece.model").is_file():
        return target
    archive = directory / "model.download"
    try:
        request = Request(MODEL_URL, headers={"User-Agent": "FieldnoteDesk/1.0"})
        with urlopen(request, timeout=30) as response, archive.open("wb") as output:
            shutil.copyfileobj(response, output)
        with archive.open("rb") as contents:
            if hashlib.file_digest(contents, "sha256").hexdigest() != MODEL_HASH:
                raise ValueError("The translation model checksum differs from the pinned release")
        with ZipFile(archive) as package:
            package.extractall(directory)
    finally:
        archive.unlink(missing_ok=True)
    return target


class Translator:
    def __init__(self, directory):
        import ctranslate2
        import sentencepiece

        model = install(directory)
        self.tokens = sentencepiece.SentencePieceProcessor(
            model_file=str(model / "sentencepiece.model")
        )
        self.model = ctranslate2.Translator(
            str(model / "model"), device="cpu", compute_type="int8", intra_threads=2
        )

    def translate(self, text):
        encoded = self.tokens.encode(text, out_type=str)
        results = self.model.translate_batch(
            encoded, beam_size=2, max_batch_size=24, max_decoding_length=175
        )
        return [self.tokens.decode(result.hypotheses[0]) for result in results]
