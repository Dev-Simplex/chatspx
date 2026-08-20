/**
 * A confirmacao ao sair com alteracao pendente.
 *
 * Tres saidas distintas levam embora o rascunho, e as tres precisam do mesmo
 * aviso — perder dez campos configurados e a falha mais cara que uma tela de
 * settings pode ter (23-plano §B.1.1):
 *
 *   1. trocar de aba DENTRO da tela de configuracao da inbox. Nao passa pelo
 *      router: `Settings.vue` troca de aba com `window.history.replaceState`,
 *      entao nenhum guard de rota dispara. Por isso existe `requestLeave`, que
 *      quem troca a aba chama passando a acao a executar depois do "sim";
 *   2. navegar para outra rota do painel — `onBeforeRouteLeave`, na forma que
 *      DEVOLVE uma promessa: o guard fica pendurado ate o dialogo responder, em
 *      vez de chamar `next()` duas vezes (que o router trata como erro);
 *   3. fechar/recarregar a aba do navegador — `beforeunload`.
 */
import { onBeforeUnmount, onMounted, ref, unref } from 'vue';
import { onBeforeRouteLeave } from 'vue-router';

export function useUnsavedChangesGuard({ isDirty, onDiscard = null } = {}) {
  const isPromptOpen = ref(false);
  let onConfirm = null;
  let onCancel = null;

  const dirty = () => Boolean(unref(isDirty));

  const openPrompt = ({ confirm, cancel }) => {
    onConfirm = confirm ?? null;
    onCancel = cancel ?? null;
    isPromptOpen.value = true;
  };

  /**
   * @param {Function} action  o que fazer se o administrador confirmar a saida
   * @returns {boolean} true quando saiu na hora (nao havia pendencia)
   */
  const requestLeave = action => {
    if (!dirty()) {
      action?.();
      return true;
    }
    openPrompt({ confirm: action });
    return false;
  };

  const confirmLeave = () => {
    isPromptOpen.value = false;
    onDiscard?.();
    const action = onConfirm;
    onConfirm = null;
    onCancel = null;
    action?.();
  };

  const cancelLeave = () => {
    isPromptOpen.value = false;
    const action = onCancel;
    onConfirm = null;
    onCancel = null;
    action?.();
  };

  const onBeforeUnload = event => {
    if (!dirty()) return undefined;
    // O texto e do navegador desde o Chrome 51; o que vale e o preventDefault.
    event.preventDefault();
    event.returnValue = '';
    return '';
  };

  onMounted(() => window.addEventListener('beforeunload', onBeforeUnload));
  onBeforeUnmount(() =>
    window.removeEventListener('beforeunload', onBeforeUnload)
  );

  onBeforeRouteLeave(() => {
    if (!dirty()) return true;
    return new Promise(resolve => {
      openPrompt({
        confirm: () => resolve(true),
        cancel: () => resolve(false),
      });
    });
  });

  return {
    isPromptOpen,
    requestLeave,
    confirmLeave,
    cancelLeave,
    onBeforeUnload,
  };
}
