import { mount } from '@vue/test-utils';
import Dialog from '../Dialog.vue';

// Regressão: o aviso "Este contato já está em atendimento" travava com
// RangeError (Maximum call stack size exceeded) e os 3 botões não faziam nada.
// Causa: close() emite 'close' ANTES de fechar, e o pai reage a esse evento
// chamando close() de volta -> recursão infinita. Este harness reproduz
// exatamente esse contrato: o consumidor fecha o diálogo dentro do @close.
let wrapper;

const mountWithReentrantParent = () =>
  mount(Dialog, {
    props: { title: 'Em atendimento' },
    attrs: {
      onClose: () => wrapper.vm.close(),
    },
    global: {
      stubs: {
        TeleportWithDirection: { template: '<div><slot /></div>' },
        Button: true,
      },
    },
  });

describe('Dialog', () => {
  beforeEach(() => {
    // jsdom não implementa a API nativa de <dialog>.
    HTMLDialogElement.prototype.showModal = vi.fn();
    HTMLDialogElement.prototype.close = vi.fn();
  });

  afterEach(() => {
    wrapper?.unmount();
    wrapper = null;
  });

  it('não recursa quando o pai chama close() dentro do @close', () => {
    wrapper = mountWithReentrantParent();
    wrapper.vm.open();

    expect(() => wrapper.vm.close()).not.toThrow();
  });

  it('emite close uma única vez por fechamento', () => {
    wrapper = mountWithReentrantParent();
    wrapper.vm.open();
    wrapper.vm.close();

    expect(wrapper.emitted('close')).toHaveLength(1);
  });

  it('continua fechando normalmente em aberturas seguintes', () => {
    wrapper = mountWithReentrantParent();

    wrapper.vm.open();
    wrapper.vm.close();
    wrapper.vm.open();
    wrapper.vm.close();

    expect(wrapper.emitted('close')).toHaveLength(2);
  });
});
