import fs from 'fs';
import path from 'path';
import ptBR from 'dashboard/i18n/locale/pt_BR/inboxWidget.json';
import en from 'dashboard/i18n/locale/en/inboxWidget.json';
import {
  APPROACHES,
  DEVICES,
  TRIGGER_IDS,
  URL_OPERATORS,
} from '../../composables/widgetTriggersContract';

/**
 * As chaves montadas em tempo de execucao (`ITEMS.${id}`, `APPROACH.${nivel}`)
 * nao caem no grep de `$t()`; sao verificadas nominalmente aqui, nos dois
 * idiomas — pt-BR e prioridade e `en` nao pode ficar para tras.
 *
 * E o ultimo teste deste arquivo executa um aceite que e POLITICA, nao estilo.
 */
const buscar = (arvore, chaveComPontos) =>
  chaveComPontos.split('.').reduce((no, parte) => no?.[parte], arvore);

const arquivosDaTela = () => {
  const dir = path.resolve(
    process.cwd(),
    'app/javascript/dashboard/routes/dashboard/settings/inbox/widget/triggers'
  );
  const acc = [];
  const percorre = atual =>
    fs.readdirSync(atual, { withFileTypes: true }).forEach(entrada => {
      const completo = path.join(atual, entrada.name);
      if (entrada.isDirectory()) {
        if (entrada.name !== 'specs') percorre(completo);
      } else if (/\.(vue|js)$/.test(entrada.name)) {
        acc.push(completo);
      }
    });
  percorre(dir);
  return acc;
};

describe('i18n da tela de gatilhos', () => {
  it.each(TRIGGER_IDS)(
    'o gatilho %s tem rótulo e explicação nos dois idiomas',
    id => {
      ['LABEL', 'HINT', 'UNIT'].forEach(campo => {
        const chave = `TRIGGERS.ITEMS.${id.toUpperCase()}.${campo}`;
        expect(buscar(ptBR.INBOX_WIDGET, chave)).toBeTypeOf('string');
        expect(buscar(en.INBOX_WIDGET, chave)).toBeTypeOf('string');
      });
    }
  );

  // A abordagem vive no namespace APPROACH, que a trilha do backend declarou
  // junto do schema de 3.20 — esta tela e a consumidora, e nao criou um segundo.
  it.each(APPROACHES)(
    'o nível %s tem nome E descrição nos dois idiomas',
    nivel => {
      ['LABEL', 'DESCRIPTION'].forEach(campo => {
        const chave = `APPROACH.LEVELS.${nivel.toUpperCase()}.${campo}`;
        expect(buscar(ptBR.INBOX_WIDGET, chave)).toBeTypeOf('string');
        expect(buscar(en.INBOX_WIDGET, chave)).toBeTypeOf('string');
      });
    }
  );

  it.each(URL_OPERATORS)(
    'o operador %s tem rótulo nos dois idiomas',
    operador => {
      const chave = `TRIGGERS.AUDIENCE.OPERATORS.${operador.toUpperCase()}`;
      expect(buscar(ptBR.INBOX_WIDGET, chave)).toBeTypeOf('string');
      expect(buscar(en.INBOX_WIDGET, chave)).toBeTypeOf('string');
    }
  );

  it.each(DEVICES)('o dispositivo %s tem rótulo nos dois idiomas', device => {
    const chave = `TRIGGERS.AUDIENCE.DEVICES.${device.toUpperCase()}`;
    expect(buscar(ptBR.INBOX_WIDGET, chave)).toBeTypeOf('string');
    expect(buscar(en.INBOX_WIDGET, chave)).toBeTypeOf('string');
  });

  it('toda chave escrita nos componentes existe nos dois idiomas', () => {
    const usadas = new Set();
    arquivosDaTela().forEach(arquivo => {
      const conteudo = fs.readFileSync(arquivo, 'utf8');
      [...conteudo.matchAll(/['"`](INBOX_WIDGET\.[A-Z0-9_.]+)['"`]/g)].forEach(
        ([, chave]) => usadas.add(chave)
      );
    });

    expect(usadas.size).toBeGreaterThan(20);
    const faltando = [...usadas].filter(chave => {
      const relativa = chave.replace(/^INBOX_WIDGET\./, '');
      return (
        typeof buscar(ptBR.INBOX_WIDGET, relativa) !== 'string' ||
        typeof buscar(en.INBOX_WIDGET, relativa) !== 'string'
      );
    });

    expect(faltando).toEqual([]);
  });

  /**
   * ACEITE DE POLITICA (bloco 4.20), nao de estilo: o texto do aviso do nivel
   * Agressivo **nao menciona penalizacao de buscador**. E decisao de produto
   * tomada — o motivo que a tela da e o do VISITANTE (o painel cobre o que ele
   * lia), nao o do ranking. Quem for "melhorar" o texto acrescentando isso
   * derruba este teste.
   */
  it('nenhuma string desta tela menciona buscador — decisão de produto do 4.20', () => {
    const secoes = [
      ptBR.INBOX_WIDGET.TRIGGERS,
      en.INBOX_WIDGET.TRIGGERS,
      ptBR.INBOX_WIDGET.APPROACH,
      en.INBOX_WIDGET.APPROACH,
    ];
    const textos = [];
    const colher = no => {
      if (typeof no === 'string') textos.push(no);
      else if (no && typeof no === 'object') Object.values(no).forEach(colher);
    };
    secoes.forEach(colher);

    expect(textos.length).toBeGreaterThan(50);
    expect(textos.filter(texto => /google|seo|ranking/i.test(texto))).toEqual(
      []
    );
  });
});
