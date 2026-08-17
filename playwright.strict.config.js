// INSTRUMENTO DE MEDIÇÃO — não faz parte da suíte, é descartado após o uso.
//
// Reaproveita integralmente o playwright.config.js do repositório e APERTA um único
// parâmetro: a tolerância de pixel do toHaveScreenshot passa de maxDiffPixelRatio 0.01
// para maxDiffPixels 0 (zero pixels de diferença admitidos).
//
// Motivo: a suíte passou 20/20 com a tolerância padrão, mas o merge alterou
// App.vue (container raiz ganhou `bg-n-slate-2 dark:bg-n-solid-1`). Com 1% de folga
// num quadro de ~400x600 cabem ~2400 pixels alterados sem que o teste acuse nada.
// Para responder "o merge muda o widget?" com um número, e não com um "passou",
// é preciso saber se a diferença é ZERO ou apenas menor que a folga.
//
// Isto NÃO afrouxa o aceite — endurece. O aceite oficial continua sendo o
// playwright.config.js do repositório.
const base = require('./playwright.config.js');

module.exports = {
  ...base,
  expect: {
    ...base.expect,
    toHaveScreenshot: {
      ...base.expect.toHaveScreenshot,
      maxDiffPixelRatio: undefined,
      maxDiffPixels: 0,
      threshold: 0,
    },
  },
};
