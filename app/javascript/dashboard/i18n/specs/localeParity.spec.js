import fs from 'fs';
import path from 'path';

// Sem `fallbackLocale` configurado (ver entrypoints/dashboard.js), o vue-i18n cai no
// proprio `locale: 'en'`. Consequencia pratica das lacunas:
//   - chave que falta no pt_BR  -> usuario brasileiro le TEXTO EM INGLES
//   - chave que falta no en     -> usuario ingles le a CHAVE CRUA na tela
// Este spec trava as duas. Em 21/08/2026 havia 104 faltando no pt_BR e 21 no en.

const RAIZ = path.resolve(
  process.cwd(),
  'app/javascript/dashboard/i18n/locale'
);

const leJson = filePath => JSON.parse(fs.readFileSync(filePath, 'utf-8'));

const achata = (valor, prefixo = '', chaves = []) => {
  if (!valor || typeof valor !== 'object') {
    if (prefixo) chaves.push(prefixo);
    return chaves;
  }
  Object.entries(valor).forEach(([chave, aninhado]) => {
    achata(aninhado, prefixo ? `${prefixo}.${chave}` : chave, chaves);
  });
  return chaves;
};

const arquivosEn = fs
  .readdirSync(path.join(RAIZ, 'en'))
  .filter(f => f.endsWith('.json'))
  .sort();

describe('paridade de chaves entre en e pt_BR', () => {
  it('tem os mesmos arquivos de locale nos dois idiomas', () => {
    const arquivosPt = fs
      .readdirSync(path.join(RAIZ, 'pt_BR'))
      .filter(f => f.endsWith('.json'))
      .sort();
    expect(arquivosPt).toEqual(arquivosEn);
  });

  it.each(arquivosEn)('%s: nenhuma chave do en falta no pt_BR', arquivo => {
    const en = achata(leJson(path.join(RAIZ, 'en', arquivo)));
    const pt = new Set(achata(leJson(path.join(RAIZ, 'pt_BR', arquivo))));
    const faltando = en.filter(k => !pt.has(k));
    expect(faltando).toEqual([]);
  });

  it.each(arquivosEn)('%s: nenhuma chave do pt_BR falta no en', arquivo => {
    const pt = achata(leJson(path.join(RAIZ, 'pt_BR', arquivo)));
    const en = new Set(achata(leJson(path.join(RAIZ, 'en', arquivo))));
    const faltando = pt.filter(k => !en.has(k));
    expect(faltando).toEqual([]);
  });
});
