// O `router` do painel entra PRIMEIRO de proposito: ele e a porta de entrada do
// ciclo de imports das rotas (index -> dashboard.routes -> ... -> BackButton ->
// index). Comecar por qualquer outro ponto do ciclo deixa `dashboard.routes`
// pela metade e o arquivo inteiro morre no carregamento.
import { router } from 'dashboard/routes/index';
import { mount, flushPromises, config } from '@vue/test-utils';
import { createStore } from 'vuex';
import { nextTick } from 'vue';
import { describe, it, expect, vi, afterEach } from 'vitest';
import Sidebar from '../Sidebar.vue';
import SidebarGroup from '../SidebarGroup.vue';
import SidebarCollapsedPopover from '../SidebarCollapsedPopover.vue';

// Bloco 1.22 — o relatorio de origem so existe para quem digita a URL enquanto
// nao houver item na barra lateral. Este arquivo monta a Sidebar DE VERDADE,
// com a tabela de rotas real do painel, e exige o caminho que o cliente faz:
// passar o mouse no grupo "Relatorios" e clicar em "Origem".
//
// Deliberadamente NAO e um grep por 'conversation_origin_reports' no arquivo:
// o item ja foi acrescentado uma vez (439471e015) e apagado por um recorte de
// upstream (13348e12a4) sem que nada ficasse vermelho.

vi.mock('lottie-web', () => ({
  default: { loadAnimation: vi.fn(() => ({ destroy: vi.fn() })) },
}));

const CURRENT_USER = {
  id: 1,
  name: 'Agent',
  account_id: 1,
  accounts: [{ id: 1, role: 'administrator', permissions: ['administrator'] }],
};

const buildStore = () => {
  const noop = () => {};
  return createStore({
    state: {},
    getters: {
      getCurrentUser: () => CURRENT_USER,
      getCurrentAccountId: () => 1,
      getCurrentRole: () => 'administrator',
      getUserAccounts: () => CURRENT_USER.accounts,
      getCurrentUserAvailability: () => 'online',
      getCurrentUserAutoOffline: () => false,
      getUISettings: () => ({}),
    },
    actions: { setUser: noop, updateUISettings: noop },
    modules: {
      accounts: {
        namespaced: true,
        getters: {
          getAccount: () => () => ({ id: 1, settings: {} }),
          isFeatureEnabledonAccount: () => () => true,
          isRTL: () => false,
        },
      },
      globalConfig: {
        namespaced: true,
        getters: {
          get: () => ({}),
          isOnChatwootCloud: () => false,
          isACustomBrandedInstance: () => false,
        },
      },
      inboxes: {
        namespaced: true,
        getters: { getInboxes: () => [] },
        actions: { get: noop },
      },
      labels: {
        namespaced: true,
        getters: { getLabelsOnSidebar: () => [] },
        actions: { get: noop },
      },
      teams: {
        namespaced: true,
        getters: { getVisibleTeams: () => [] },
        actions: { get: noop },
      },
      conversationStats: {
        namespaced: true,
        getters: { getStats: () => ({}) },
        actions: { get: noop },
      },
      customViews: {
        namespaced: true,
        getters: {
          getContactCustomViews: () => [],
          getConversationCustomViews: () => [],
        },
        actions: { get: noop },
      },
      notifications: {
        namespaced: true,
        getters: { getMeta: () => ({}), getUnreadCount: () => 0 },
        actions: { unReadCount: noop },
      },
      integrations: {
        namespaced: true,
        getters: { getAppIntegrations: () => [] },
        actions: { get: noop },
      },
      takeoverRequests: {
        namespaced: true,
        getters: { getIncomingCount: () => 0 },
        actions: { fetchIncoming: noop },
      },
      internalChat: {
        namespaced: true,
        getters: { getPendingMention: () => false, getTotalUnread: () => 0 },
        actions: { fetchChannels: noop },
      },
      attributes: {
        namespaced: true,
        getters: { getAttributes: () => [] },
        actions: { get: noop },
      },
    },
  });
};

// A tabela de rotas e a REAL do painel (o mesmo `router` que vai ao ar): se o
// nome da rota do relatorio mudar ou sumir, este spec cai junto — nao ha rota
// inventada aqui para o item apontar.
const montarSidebar = async () => {
  await router.push('/app/accounts/1/dashboard');
  await router.isReady();
  const wrapper = mount(Sidebar, {
    attachTo: document.body,
    global: {
      plugins: [buildStore(), router],
      stubs: {
        SidebarProfileMenu: true,
        SidebarAccountSwitcher: true,
        SidebarChangelogCard: true,
        SidebarChangelogButton: true,
        Logo: true,
        LordIconIcon: true,
      },
    },
  });
  await flushPromises();
  return { wrapper };
};

// O rail vive colapsado: os filhos de um grupo aparecem no flyout que abre no
// hover. E assim que o cliente chega no relatorio, entao e assim que o teste
// chega tambem.
const abrirGrupo = async (wrapper, nomeDoGrupo) => {
  const grupo = wrapper
    .findAllComponents(SidebarGroup)
    .find(componente => componente.props('name') === nomeDoGrupo);
  expect(
    grupo,
    `grupo "${nomeDoGrupo}" nao existe na barra lateral`
  ).toBeTruthy();
  await grupo.find('div.relative').trigger('mouseenter');
  await flushPromises();
  await nextTick();
  return wrapper.findComponent(SidebarCollapsedPopover);
};

// A instancia de i18n e a do `vitest.setup.js` (mensagens reais do painel).
const obterI18n = () =>
  config.global.plugins.find(plugin => plugin?.global?.locale);

// O flyout sai por <Teleport> para o body (dentro do <div dir> do
// TeleportWithDirection), entao a leitura e feita no DOM — o wrapper do VTU nao
// alcanca conteudo teleportado.
const botoesDoFlyout = () =>
  Array.from(document.querySelectorAll('body div[dir] button'));

const itensDoFlyout = () =>
  botoesDoFlyout().map(botao => botao.textContent.trim());

describe('Sidebar — item "Relatórios > Origem" (bloco 1.22)', () => {
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('mostra o item de Origem entre os relatórios do flyout', async () => {
    const { wrapper } = await montarSidebar();
    const popover = await abrirGrupo(wrapper, 'Reports');
    const itens = itensDoFlyout();

    expect(popover.exists()).toBe(true);
    // Trava contra o vacuo: um flyout vazio faria a assercao de baixo falhar
    // por motivo errado. Estes tres itens sao os vizinhos de sempre.
    expect(itens).toEqual(
      expect.arrayContaining(['Overview', 'Conversations', 'Agents'])
    );
    expect(itens).toContain('Origin');
  });

  it('clicar no item leva à tela do relatório de origem', async () => {
    const { wrapper } = await montarSidebar();
    await abrirGrupo(wrapper, 'Reports');

    const item = botoesDoFlyout().find(
      botao => botao.textContent.trim() === 'Origin'
    );
    expect(item, 'o item "Origem" nao esta no menu de relatorios').toBeTruthy();

    item.click();
    await flushPromises();

    expect(router.currentRoute.value.name).toBe('conversation_origin_reports');
    expect(router.currentRoute.value.path).toBe(
      '/app/accounts/1/reports/origin'
    );
  });

  it('o rótulo do item vem da tradução, e existe em pt-BR', async () => {
    // A chave `SIDEBAR.REPORTS_ORIGIN` existia nos dois idiomas com ZERO
    // consumidores. Aqui ela e lida pela tela: se o item voltar com texto fixo,
    // ou se a traducao sumir de um dos idiomas, o texto muda e o teste cai.
    const i18n = obterI18n();
    expect(i18n.global.t('SIDEBAR.REPORTS_ORIGIN')).toBe('Origin');

    i18n.global.locale.value = 'pt_BR';
    try {
      const { wrapper } = await montarSidebar();
      await abrirGrupo(wrapper, 'Reports');
      expect(itensDoFlyout()).toContain('Origem');
    } finally {
      i18n.global.locale.value = 'en';
    }
  });
});
