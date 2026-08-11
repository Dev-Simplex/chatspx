import { mount } from '@vue/test-utils';
import { h, ref } from 'vue';
import Dialog from '../Dialog.vue';

// jsdom não implementa <dialog>; só precisamos que os métodos existam.
beforeAll(() => {
  HTMLDialogElement.prototype.showModal = function showModal() {
    this.setAttribute('open', '');
  };
  HTMLDialogElement.prototype.close = function close() {
    this.removeAttribute('open');
  };
});

// Espelha o contrato real dos consumidores (ComposeConversation.onAttendanceCancel
// e ConversationAction.onTakeoverCancel): o handler de @close chama close() de
// volta no diálogo. Antes da guarda de reentrância isso estourava a pilha e
// abortava o handler do clique — os botões do aviso "Este contato já está em
// atendimento" não faziam nada e a tela travava.
const mountHarness = () => {
  const dialogRef = ref(null);
  const closeSpy = vi.fn();

  mount(
    {
      setup() {
        const onClose = () => {
          closeSpy();
          dialogRef.value?.close();
        };
        return () =>
          h(Dialog, {
            ref: el => {
              dialogRef.value = el;
            },
            title: 'Este contato já está em atendimento',
            onClose,
          });
      },
    },
    {
      global: {
        stubs: {
          TeleportWithDirection: { template: '<div><slot /></div>' },
          OnClickOutside: { template: '<div><slot /></div>' },
        },
        mocks: { $t: key => key },
      },
    }
  );

  return { dialogRef, closeSpy };
};

describe('Dialog', () => {
  it('não entra em recursão quando o pai chama close() dentro do @close', () => {
    const { dialogRef } = mountHarness();
    dialogRef.value.open();

    expect(() => dialogRef.value.close()).not.toThrow();
  });

  it('emite close uma única vez por fechamento', () => {
    const { dialogRef, closeSpy } = mountHarness();
    dialogRef.value.open();

    dialogRef.value.close();

    expect(closeSpy).toHaveBeenCalledTimes(1);
  });

  it('continua fechando normalmente em aberturas seguintes', () => {
    const { dialogRef, closeSpy } = mountHarness();

    dialogRef.value.open();
    dialogRef.value.close();
    dialogRef.value.open();
    dialogRef.value.close();

    expect(closeSpy).toHaveBeenCalledTimes(2);
  });
});
