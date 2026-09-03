/**
 * Mecanismo de aceite do bloco 1.07 — primeira metade.
 *
 * ACEITE (§2.2): "Nenhuma requisição a `typing.gif`".
 *
 * A forma mais direta de garantir que um recurso não é baixado é não haver
 * elemento que o peça: este spec assere que o balão de "digitando" não tem
 * `<img>` nenhuma, e que o `typing.gif` não é referenciado em ponto algum do
 * código do widget. A medição de rede de fato (`page.on('request')`) exige o
 * harness E2E, que usa portas compartilhadas — mas ela mediria a consequência de
 * exatamente o que está assertado aqui.
 */
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { readFileSync } from 'node:fs';
import { globSync } from 'node:fs';
import ptBR from 'widget/i18n/locale/pt_BR.json';
import AgentTypingBubble from '../AgentTypingBubble.vue';
import WTypingDots from 'widget/ui/WTypingDots.vue';

const i18n = createI18n({
  legacy: true,
  locale: 'pt_BR',
  messages: { pt_BR: ptBR },
  fallbackWarn: false,
  missingWarn: false,
});

const montar = componente =>
  mount(componente, {
    global: { plugins: [i18n], mocks: { $t: k => i18n.global.t(k) } },
  });

describe('1.07 — typing dots em CSS, sem o GIF', () => {
  it('o balão de digitando não pede imagem nenhuma', () => {
    const wrapper = montar(AgentTypingBubble);

    expect(wrapper.findAll('img')).toHaveLength(0);
    // Qualquer elemento que possa disparar requisição — `src` de qualquer tag,
    // não só `<img>`. Comparo os atributos, não o HTML bruto: o template
    // explica em comentário por que o GIF saiu, e comentário não baixa byte.
    const comSrc = wrapper
      .findAll('[src]')
      .map(el => el.attributes('src'))
      .filter(Boolean);
    expect(comSrc).toEqual([]);
  });

  it('o balão usa o componente de pontos em CSS', () => {
    const wrapper = montar(AgentTypingBubble);
    expect(wrapper.findComponent(WTypingDots).exists()).toBe(true);
  });

  it('são exatamente três pontos, e eles são decorativos', () => {
    const wrapper = montar(WTypingDots);
    const pontos = wrapper.findAll('.w-typing__dot');

    // Três: é o que a animação escalona com dois delays. Um número diferente
    // deixaria um ponto sem delay, saltando junto com o primeiro.
    expect(pontos).toHaveLength(3);
    pontos.forEach(ponto => {
      expect(ponto.attributes('aria-hidden')).toBe('true');
    });
  });

  it('o estado é anunciado como status, com nome em pt-BR', () => {
    const wrapper = montar(WTypingDots);
    const status = wrapper.find('[role="status"]');

    expect(status.exists()).toBe(true);
    expect(status.attributes('aria-label')).toBe('O agente está digitando');
  });

  it('nenhum arquivo do widget referencia typing.gif em código', () => {
    // O componente pode ter parado de usar e uma folha de estilo continuar
    // pedindo o arquivo em `background-image`. Este teste varre o diretório.
    //
    // Comentários são removidos antes de medir — este bloco e os dois
    // componentes EXPLICAM que o GIF saiu, e a explicação cita o nome do
    // arquivo. Medir prosa daria vermelho eterno; o que não pode existir é
    // referência que o bundler resolva.
    const semComentarios = texto =>
      texto
        .replace(/<!--[\s\S]*?-->/g, '')
        .replace(/\/\*[\s\S]*?\*\//g, '')
        .replace(/^\s*\/\/.*$/gm, '');

    const arquivos = globSync(
      'app/javascript/widget/**/*.{vue,js,scss}'
    ).filter(f => !f.endsWith('typingDots.spec.js'));

    // Piso alto de propósito: se o glob quebrar e devolver 2 arquivos, o teste
    // passaria sem ter varrido nada.
    expect(arquivos.length).toBeGreaterThan(50);
    const culpados = arquivos.filter(f =>
      semComentarios(readFileSync(f, 'utf8')).includes('typing.gif')
    );
    expect(culpados).toEqual([]);
  });
});
