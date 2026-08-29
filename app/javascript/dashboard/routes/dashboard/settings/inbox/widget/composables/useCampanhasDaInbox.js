import { computed, onMounted, unref } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';

/**
 * O CARREGAMENTO das campanhas de chat ao vivo — blocos 4.05 e 4.22.
 *
 * As duas seções da tela de gatilhos que falam de campanha (o compositor do
 * teaser, 4.05, e a seção "modo antigo", 4.22) leem `campaigns/*` do store. Só
 * que nada na rota da caixa de entrada despachava `campaigns/get`: em visita
 * direta ou F5 — o caminho normal de quem abre Configurações da caixa por link
 * ou recarrega a página — a lista chega VAZIA. O compositor então mostra "esta
 * caixa ainda não tem campanha", que é falso, e a seção "modo antigo" (que vive
 * sob `v-if="legadas.length"`) simplesmente não existe na tela.
 *
 * Por que um lugar só, e não uma linha em cada componente: os dois consumidores
 * vivem na MESMA tela e montam no mesmo tique, então dois `onMounted` seriam duas
 * requisições para a mesma lista. A guarda é o próprio `isFetching` do módulo
 * Vuex, que a action liga ANTES do primeiro `await` — logo, de forma síncrona no
 * `dispatch`: o segundo consumidor já o encontra ligado e não repete a busca.
 * Hoje quem chama é a seção "modo antigo"; o compositor do teaser é o segundo
 * consumidor previsto, e é para ele que a guarda existe desde já.
 *
 * O que esta função NÃO faz: cachear entre montagens. Abrir a aba de gatilhos
 * recarrega a lista de propósito — a alternativa (só buscar se o store estiver
 * vazio) deixaria a tela mostrando campanha apagada em outra aba do navegador.
 */
export function useCampanhasDaInbox(inboxId) {
  const store = useStore();

  const todas = useMapGetter('campaigns/getLiveChatCampaigns');
  const uiFlags = useMapGetter('campaigns/getUIFlags');

  /**
   * Devolve a promessa do `dispatch` quando ele acontece, e `null` quando foi
   * dispensado por já haver uma busca em voo — o teste precisa distinguir os
   * dois casos, senão "não buscou" e "buscou" ficam indistinguíveis.
   */
  const carregar = () => {
    if (uiFlags.value?.isFetching) return null;
    return store.dispatch('campaigns/get');
  };

  onMounted(carregar);

  /**
   * As campanhas DESTA caixa. O payload que o store guarda traz a caixa ANINHADA
   * em `inbox` — é a única forma que o serializador produz
   * (`api/v1/models/_campaign.json.jbuilder:5-7`), e `inbox_id` plano só existe
   * do lado do REQUEST, no formulário de campanha. A queda para `inbox_id` fica
   * como rede, não como caminho esperado.
   */
  const daInbox = computed(() =>
    todas.value.filter(
      campanha =>
        Number(campanha.inbox?.id ?? campanha.inbox_id) ===
        Number(unref(inboxId))
    )
  );

  return { todas, daInbox, uiFlags, carregar };
}

export default useCampanhasDaInbox;
