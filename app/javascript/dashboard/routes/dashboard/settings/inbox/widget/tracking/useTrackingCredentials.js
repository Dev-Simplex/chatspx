/* global axios */
/**
 * As credenciais da inbox, do lado da tela (bloco 5.06, consumindo o 5.02).
 *
 * O 5.02 e quem guarda: tabela cifrada, `TrackingCredential`. Esta tela NUNCA
 * ve o segredo — nem para exibir, nem para reenviar. O contrato de leitura tem
 * dois campos e so dois:
 *
 *     { configured: true, last_four: "9f2a" }
 *
 * `last_four` existe para uma pergunta que o administrador faz de verdade:
 * "o token que esta ai e o novo ou o antigo?". Quatro caracteres respondem
 * isso e nao reconstituem nada. O segredo inteiro nunca volta do servidor.
 *
 * A REGRA DO SENTIDO CONTRARIO, que ja custou caro nesta base: **salvar sem
 * re-exibir nao pode APAGAR**. Por isso a escrita e um `PUT` por credencial,
 * disparado so quando o administrador digita um valor novo — e nao um campo
 * dentro do PATCH da inbox. Se o segredo viajasse junto do formulario, abrir a
 * tela e salvar outra coisa mandaria string vazia e apagaria a credencial, que
 * e exatamente o defeito documentado em `SecretField.vue`.
 *
 * Enquanto o 5.02 nao subir, o `GET` responde 404: a tela desabilita os campos
 * e diz por que, nomeando o bloco. Inventar um cofre local aqui seria pior que
 * nao ter nenhum.
 */
import { ref } from 'vue';

/** As duas credenciais desta tela. O `send_to` do Ads e publico, nao entra. */
export const CREDENTIAL_KEYS = Object.freeze([
  'meta_access_token',
  'ga4_api_secret',
]);

// O caminho e SINGULAR de proposito. A rota e `resource :tracking_credential` (nao `resources`),
// porque ha no maximo uma credencial por inbox — UNIQUE no banco. O Rails resolve o `resource`
// singular para um controller PLURAL, e essa assimetria confunde: o controller se chama
// TrackingCredentialsController, mas a URL que ele serve e /tracking_credential.
//
// Esta linha dizia `tracking_credentials` e dava 404 em toda chamada — front e backend foram
// escritos por trilhas diferentes, cada uma com a sua suposicao, e nenhum teste cruzava as duas.
// Achado em navegador real; nenhum spec pegava, porque o do front dubla a chamada HTTP e o do
// backend chama o controller direto, sem passar pela rota.
const baseUrl = (accountId, inboxId) =>
  `/api/v1/accounts/${accountId}/inboxes/${inboxId}/tracking_credential`;

const accountIdFromRoute = () => {
  const { pathname } = window.location;
  if (!pathname.includes('/app/accounts')) return '';

  return pathname.split('/')[3] ?? '';
};

/** So `configured` e `last_four` atravessam — o resto e descartado por omissao. */
const readState = (raw = {}) => ({
  configured: Boolean(raw.configured),
  lastFour: typeof raw.last_four === 'string' ? raw.last_four.slice(-4) : '',
});

const emptyState = () =>
  Object.fromEntries(
    CREDENTIAL_KEYS.map(key => [key, { configured: false, lastFour: '' }])
  );

export function useTrackingCredentials(inboxId) {
  const credentials = ref(emptyState());
  const isLoading = ref(false);
  /** `true` enquanto o cofre do 5.02 nao existir: a tela desabilita e explica. */
  const vaultUnavailable = ref(true);
  const saveError = ref('');

  const carregar = async () => {
    isLoading.value = true;
    try {
      const { data } = await axios.get(baseUrl(accountIdFromRoute(), inboxId));
      const lidas = data?.credentials ?? {};
      credentials.value = Object.fromEntries(
        CREDENTIAL_KEYS.map(key => [key, readState(lidas[key])])
      );
      vaultUnavailable.value = false;
    } catch (error) {
      // 404 = o 5.02 ainda nao subiu. Nao e erro do administrador, e ausencia
      // de recurso — e a tela precisa dizer isso com o numero do bloco.
      credentials.value = emptyState();
      vaultUnavailable.value = true;
      const status = error?.response?.status;
      if (status && status !== 404 && status !== 501) {
        saveError.value = error?.message ?? '';
      }
    } finally {
      isLoading.value = false;
    }
  };

  /**
   * Grava UMA credencial. So e chamada quando ha valor novo — a ausencia de
   * chamada e o que significa "mantenha o que esta guardado".
   */
  const guardar = async (key, value) => {
    saveError.value = '';
    try {
      const { data } = await axios.put(
        `${baseUrl(accountIdFromRoute(), inboxId)}/${key}`,
        { value }
      );
      credentials.value = {
        ...credentials.value,
        [key]: readState(data?.credential),
      };
      return true;
    } catch (error) {
      saveError.value = error?.message ?? '';
      return false;
    }
  };

  return {
    credentials,
    isLoading,
    vaultUnavailable,
    saveError,
    carregar,
    guardar,
  };
}
