import fs from 'fs';
import path from 'path';
import { mount } from '@vue/test-utils';
import { PREVIEW_AVATAR_ACCENT } from '../previewAvatarAccent';
import WidgetFooter from '../components/WidgetFooter.vue';
import WidgetTeaser from '../components/WidgetTeaser.vue';

/**
 * O piso de contraste do avatar de iniciais do preview.
 *
 * Este spec nao pergunta "passou um `accent`?" — essa pergunta passa com
 * qualquer cor. Ele resolve as custom properties do accent contra os valores
 * REAIS de `widget/assets/scss/_tokens_values.scss`, nos dois temas do widget,
 * e mede a razao. Um accent que aponte para um par sem contraste (o
 * `--teal-4`/`--teal-11` que produziu 3,8187:1 na tela) reprova aqui.
 */
const tokensScss = fs.readFileSync(
  path.resolve(
    process.cwd(),
    'app/javascript/widget/assets/scss/_tokens_values.scss'
  ),
  'utf8'
);

/** As declaracoes `--nome: R G B;` de um mixin da paleta do widget. */
const paletaDoMixin = nome => {
  const bloco = new RegExp(`@mixin ${nome}\\s*\\{([\\s\\S]*?)\\n\\}`).exec(
    tokensScss
  );
  if (!bloco) throw new Error(`mixin ${nome} nao encontrado`);
  return Object.fromEntries(
    [...bloco[1].matchAll(/(--[\w-]+):\s*([^;]+);/g)].map(m => [
      m[1],
      m[2].trim(),
    ])
  );
};

/** `rgb(var(--slate-4))` -> [232, 232, 236], pela paleta do tema pedido. */
const resolver = (expressao, paleta) => {
  const nome = /var\((--[\w-]+)\)/.exec(expressao);
  if (!nome) {
    throw new Error(
      `"${expressao}" nao consome custom property. O accent do preview tem de ` +
        'ser token do widget — hex literal e a copia de paleta que o D4 matou.'
    );
  }
  const valor = paleta[nome[1]];
  if (!valor) throw new Error(`${nome[1]} nao existe na paleta do widget`);
  return valor.split(/\s+/).map(Number);
};

const luminancia = ([r, g, b]) => {
  const canal = v => {
    const c = v / 255;
    return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * canal(r) + 0.7152 * canal(g) + 0.0722 * canal(b);
};

const contraste = (a, b) => {
  const [claro, escuro] = [luminancia(a), luminancia(b)].sort((x, y) => y - x);
  return (claro + 0.05) / (escuro + 0.05);
};

describe('avatar do preview — o par de cores tem piso de contraste', () => {
  it('a medicao acusa o par que reprovava na tela (auto-verificacao)', () => {
    const light = paletaDoMixin('widget-palette-light');

    // O par que o `Avatar` sorteava para "Site da Simplex": teal-4 / teal-11.
    // Se esta conta deixar de reprovar, o teste abaixo nao mede nada.
    const razao = contraste(
      resolver('rgb(var(--teal-11))', light),
      resolver('rgb(var(--teal-4))', light)
    );

    expect(razao).toBeLessThan(4.5);
    expect(razao).toBeCloseTo(3.8187, 3);
  });

  it.each([
    ['claro', 'widget-palette-light', 'text', 'bg'],
    ['escuro', 'widget-palette-dark', 'text', 'bg'],
    ['escuro pelo painel', 'widget-palette-dark', 'darkText', 'darkBg'],
  ])('no tema %s o accent fica em 4,5:1 ou mais', (_, mixin, fg, bg) => {
    const paleta = paletaDoMixin(mixin);

    const razao = contraste(
      resolver(PREVIEW_AVATAR_ACCENT[fg], paleta),
      resolver(PREVIEW_AVATAR_ACCENT[bg], paleta)
    );

    expect(razao).toBeGreaterThanOrEqual(4.5);
  });

  it('o rodape e o teaser passam o accent ao Avatar', () => {
    const rodape = mount(WidgetFooter, {
      props: {
        config: { isDefaultScreen: true, websiteName: 'Site da Simplex' },
      },
      global: {
        stubs: { Avatar: true, FluentIcon: true, ResizableTextArea: true },
        mocks: { $t: chave => chave },
      },
    });
    const teaser = mount(WidgetTeaser, {
      props: { level: 'bold', text: 'oi', senderName: 'Marina' },
      global: { stubs: { Avatar: true } },
    });

    [rodape, teaser].forEach(wrapper => {
      expect(wrapper.findComponent({ name: 'Avatar' }).props('accent')).toEqual(
        PREVIEW_AVATAR_ACCENT
      );
    });
  });
});
