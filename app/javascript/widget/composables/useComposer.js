import { computed, ref, watch } from 'vue';
import { useStore } from 'vuex';

/**
 * O estado do composer — bloco 2.05.
 *
 * Sai de dentro de `ChatInputWrap.vue` para que a casca fique com o que casca
 * deve ter: marcação e delegação. O arquivo original tinha 199 linhas e o aceite
 * 7 exige menos de 60.
 *
 * A COMPOSIÇÃO (IME) É TRATADA AQUI, e não no primitivo: `WComposer` emite
 * `submit` no `Enter` sem olhar `isComposing`. Digitar "café" com teclado de
 * celular ou com dead key passa por um `Enter` que **confirma a composição** —
 * e enviaria a mensagem pela metade. Como o primitivo é de outra trilha e a
 * regra é não alterá-lo, o consumidor se defende: enquanto `compondo` é
 * verdadeiro, `submit` é ignorado. Está registrado no relatório como divergência
 * de contrato a conciliar.
 */
export const useComposer = ({ onSendMessage } = {}) => {
  // `vuex` direto, e não `dashboard/composables/store`: o widget não importa de
  // `dashboard/` — foi o que o bloco 1.08 tirou do grafo para o CSS cair de
  // 1.692.204 B para 100.717 B, e reintroduzir a dependência a traria de volta.
  const store = useStore();
  const isWidgetOpen = computed(
    () => store.getters['appConfig/getIsWidgetOpen']
  );

  const userInput = ref('');
  const compondo = ref(false);
  const campo = ref(null);

  /** Campo vazio (ou só espaço) não envia — e o botão diz isso antes do clique. */
  const podeEnviar = computed(() => Boolean(userInput.value.trim()));

  const focar = () => campo.value?.focus?.();

  const enviar = () => {
    if (compondo.value || !podeEnviar.value) return;
    onSendMessage?.(userInput.value);
    userInput.value = '';
    focar();
  };

  const aoComporInicio = () => {
    compondo.value = true;
  };

  const aoComporFim = () => {
    compondo.value = false;
  };

  const alternarDigitando = status =>
    store.dispatch('conversation/toggleUserTyping', { typingStatus: status });

  // Já existia em `ChatInputWrap.vue:63-68` e continua existindo: o foco ao
  // abrir NÃO é implementado de novo (§C.9 alerta que reimplementar duplicaria
  // a lógica). Só mudou de lugar.
  watch(isWidgetOpen, aberto => {
    if (aberto) focar();
  });

  // O seletor de emoji tambem mora aqui: na casca ele custava tres membros de
  // estado, e o aceite 7 pede menos de 60 linhas la.
  const emojiAberto = ref(false);
  const alternarEmoji = () => {
    emojiAberto.value = !emojiAberto.value;
  };
  const inserirEmoji = ({ value }) => {
    userInput.value = `${userInput.value}${value} `;
  };

  return {
    userInput,
    campo,
    emojiAberto,
    alternarEmoji,
    inserirEmoji,
    podeEnviar,
    compondo,
    enviar,
    focar,
    aoComporInicio,
    aoComporFim,
    aoDigitarInicio: () => alternarDigitando('on'),
    aoDigitarFim: () => alternarDigitando('off'),
  };
};
