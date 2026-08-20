import { computed, getCurrentScope, onScopeDispose, ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

const isDarkModeAuto = mode => mode === 'auto';
const isDarkMode = mode => mode === 'dark';

const DARK_QUERY = '(prefers-color-scheme: dark)';

// `window.matchMedia` pode não existir (WebView antiga, jsdom sem shim) e pode
// existir devolvendo `undefined` num dublê de teste. As duas coisas caem no
// mesmo lugar: sem MediaQueryList, a preferência do sistema é "claro" e o
// widget segue funcionando — a mesma degradação de antes, agora explícita.
const consultarSistema = () => {
  try {
    return window.matchMedia?.(DARK_QUERY) ?? null;
  } catch {
    // Um `matchMedia` que lança (já visto em WebView embarcada) não pode
    // derrubar o widget inteiro por causa da cor de fundo.
    return null;
  }
};

const calculatePrefersDarkMode = (mode, systemPreference) =>
  isDarkModeAuto(mode) ? systemPreference : isDarkMode(mode);

/**
 * Composable for handling dark mode.
 *
 * BLOCO 2.10 — por que a preferência do sistema virou `ref` com ouvinte.
 *
 * Antes:  `const systemPreference = computed(getSystemPreference)`, com
 * `getSystemPreference` lendo `window.matchMedia(...).matches`.
 *
 * Um `computed` do Vue só reavalia quando uma dependência REATIVA muda, e
 * `matchMedia().matches` não é reativo: é uma leitura simples de propriedade.
 * Na prática o valor congelava na primeira avaliação. Com `darkMode: 'auto'`,
 * o visitante que trocasse o tema do sistema com o chat aberto ficava preso no
 * tema antigo até remontar o widget — que é justamente o que o aceite proíbe.
 *
 * O `MediaQueryList` já emite `change` quando o SO troca de tema; o que
 * faltava era alguém escutando e um `ref` para o Vue observar.
 *
 * O ouvinte é POR CHAMADA, não um singleton de módulo. Um singleton
 * pareceria mais econômico, mas amarraria o valor à primeira montagem do
 * primeiro componente e tornaria o estado impossível de reinicializar entre
 * testes. São dois ouvintes no app inteiro (`App.vue` e `ConversationWrap`),
 * ambos liberados no `onScopeDispose`.
 *
 * @returns {Object} An object containing computed properties and methods for dark mode.
 */
export function useDarkMode() {
  const darkMode = useMapGetter('appConfig/darkMode');

  const mediaQueryList = consultarSistema();
  const systemPreference = ref(mediaQueryList?.matches ?? false);

  const aoTrocarTemaDoSistema = evento => {
    systemPreference.value = evento.matches;
  };

  // `addEventListener` é o caminho padrão; `addListener` é o depreciado que
  // Safari < 14 ainda é o único a oferecer — e Safari velho é exatamente o
  // navegador que sobra num widget embarcado em site de terceiro.
  if (mediaQueryList?.addEventListener) {
    mediaQueryList.addEventListener('change', aoTrocarTemaDoSistema);
  } else if (mediaQueryList?.addListener) {
    mediaQueryList.addListener(aoTrocarTemaDoSistema);
  }

  // Sem isto, cada remount de `ConversationWrap` deixaria um ouvinte preso a um
  // `ref` órfão. `getCurrentScope` protege o uso fora de um `setup()`, onde
  // `onScopeDispose` só emitiria aviso.
  if (getCurrentScope()) {
    onScopeDispose(() => {
      if (mediaQueryList?.removeEventListener) {
        mediaQueryList.removeEventListener('change', aoTrocarTemaDoSistema);
      } else if (mediaQueryList?.removeListener) {
        mediaQueryList.removeListener(aoTrocarTemaDoSistema);
      }
    });
  }

  const prefersDarkMode = computed(() =>
    calculatePrefersDarkMode(darkMode.value, systemPreference.value)
  );

  return {
    darkMode,
    prefersDarkMode,
  };
}
