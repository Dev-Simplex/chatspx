import { mount } from '@vue/test-utils';
import { nextTick, ref } from 'vue';
import { useGlobalDropZone } from '../useGlobalDropZone';

// DragEvent não existe no jsdom: um Event comum com `dataTransfer` anexado
// reproduz o que o composable lê (types/files/relatedTarget).
const dragEvent = (type, { files = ['a.png'], relatedTarget } = {}) => {
  const event = new Event(type, { bubbles: true, cancelable: true });
  Object.defineProperty(event, 'dataTransfer', {
    value: {
      types: files ? ['Files'] : [],
      files: files ? files.map(name => ({ name })) : [],
      dropEffect: '',
    },
  });
  if (relatedTarget !== undefined) {
    Object.defineProperty(event, 'relatedTarget', { value: relatedTarget });
  }
  return event;
};

const mountComposable = (options = {}) => {
  let api;
  const wrapper = mount({
    setup() {
      api = useGlobalDropZone(options);
      return () => null;
    },
  });
  return { api, wrapper };
};

describe('useGlobalDropZone', () => {
  it('mostra o overlay ao arrastar arquivos e esconde ao sair', async () => {
    const { api, wrapper } = mountComposable();
    expect(api.isOverDropZone.value).toBe(false);

    window.dispatchEvent(dragEvent('dragenter'));
    await nextTick();
    expect(api.isOverDropZone.value).toBe(true);

    window.dispatchEvent(
      dragEvent('dragleave', { relatedTarget: document.body })
    );
    await nextTick();
    expect(api.isOverDropZone.value).toBe(false);
    wrapper.unmount();
  });

  it('não reage a arraste que não seja de arquivo', async () => {
    const { api, wrapper } = mountComposable();
    window.dispatchEvent(dragEvent('dragenter', { files: null }));
    await nextTick();
    expect(api.isOverDropZone.value).toBe(false);
    wrapper.unmount();
  });

  // O bug do print: o usuário cancela o arraste (ESC ou solta fora da janela).
  // Não vem `drop` nem `dragleave` que balance o contador — só `dragend`. Sem
  // tratar, o overlay cobria o app para sempre e parecia que tinha travado.
  it('esconde o overlay quando o arraste é CANCELADO (dragend)', async () => {
    const { api, wrapper } = mountComposable();
    window.dispatchEvent(dragEvent('dragenter'));
    window.dispatchEvent(dragEvent('dragenter')); // filhos aninhados: contador > 1
    await nextTick();
    expect(api.isOverDropZone.value).toBe(true);

    window.dispatchEvent(dragEvent('dragend'));
    await nextTick();
    expect(api.isOverDropZone.value).toBe(false);
    wrapper.unmount();
  });

  it('esconde o overlay quando o cursor sai da janela inteira (relatedTarget nulo)', async () => {
    const { api, wrapper } = mountComposable();
    window.dispatchEvent(dragEvent('dragenter'));
    window.dispatchEvent(dragEvent('dragenter'));
    await nextTick();
    expect(api.isOverDropZone.value).toBe(true);

    window.dispatchEvent(dragEvent('dragleave', { relatedTarget: null }));
    await nextTick();
    expect(api.isOverDropZone.value).toBe(false);
    wrapper.unmount();
  });

  it('entrega os arquivos no drop e esconde o overlay', async () => {
    const onDrop = vi.fn();
    const { api, wrapper } = mountComposable({ onDrop });
    window.dispatchEvent(dragEvent('dragenter'));
    await nextTick();

    window.dispatchEvent(dragEvent('drop', { files: ['a.png', 'b.png'] }));
    await nextTick();
    expect(onDrop).toHaveBeenCalledTimes(1);
    expect(onDrop.mock.calls[0][0]).toHaveLength(2);
    expect(api.isOverDropZone.value).toBe(false);
    wrapper.unmount();
  });

  it('some do caminho quando o drag-drop é desabilitado em runtime', async () => {
    const enabled = ref(true);
    const { api, wrapper } = mountComposable({ enabled });
    window.dispatchEvent(dragEvent('dragenter'));
    await nextTick();
    expect(api.isOverDropZone.value).toBe(true);

    enabled.value = false;
    await nextTick();
    expect(api.isOverDropZone.value).toBe(false);
    wrapper.unmount();
  });

  it('desliga os listeners ao desmontar (não prende overlay de tela antiga)', async () => {
    const onDrop = vi.fn();
    const { wrapper } = mountComposable({ onDrop });
    wrapper.unmount();

    window.dispatchEvent(dragEvent('drop', { files: ['a.png'] }));
    await nextTick();
    expect(onDrop).not.toHaveBeenCalled();
  });
});
