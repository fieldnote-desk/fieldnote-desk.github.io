// Run Mozilla's WebAssembly distribution in the publisher, never in readers' tabs.
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { runInThisContext } = require('node:vm');

// The Japanese model sometimes reads “168万” as “168 million”.
function correctJapaneseTenThousands(original, pivot) {
  const source = original.normalize('NFKC');
  const counts = new Map();
  const numbers = /([\d,.]+)\s*(万億|万兆|万|億|兆)/gu;
  for (const match of source.matchAll(numbers)) {
    if (match[2] !== '万' || /[兆億万\d]/u.test(source[match.index - 1] ?? '')) continue;
    const number = Number(match[1].replaceAll(',', ''));
    if (!Number.isFinite(number) || number <= 0) continue;
    counts.set(number, `${number / 100} million`);
  }
  return pivot.replace(/([\d,.]+)\s*million\b/giu, (phrase, digits) => {
    const number = Number(digits.replaceAll(',', ''));
    if (counts.has(number * 100) || !counts.has(number)) return phrase;
    return ` ${counts.get(number)}`;
  });
}

async function main(directory) {
  const read = name => readFileSync(join(directory, name));
  const load = runInThisContext(read('bergamot-translator.js').toString() + '\nloadBergamot');
  const bergamot = await new Promise((resolve, reject) => {
    const module = load({
      wasmBinary: read('bergamot-translator.wasm'),
      INITIAL_MEMORY: 234291200,
      print: message => console.error(message),
      onAbort: reason => reject(new Error(String(reason))),
      onRuntimeInitialized: () => queueMicrotask(() => resolve(module)),
    });
  });
  function aligned(filename, alignment) {
    const file = read(filename);
    const buffer = new bergamot.AlignedMemory(file.length, alignment);
    buffer.getByteArrayView().set(file);
    return buffer;
  }
  function model(from, to, pair, vocabs) {
    const vocab = new bergamot.AlignedMemoryList();
    for (const file of vocabs) vocab.push_back(aligned(file, 64));
    const config = [
      'beam-size: 1', 'max-length-break: 128', 'mini-batch-words: 1024',
      'workspace: 128', 'max-length-factor: 2.0', 'skip-cost: true',
      'cpu-threads: 0', 'quiet: true', 'quiet-translation: true',
      'gemm-precision: int8shiftAlphaAll', 'alignment: soft',
    ].join('\n');
    return new bergamot.TranslationModel(
      from, to, config, aligned(`model.${pair}.intgemm.alphas.bin`, 256),
      aligned(`lex.50.50.${pair}.s2t.bin`, 64), vocab, null,
    );
  }

  const input = JSON.parse(readFileSync(0, 'utf8'));
  const service = new bergamot.BlockingService({ cacheSize: 0 });
  const english = model('en', 'zh-Hans', 'enzh', ['srcvocab.enzh.spm', 'trgvocab.enzh.spm']);
  const japanese = input.ja.length ? model('ja', 'en', 'jaen', ['vocab.jaen.spm']) : null;
  const output = { en: [], ja: [] };

  function translate(model, texts) {
    const messages = new bergamot.VectorString();
    const options = new bergamot.VectorResponseOptions();
    let replies;
    try {
      for (const text of texts) {
        messages.push_back(text);
        options.push_back({ qualityScores: false, alignment: true, html: false });
      }
      replies = service.translate(model, messages, options);
      const translated = [];
      for (let i = 0; i < replies.size(); i++) {
        const response = replies.get(i);
        try { translated.push(response.getTranslatedText()); }
        finally { response.delete(); }
      }
      return translated;
    } finally {
      replies?.delete();
      messages.delete();
      options.delete();
    }
  }

  for (const [language, texts] of Object.entries(input)) {
    for (let start = 0; start < texts.length; start += 24) {
      const batch = texts.slice(start, start + 24);
      const englishText = language === 'ja'
        ? translate(japanese, batch).map((pivot, i) => correctJapaneseTenThousands(batch[i], pivot))
        : batch;
      // A failed pivot can be empty; Bergamot requires a nonempty input.
      const translated = translate(english, englishText.map(text => text.trim() || '…'));
      output[language].push(...translated);
    }
  }
  process.stdout.write(JSON.stringify(output));
}

main(process.argv[2]).catch(error => {
  console.error(error);
  process.exitCode = 1;
});
