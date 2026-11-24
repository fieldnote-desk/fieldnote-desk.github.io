// Run Mozilla's WebAssembly distribution in the publisher, never in readers' tabs.
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { runInThisContext } = require('node:vm');

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

  for (const [language, texts] of Object.entries(input)) {
    for (let start = 0; start < texts.length; start += 24) {
      const messages = new bergamot.VectorString();
      const options = new bergamot.VectorResponseOptions();
      let replies;
      try {
        for (const text of texts.slice(start, start + 24)) {
          messages.push_back(text);
          options.push_back({ qualityScores: false, alignment: true, html: false });
        }
        replies = language === 'ja'
          ? service.translateViaPivoting(japanese, english, messages, options)
          : service.translate(english, messages, options);
        for (let i = 0; i < replies.size(); i++) {
          const response = replies.get(i);
          try { output[language].push(response.getTranslatedText()); }
          finally { response.delete(); }
        }
      } finally {
        replies?.delete();
        messages.delete();
        options.delete();
      }
    }
  }
  process.stdout.write(JSON.stringify(output));
}

main(process.argv[2]).catch(error => {
  console.error(error);
  process.exitCode = 1;
});
