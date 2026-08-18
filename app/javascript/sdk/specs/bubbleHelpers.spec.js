/**
 * MECANISMO DE ACEITE DO BLOCO 3.19 — a metade W (o SDK).
 *
 * Das nove asserções do bloco, este arquivo executa as CINCO que vivem no SDK:
 *   (5) `preload`/`fetchpriority` garantem que o lançador não pisque vazio
 *   (6) `onerror` volta ao `bubbleSVG` — 404 na foto nunca deixa o site sem canal
 *   (7) anel derivado de `--w-brand-border`, ≥ 3:1 (SC 1.4.11)
 *   (8) recorte `object-fit: cover` no círculo de 64 px congelado (§8 item 2)
 *   (9) nome acessível traduzido, nunca o `'Open chat window'` de hoje
 *
 * As asserções 1–4 (default de fábrica na criação da inbox, aviso na tela de aparência,
 * teto de 20 KB no upload, byte servido do nosso domínio) dependem de 3.18/3.09 e estão
 * registradas como BLOQUEADAS no relatório — não há mecanismo aqui porque não há código
 * delas aqui, e um teste que fingisse cobri-las seria pior que a ausência.
 */
import {
  bubbleSVG,
  chatBubble,
  closeBubble,
  createBubbleIcon,
  preloadLauncherImage,
  resolveLauncherIcon,
  setBubbleAccessibleName,
} from '../bubbleHelpers';
import { IFrameHelper } from '../IFrameHelper';
import { SDK_CSS } from '../sdk';

// ── contraste WCAG, calculado aqui e só aqui ────────────────────────────────
// Vive no teste, não na produção: o aceite de 1.03 proíbe fórmula de contraste em JS
// de runtime. Aqui ela serve para MEDIR um design estático, que é o que a asserção 7 pede.
const channelLuminance = c => {
  const s = c / 255;
  return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
};

const relativeLuminance = ([r, g, b]) =>
  0.2126 * channelLuminance(r) +
  0.7152 * channelLuminance(g) +
  0.0722 * channelLuminance(b);

const contrastRatio = (a, b) => {
  const [hi, lo] = [relativeLuminance(a), relativeLuminance(b)].sort(
    (x, y) => y - x
  );
  return (hi + 0.05) / (lo + 0.05);
};

/** Compõe uma cor com alfa sobre um fundo opaco — o anel externo é rgba(). */
const over = ([r, g, b, alpha], [br, bg, bb]) => [
  alpha * r + (1 - alpha) * br,
  alpha * g + (1 - alpha) * bg,
  alpha * b + (1 - alpha) * bb,
];

const WHITE = [255, 255, 255];
const BRAND = [45, 196, 111]; // #2dc46f — a cor da marca (default unificado no bloco 0.8)
const DARK_PAGE = [23, 23, 23]; // um fundo escuro plausível de página de cliente
const RING_INNER = WHITE; // var(--w-brand-border, #ffffff)
const RING_OUTER = [0, 0, 0, 0.55]; // rgba(0, 0, 0, 0.55)

describe('3.19 (metade W) — o ícone do lançador deixa de ser um path fixo', () => {
  beforeEach(() => {
    window.$chatwoot = { position: 'right', type: 'standard' };
    document.head.innerHTML = '';
  });

  const freshButton = () => document.createElement('button');

  // ─────────────────────────────────────────────────────────────────────────
  describe('resolveLauncherIcon — o contrato com 3.18', () => {
    it('sem widget_appearance resolve para `default` (3.18 ainda não entregou)', () => {
      expect(resolveLauncherIcon({})).toMatchObject({
        mode: 'default',
        src: null,
      });
      expect(resolveLauncherIcon()).toMatchObject({ mode: 'default' });
    });

    it('aceita o modo como string — a forma mais provável do schema', () => {
      expect(
        resolveLauncherIcon({ widgetAppearance: { launcher_icon: 'default' } })
          .mode
      ).toBe('default');
    });

    it('aceita o modo como objeto {mode, url}', () => {
      expect(
        resolveLauncherIcon({
          widgetAppearance: {
            launcher_icon: { mode: 'image', url: '/rails/blob/marina.webp' },
          },
        })
      ).toMatchObject({ mode: 'image', src: '/rails/blob/marina.webp' });
    });

    it('`agent_photo` reusa o avatarUrl da inbox, sem upload novo', () => {
      expect(
        resolveLauncherIcon({
          avatarUrl: 'https://app.chatspx.com.br/avatar/marina.png',
          widgetAppearance: { launcher_icon: 'agent_photo' },
        })
      ).toMatchObject({
        mode: 'agent_photo',
        src: 'https://app.chatspx.com.br/avatar/marina.png',
      });
    });

    it('modo desconhecido, `image` sem URL e `agent_photo` sem avatar caem em `default`', () => {
      expect(
        resolveLauncherIcon({ widgetAppearance: { launcher_icon: 'gif' } }).mode
      ).toBe('default');
      expect(
        resolveLauncherIcon({ widgetAppearance: { launcher_icon: 'image' } })
          .mode
      ).toBe('default');
      expect(
        resolveLauncherIcon({
          widgetAppearance: { launcher_icon: 'agent_photo' },
        }).mode
      ).toBe('default');
    });
  });

  // ── ASSERÇÃO 9 ───────────────────────────────────────────────────────────
  //
  // REESCRITA NO MERGE COM O 1.06, e vale dizer por quê. A versão original deste
  // bloco traduzia o nome no próprio SDK, com uma tabela de 4 locales. O 1.06
  // trouxe algo melhor: a string atravessa a ponte já traduzida, vinda do painel,
  // que tem 40 locales. A tabela foi APAGADA — duas fontes de i18n divergem, é só
  // questão de tempo.
  //
  // O que a asserção 9 exige de verdade é que o nome acessível que o visitante
  // recebe seja traduzido, e não o inglês cravado. Quem entrega isso agora é a
  // ponte. Estes testes cobrem a ponte, a precedência e o provisório.
  describe('asserção 9 — nome acessível traduzido', () => {
    it('o SDK NÃO carrega tabela de tradução própria — a fonte é o painel', async () => {
      const { readFileSync } = await import('node:fs');
      const { join } = await import('node:path');
      const source = readFileSync(
        join(process.cwd(), 'app/javascript/sdk/bubbleHelpers.js'),
        'utf8'
      );

      // Se alguém reintroduzir um dicionário aqui, volta a haver duas verdades.
      expect(source).not.toContain('Abrir chat');
      expect(source).not.toContain('Falar com');
      expect(source).not.toMatch(/LAUNCHER_LABELS|launcherLabel/);
    });

    it('setBubbleAccessibleName pinta title E aria-label nos DOIS botões', () => {
      setBubbleAccessibleName('Abrir o chat');

      expect(chatBubble.title).toBe('Abrir o chat');
      expect(chatBubble.getAttribute('aria-label')).toBe('Abrir o chat');
      // O botão de fechar também: ele troca de papel com o de abrir.
      expect(closeBubble.title).toBe('Abrir o chat');
      expect(closeBubble.getAttribute('aria-label')).toBe('Abrir o chat');
    });

    it('nome vazio não apaga um nome já posto — botão sem nome é o pior caso', () => {
      setBubbleAccessibleName('Abrir o chat');
      setBubbleAccessibleName('');
      setBubbleAccessibleName(undefined);

      expect(chatBubble.title).toBe('Abrir o chat');
    });

    it('a ponte SUBSTITUI o provisório em inglês pelo traduzido do painel', () => {
      window.$chatwoot = { position: 'right', type: 'standard' };
      const target = freshButton();
      createBubbleIcon({
        className: 'woot-widget-bubble',
        path: bubbleSVG,
        target,
        launcherIcon: resolveLauncherIcon({}),
      });

      // O provisório existe de propósito: um botão sem nome é pior para o leitor
      // de tela do que um botão com nome no idioma errado por milissegundos.
      expect(target.title).toBe('Open chat window');

      IFrameHelper.launcherIconLabel = null;
      IFrameHelper.events.setBubbleLabel({
        label: 'Converse conosco',
        ariaLabel: 'Abrir o chat',
      });

      expect(chatBubble.title).toBe('Abrir o chat');
      expect(chatBubble.getAttribute('aria-label')).toBe('Abrir o chat');
    });

    it('o rótulo da tela de aparência (3.19) SOBREVIVE à ponte', () => {
      // Sem esta precedência, o lançador apareceria com a foto da Marina e o nome
      // dela seria trocado pelo genérico milissegundos depois.
      IFrameHelper.launcherIconLabel = 'Falar com a Marina';
      IFrameHelper.events.setBubbleLabel({
        label: 'Converse conosco',
        ariaLabel: 'Abrir o chat',
      });

      expect(chatBubble.getAttribute('aria-label')).toBe('Falar com a Marina');
    });

    it('mas a opção pública do cliente vence até o rótulo da aparência', () => {
      window.$chatwoot = {
        position: 'right',
        type: 'standard',
        launcherTitle: 'Fale com o suporte',
      };
      IFrameHelper.launcherIconLabel = 'Falar com a Marina';
      IFrameHelper.events.setBubbleLabel({
        label: 'Converse conosco',
        ariaLabel: 'Abrir o chat',
      });

      expect(chatBubble.getAttribute('aria-label')).toBe('Fale com o suporte');
    });

    it('resolveLauncherIcon repassa rótulo explícito, e só ele — não traduz', () => {
      expect(
        resolveLauncherIcon({
          locale: 'pt_BR',
          widgetAppearance: {
            launcher_icon: { mode: 'agent_photo', label: 'Falar com a Marina' },
          },
          avatarUrl: '/avatar/marina.png',
        }).label
      ).toBe('Falar com a Marina');

      // Sem rótulo configurado devolve `null`, e quem nomeia é a ponte.
      expect(resolveLauncherIcon({ locale: 'pt_BR' }).label).toBeNull();
      expect(
        resolveLauncherIcon({
          widgetAppearance: { launcher_icon_label: '   ' },
        }).label
      ).toBeNull();
    });
  });

  // ── MODO default ─────────────────────────────────────────────────────────
  describe('modo `default` — o balão de hoje, intacto', () => {
    it('desenha o SVG com o path e o fill de sempre', () => {
      const target = freshButton();
      createBubbleIcon({
        className: 'woot-widget-bubble',
        path: bubbleSVG,
        target,
      });

      const path = target.querySelector('svg#woot-widget-bubble-icon path');
      expect(path.getAttribute('d')).toBe(bubbleSVG);
      // `currentColor`, valor do bloco 1.05: o ícone herda `--w-on-brand`, que o
      // servidor calculou por luminância. Um `#FFFFFF` cravado aqui deixaria o
      // ícone branco sobre marca clara, a 3,07:1.
      expect(path.getAttribute('fill')).toBe('currentColor');
      expect(target.querySelector('img')).toBeNull();
      expect(target.className).not.toContain('has-photo');
    });

    it('INVARIANTE: o fill continua ATRIBUTO de apresentação, nunca style inline', () => {
      const target = freshButton();
      createBubbleIcon({
        className: 'woot-widget-bubble',
        path: bubbleSVG,
        target,
      });

      const path = target.querySelector('path');
      // `style` inline é a única forma que uma folha sem `!important` não
      // sobrescreve. Enquanto for atributo, qualquer regra futura sobre `path`
      // ainda alcança o ícone — e é o que permitiu ao 1.05 trocar o valor sem
      // tocar na forma. Um merge "moderno" que trocasse por `style.fill` passaria
      // em tudo e mataria a variante clara em silêncio.
      expect(path.style.fill).toBe('');
      expect(path.hasAttribute('fill')).toBe(true);
    });

    it('não emite preload quando não há foto', () => {
      createBubbleIcon({
        className: 'woot-widget-bubble',
        path: bubbleSVG,
        target: freshButton(),
      });

      expect(
        document.head.querySelectorAll('link[rel="preload"]')
      ).toHaveLength(0);
    });
  });

  // ── ASSERÇÃO 5 ───────────────────────────────────────────────────────────
  describe('asserção 5 — preload/fetchpriority: o lançador não pisca vazio', () => {
    const PHOTO = 'https://app.chatspx.com.br/rails/blob/marina.webp';

    it('emite <link rel=preload as=image fetchpriority=high> para a foto', () => {
      createBubbleIcon({
        className: 'woot-widget-bubble',
        path: bubbleSVG,
        target: freshButton(),
        launcherIcon: { mode: 'image', src: PHOTO, label: 'Abrir chat' },
      });

      const link = document.head.querySelector('link[rel="preload"]');
      expect(link.getAttribute('as')).toBe('image');
      expect(link.getAttribute('href')).toBe(PHOTO);
      expect(link.getAttribute('fetchpriority')).toBe('high');
    });

    it('a própria <img> também é high priority e decode assíncrono', () => {
      const target = freshButton();
      createBubbleIcon({
        className: 'woot-widget-bubble',
        path: bubbleSVG,
        target,
        launcherIcon: { mode: 'image', src: PHOTO, label: 'Abrir chat' },
      });

      const img = target.querySelector('img');
      expect(img.getAttribute('fetchpriority')).toBe('high');
      expect(img.getAttribute('decoding')).toBe('async');
    });

    it('reinicializar o widget não empilha <link> — o preload é idempotente', () => {
      preloadLauncherImage(PHOTO);
      preloadLauncherImage(PHOTO);
      preloadLauncherImage(PHOTO);

      expect(
        document.head.querySelectorAll('link[rel="preload"][as="image"]')
      ).toHaveLength(1);
    });

    it('a imagem é decorativa: o nome acessível vive no botão, não duplicado no alt', () => {
      const target = freshButton();
      createBubbleIcon({
        className: 'woot-widget-bubble',
        path: bubbleSVG,
        target,
        launcherIcon: {
          mode: 'image',
          src: PHOTO,
          label: 'Falar com a Marina',
        },
      });

      const img = target.querySelector('img');
      expect(img.alt).toBe('');
      expect(img.getAttribute('aria-hidden')).toBe('true');
      expect(target.getAttribute('aria-label')).toBe('Falar com a Marina');
    });
  });

  // ── ASSERÇÃO 6 ───────────────────────────────────────────────────────────
  describe('asserção 6 — 404 na foto nunca deixa o site sem canal de contato', () => {
    const BROKEN = 'https://app.chatspx.com.br/rails/blob/apagada.webp';

    it('onerror remove a <img> e devolve o bubbleSVG ao botão', () => {
      const target = freshButton();
      createBubbleIcon({
        className: 'woot-widget-bubble',
        path: bubbleSVG,
        target,
        launcherIcon: { mode: 'image', src: BROKEN, label: 'Abrir chat' },
      });

      const img = target.querySelector('img');
      expect(img).not.toBeNull();
      expect(target.querySelector('svg')).toBeNull();

      img.onerror();

      expect(target.querySelector('img')).toBeNull();
      const path = target.querySelector('svg#woot-widget-bubble-icon path');
      expect(path.getAttribute('d')).toBe(bubbleSVG);
    });

    it('o anel da foto some junto — o balão não fica com borda de retrato', () => {
      const target = freshButton();
      createBubbleIcon({
        className: 'woot-widget-bubble',
        path: bubbleSVG,
        target,
        launcherIcon: { mode: 'image', src: BROKEN, label: 'Abrir chat' },
      });

      expect(target.className).toContain('woot-widget-bubble--has-photo');
      target.querySelector('img').onerror();
      expect(target.className).not.toContain('woot-widget-bubble--has-photo');
    });

    it('o nome acessível sobrevive à queda da foto', () => {
      const target = freshButton();
      createBubbleIcon({
        className: 'woot-widget-bubble',
        path: bubbleSVG,
        target,
        launcherIcon: {
          mode: 'image',
          src: BROKEN,
          label: 'Falar com a Marina',
        },
      });

      target.querySelector('img').onerror();

      expect(target.getAttribute('aria-label')).toBe('Falar com a Marina');
    });
  });

  // ── ASSERÇÃO 7 ───────────────────────────────────────────────────────────
  describe('asserção 7 — anel ≥ 3:1 (SC 1.4.11)', () => {
    it('o anel interno sai de --w-brand-border, com branco de fallback', () => {
      expect(SDK_CSS).toContain('0 0 0 2px var(--w-brand-border, #ffffff)');
    });

    it('o anel externo existe — sem ele o aceite é insatisfazível', () => {
      expect(SDK_CSS).toContain('0 0 0 3px rgba(0, 0, 0, 0.55)');
    });

    it('PROVA: um anel de UMA cor não pode satisfazer os três pares', () => {
      // Este teste não verifica o nosso código — verifica a ARITMÉTICA que obrigou o
      // desenho de dois anéis, para que ninguém "simplifique" de volta para uma cor só.
      const maxForLightPage = 1.05 / 3 - 0.05;
      const minForDarkPage = 3 * (relativeLuminance(DARK_PAGE) + 0.05) - 0.05;
      const maxForBrand = (relativeLuminance(BRAND) + 0.05) / 3 - 0.05;

      expect(maxForLightPage).toBeCloseTo(0.3, 2);
      expect(minForDarkPage).toBeCloseTo(0.13, 2);
      expect(maxForBrand).toBeCloseTo(0.1, 2);

      // O intervalo exigido é vazio: o piso do fundo escuro está ACIMA do teto da marca.
      expect(minForDarkPage).toBeGreaterThan(maxForBrand);
    });

    it('par 1/3 — a borda × cor da marca ≥ 3:1 (quem carrega é o anel externo)', () => {
      expect(
        contrastRatio(over(RING_OUTER, BRAND), BRAND)
      ).toBeGreaterThanOrEqual(3);
    });

    it('par 2/3 — a borda × fundo claro ≥ 3:1 (anel externo)', () => {
      expect(
        contrastRatio(over(RING_OUTER, WHITE), WHITE)
      ).toBeGreaterThanOrEqual(3);
    });

    it('par 3/3 — a borda × fundo escuro ≥ 3:1 (quem carrega é o anel interno)', () => {
      expect(contrastRatio(RING_INNER, DARK_PAGE)).toBeGreaterThanOrEqual(3);
    });

    it('e os dois anéis contrastam ENTRE SI — a fronteira nunca some', () => {
      // É isto que fecha o caso do fundo arbitrário: quando um anel se funde com a
      // página do cliente, o outro continua desenhando a borda do controle.
      expect(
        contrastRatio(over(RING_OUTER, WHITE), RING_INNER)
      ).toBeGreaterThanOrEqual(3);
    });

    it('os quatro números medidos, com tolerância declarada', () => {
      expect(contrastRatio(over(RING_OUTER, BRAND), BRAND)).toBeCloseTo(
        3.73,
        2
      );
      expect(contrastRatio(over(RING_OUTER, WHITE), WHITE)).toBeCloseTo(
        4.76,
        2
      );
      expect(contrastRatio(over(RING_OUTER, WHITE), RING_INNER)).toBeCloseTo(
        4.76,
        2
      );
      expect(contrastRatio(RING_INNER, DARK_PAGE)).toBeCloseTo(17.93, 2);
    });

    it('e o número que PROVA por que o anel branco sozinho não basta', () => {
      // 2,2734 é o mesmo valor que o plano cita no bloco 3.08 para #2DC46F.
      expect(contrastRatio(RING_INNER, BRAND)).toBeCloseTo(2.27, 2);
      expect(contrastRatio(RING_INNER, BRAND)).toBeLessThan(3);
    });
  });

  // ── ASSERÇÃO 8 ───────────────────────────────────────────────────────────
  describe('asserção 8 — object-fit: cover no círculo de 64 px congelado', () => {
    it('a foto recorta, não estica', () => {
      expect(SDK_CSS).toMatch(
        /\.woot-widget-bubble img\.woot-widget-bubble__photo\s*\{[^}]*object-fit:\s*cover/
      );
    });

    it('a foto preenche o círculo e herda o raio da bolha', () => {
      const rule = SDK_CSS.match(
        /\.woot-widget-bubble img\.woot-widget-bubble__photo\s*\{([^}]*)\}/
      )[1];

      expect(rule).toContain('width: 100%');
      expect(rule).toContain('height: 100%');
      expect(rule).toContain('border-radius: inherit');
    });

    it('o círculo de 64 px continua congelado (§8 item 2)', () => {
      const bubbleRule = SDK_CSS.match(/\.woot-widget-bubble \{([^}]*)\}/)[1];

      expect(bubbleRule).toContain('height: 64px');
      expect(bubbleRule).toContain('width: 64px');
      expect(bubbleRule).toContain('overflow: hidden');
    });
  });
});
