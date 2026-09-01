import { computed, onMounted } from 'vue';
import { useCaptainConfigStore } from 'dashboard/store/captain/preferences';
import { useAccount } from './useAccount';

/**
 * Modelo de LLM que os Agentes IA realmente usam.
 *
 * O modelo NÃO é do agente: é da CONTA. Quem resolve no backend é
 * `Agentable#agent_model`, que lê `account.captain_assistant_model` (com fallback
 * para o default). O payload do assistant (`_assistant.json.jbuilder`) não devolve
 * `config.model` nem `config.llm_model` — ler essas chaves dava sempre vazio, e a
 * tela mostrava um espaço em branco no lugar de um modelo.
 *
 * A fonte equivalente no front é a store de preferências: `features.assistant`
 * traz `selected` (o que a conta escolheu) com fallback para `default`, os mesmos
 * dois níveis do backend.
 *
 * @returns {{ assistantModel: import('vue').ComputedRef<string|null> }}
 *   `assistantModel` é `null` enquanto as preferências não chegaram, ou se a conta
 *   não tem modelo resolvível. Quem consome deve esconder o campo nesse caso —
 *   nunca renderizar string vazia como se fosse um modelo.
 */
export function useCaptainAssistantModel() {
  const captainConfigStore = useCaptainConfigStore();
  const { accountId } = useAccount();

  onMounted(() => {
    captainConfigStore.fetch({ accountId: accountId.value });
  });

  const assistantModel = computed(
    () => captainConfigStore.getSelectedModelForFeature('assistant') || null
  );

  return { assistantModel };
}
