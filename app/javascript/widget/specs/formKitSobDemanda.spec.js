/**
 * FormKit só na rota do pré-chat — bloco 2.18.
 *
 * A LISTA `ROTAS_COM_FORMKIT` é o ponto frágil do desenho: uma rota nova que
 * monte `PreChat/Form.vue` e não esteja nela não quebra build, nem lint, nem
 * teste de componente — quebra o pré-chat no site do cliente, em produção,
 * porque o plugin do FormKit não terá sido instalado quando o formulário
 * renderizar. Este arquivo é a guarda desse caso.
 *
 * Ele NÃO analisa texto de fonte para decidir quem usa o quê: carrega as
 * rotas de verdade, pelo mesmo `import()` que o navegador usa, e caminha a
 * árvore de `components` procurando o componente `FormKit` POR IDENTIDADE.
 * Um `grep` acharia a palavra "FormKit" em comentário e em nome de classe
 * CSS; identidade de objeto não tem esse ponto cego.
 *
 * E há um CONTROLE POSITIVO: se o caminhador não encontrar o FormKit na rota
 * que sabidamente o usa, o teste falha dizendo que quem quebrou foi ele — sem
 * isso, um caminhador cego passaria afirmando "nenhuma rota usa FormKit".
 */
import { describe, it, expect, beforeAll } from 'vitest';
import { FormKit } from '@formkit/vue';
import router from 'widget/router';
import { ROTAS_COM_FORMKIT } from 'widget/formkit';

const A_ROTA_QUE_SABIDAMENTE_USA = 'prechat-form';

/** Resolve o `component` de uma rota, seja ele objeto ou `() => import()`. */
const resolverComponente = async definicao => {
  if (!definicao) return null;
  if (typeof definicao === 'function') {
    const mod = await definicao();
    return mod?.default ?? mod;
  }
  return definicao;
};

/** Caminha `components` em profundidade procurando o FormKit por identidade. */
const usaFormKit = (componente, vistos = new Set()) => {
  if (!componente || typeof componente !== 'object' || vistos.has(componente)) {
    return false;
  }
  vistos.add(componente);
  if (componente === FormKit) return true;
  const filhos = componente.components ?? {};
  return Object.values(filhos).some(filho => usaFormKit(filho, vistos));
};

describe('FormKit sob demanda', () => {
  let rotasQueUsam;

  beforeAll(async () => {
    // As views leem a configuração do canal no boot; sem ela o `import()`
    // levanta antes de a árvore de componentes existir.
    window.chatwootWebChannel = {
      avatarUrl: '',
      enabledLanguages: [{ iso_639_1_code: 'en' }],
      locale: 'en',
      preChatFormEnabled: true,
      preChatFormOptions: { pre_chat_fields: [] },
      websiteToken: 'token',
      workingHours: [],
    };
    window.chatwootWidgetDefaults = {};

    const nomeadas = router
      .getRoutes()
      .filter(r => r.name && r.components?.default);

    // Se o router deixar de expor rotas nomeadas, o teste abaixo passaria
    // comparando dois conjuntos vazios. Isso é medição quebrada, não sucesso.
    expect(nomeadas.length).toBeGreaterThanOrEqual(6);

    const achados = [];
    for (const rota of nomeadas) {
      // eslint-disable-next-line no-await-in-loop
      const componente = await resolverComponente(rota.components.default);
      if (usaFormKit(componente)) achados.push(rota.name);
    }
    rotasQueUsam = achados;
  });

  it('o caminhador enxerga o FormKit na rota que sabidamente o usa', () => {
    // CONTROLE POSITIVO. Sem ele, um caminhador cego reportaria zero rotas e
    // o teste seguinte passaria por vacuidade.
    expect(rotasQueUsam).toContain(A_ROTA_QUE_SABIDAMENTE_USA);
  });

  it('`ROTAS_COM_FORMKIT` cobre exatamente as rotas que montam o formulário', () => {
    expect([...rotasQueUsam].sort()).toEqual([...ROTAS_COM_FORMKIT].sort());
  });

  it('o pré-chat continua sendo rota `import()`, não import estático', () => {
    const rota = router
      .getRoutes()
      .find(r => r.name === A_ROTA_QUE_SABIDAMENTE_USA);
    // Componente resolvido preguiçosamente = função. Virar objeto aqui
    // significaria que a view voltou ao fecho de first-paint, e aí instalar o
    // plugin sob demanda não economiza byte nenhum.
    expect(typeof rota.components.default).toBe('function');
  });
});
