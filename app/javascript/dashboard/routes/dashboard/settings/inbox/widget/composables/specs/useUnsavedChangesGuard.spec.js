/* eslint-disable vue/one-component-per-file --
   Sao dois componentes de MENTIRA (o guardado e o destino da navegacao) que so
   existem dentro deste teste; separa-los em arquivos daria dois arquivos que
   ninguem mais importa. */
import { defineComponent, h, ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import { createRouter, createMemoryHistory, RouterView } from 'vue-router';
import { useUnsavedChangesGuard } from '../useUnsavedChangesGuard';

// O guard vive no setup; o teste alcanca o que ele devolve por esta referencia
// em vez de `wrapper.vm`, porque um componente com render function nao expoe o
// setup em `vm` quando e encontrado por `findComponent`.
let guard;
let discarded;

const Guarded = defineComponent({
  props: { isDirty: { type: Object, required: true } },
  setup(props) {
    discarded = ref(0);
    guard = useUnsavedChangesGuard({
      isDirty: props.isDirty,
      onDiscard: () => {
        discarded.value += 1;
      },
    });
    return () => h('div', 'guardado');
  },
});

const Other = defineComponent({ setup: () => () => h('div', 'outra tela') });

let isDirty;

const buildRouter = () =>
  createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: Guarded, props: () => ({ isDirty }) },
      { path: '/outra', component: Other },
    ],
  });

beforeEach(() => {
  isDirty = ref(false);
  guard = null;
  discarded = null;
});

// Montado FORA do <router-view>, o `onBeforeRouteLeave` do vue-router avisa em
// stderr que nao achou rota ativa e nao registra guard nenhum. O aviso e
// esperado aqui — este bloco testa justamente o caminho que NAO passa pelo
// router (a troca de aba por `history.replaceState`). O caminho de rota tem
// bloco proprio abaixo, com router de verdade.
describe('useUnsavedChangesGuard — troca de aba (sem router)', () => {
  const build = () => mount(Guarded, { props: { isDirty } });

  it('sem pendência, a saída acontece na hora', () => {
    build();
    const action = vi.fn();

    expect(guard.requestLeave(action)).toBe(true);
    expect(action).toHaveBeenCalledTimes(1);
    expect(guard.isPromptOpen.value).toBe(false);
  });

  it('com pendência, a saída fica presa e o aviso abre', () => {
    isDirty.value = true;
    build();
    const action = vi.fn();

    expect(guard.requestLeave(action)).toBe(false);
    expect(action).not.toHaveBeenCalled();
    expect(guard.isPromptOpen.value).toBe(true);
  });

  it('confirmar descarta e executa a ação segurada', () => {
    isDirty.value = true;
    build();
    const action = vi.fn();

    guard.requestLeave(action);
    guard.confirmLeave();

    expect(discarded.value).toBe(1);
    expect(action).toHaveBeenCalledTimes(1);
    expect(guard.isPromptOpen.value).toBe(false);
  });

  it('cancelar não descarta nem executa', () => {
    isDirty.value = true;
    build();
    const action = vi.fn();

    guard.requestLeave(action);
    guard.cancelLeave();

    expect(discarded.value).toBe(0);
    expect(action).not.toHaveBeenCalled();
    expect(guard.isPromptOpen.value).toBe(false);
  });

  it('fechar a aba do navegador só é barrado com pendência', () => {
    build();
    const event = { preventDefault: vi.fn(), returnValue: undefined };

    guard.onBeforeUnload(event);
    expect(event.preventDefault).not.toHaveBeenCalled();

    isDirty.value = true;
    guard.onBeforeUnload(event);
    expect(event.preventDefault).toHaveBeenCalledTimes(1);
  });
});

describe('useUnsavedChangesGuard — navegação de rota', () => {
  it('deixa sair quando não há pendência', async () => {
    const router = buildRouter();
    router.push('/');
    await router.isReady();
    mount({ render: () => h(RouterView) }, { global: { plugins: [router] } });

    await router.push('/outra');
    await flushPromises();

    expect(router.currentRoute.value.path).toBe('/outra');
  });

  it('segura a navegação até o aviso responder, e o "não" fica na tela', async () => {
    isDirty.value = true;
    const router = buildRouter();
    router.push('/');
    await router.isReady();
    mount({ render: () => h(RouterView) }, { global: { plugins: [router] } });
    await flushPromises();

    const navigation = router.push('/outra');
    await flushPromises();

    expect(guard.isPromptOpen.value).toBe(true);
    expect(router.currentRoute.value.path).toBe('/');

    guard.cancelLeave();
    await navigation;
    await flushPromises();

    expect(router.currentRoute.value.path).toBe('/');
  });

  it('o "sim" descarta e a navegação completa', async () => {
    isDirty.value = true;
    const router = buildRouter();
    router.push('/');
    await router.isReady();
    mount({ render: () => h(RouterView) }, { global: { plugins: [router] } });
    await flushPromises();

    const navigation = router.push('/outra');
    await flushPromises();

    expect(discarded.value).toBe(0);
    guard.confirmLeave();
    await navigation;
    await flushPromises();

    expect(discarded.value).toBe(1);
    expect(router.currentRoute.value.path).toBe('/outra');
  });
});
