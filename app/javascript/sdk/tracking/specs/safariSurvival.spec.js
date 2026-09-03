/**
 * Bloco 5.08 — ACEITE, segunda metade: *"no Safari, 7+ dias depois, a origem SOBREVIVE"*.
 *
 * O QUE ESSE "7 DIAS" É. O ITP do Safari **limita a 7 dias** a validade de cookie escrito
 * por JavaScript (`document.cookie`). Qualquer coletor que guarde a origem em cookie perde
 * a campanha do visitante que volta na segunda semana — e é assim que boa parte do mercado
 * guarda.
 *
 * A NOSSA DECISÃO, e é o que este spec cobra: **a origem não depende de cookie nenhum**.
 * Ela mora em `localStorage`, que o ITP não corta em 7 dias, e o coletor lê cookie apenas
 * para ENRIQUECER (`_fbp`, `_fbc`, `_ga`) — nunca como fonte da origem.
 *
 * O teste modela o efeito do ITP do jeito que ele se manifesta: **os cookies somem**. É o
 * que se pode medir de forma determinística; o comportamento do navegador em si não se
 * simula, e fingir que se simula seria pior que não testar.
 *
 * LIMITAÇÃO DECLARADA: o ITP também pode apagar `localStorage` após 7 dias sem interação
 * quando classifica o site como rastreador. Isso vale para o site DO CLIENTE avaliado
 * contra o próprio visitante, e não está sob nosso controle. Quando acontecer, a origem
 * se perde — e a única defesa real seria persistir no servidor antes de a conversa existir,
 * que é outro bloco (4.18 fez isso para o lead incompleto).
 */
import { captureOrigin, storedOrigin } from '../capture';
import { originAttributes } from '../index';
import { STORE_KEY } from '../keys';

const OITO_DIAS = 8 * 24 * 60 * 60 * 1000;

const chegarPorAnuncio = () =>
  captureOrigin({
    location: {
      search: '?utm_source=google&utm_campaign=black-friday&gclid=Cj0KCQ',
      host: 'loja.com.br',
      origin: 'https://loja.com.br',
      pathname: '/promo',
    },
    referrer: 'https://www.google.com/',
  });

/** O que o ITP faz aos 7 dias: o cookie escrito por JS deixa de existir. */
const itpApagaCookies = () => {
  document.cookie.split(';').forEach(par => {
    const nome = par.split('=')[0].trim();
    if (nome)
      document.cookie = `${nome}=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/`;
  });
};

describe('5.08 — a origem sobrevive 7+ dias no Safari', () => {
  beforeEach(() => {
    window.localStorage.clear();
    itpApagaCookies();
  });

  it('oito dias depois, sem cookie nenhum, a conversa ainda nasce com a campanha certa', async () => {
    chegarPorAnuncio();
    document.cookie = '_fbp=fb.1.100.200';

    // Passam oito dias: o ITP apagou o cookie que o Pixel tinha escrito.
    itpApagaCookies();
    const depois = Date.now() + OITO_DIAS;

    const attrs = await originAttributes({ host: 'loja.com.br', now: depois });

    expect(attrs.first_utm_source).toBe('google');
    expect(attrs.first_utm_campaign).toBe('black-friday');
    expect(attrs.first_gclid).toBe('Cj0KCQ');
    expect(attrs.first_landing_page).toBe('https://loja.com.br/promo');
    // O enriquecimento por cookie sumiu junto com o cookie — e é só ele que some.
    expect(attrs.fbp).toBeUndefined();
  });

  it('a origem NÃO é lida de cookie: apagar todos os cookies não muda o registro', () => {
    chegarPorAnuncio();
    const antes = JSON.stringify(storedOrigin());

    itpApagaCookies();

    expect(JSON.stringify(storedOrigin())).toBe(antes);
  });

  it('o registro não tem validade própria — nada nosso o expira em 7 dias', () => {
    chegarPorAnuncio();

    const guardado = JSON.parse(window.localStorage.getItem(STORE_KEY));

    expect(guardado.first.ts).toEqual(expect.any(Number));
    // Nenhum campo de expiração: quem apaga é o navegador, nunca uma regra nossa que
    // ninguém pediu.
    expect(Object.keys(guardado)).toEqual(['last', 'first']);
    expect(guardado.first.expires).toBeUndefined();
  });

  it('oito dias depois o `_gcl_aw` ainda deriva — a janela do Google é de 90 dias, não 7', async () => {
    chegarPorAnuncio();

    const attrs = await originAttributes({
      host: 'loja.com.br',
      now: Date.now() + OITO_DIAS,
    });

    expect(attrs.gcl_aw).toMatch(/^GCL\.\d+\.Cj0KCQ$/);
  });
});
