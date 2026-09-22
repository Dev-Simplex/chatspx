<script setup>
import { onMounted, computed, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import AttendanceList from 'dashboard/components-next/Contacts/Pages/AttendanceList.vue';

// Página PRÓPRIA em vez de mais um modo dentro do ContactsIndex: aquele arquivo
// serve 4 rotas e é todo costurado em torno do store de contatos (busca,
// ordenação, segmentos, filtros, ações em massa). Um atendimento não tem nada
// disso, e cada branch a mais ali é risco para as abas que já funcionam. O preço
// é redesenhar o cabeçalho/rodapé — ~20 linhas, contra ~5 flags novas atravessando
// 3 componentes compartilhados.
const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const attendances = useMapGetter('activeAttendances/getAttendances');
const meta = useMapGetter('activeAttendances/getMeta');
const uiFlags = useMapGetter('activeAttendances/getUIFlags');
const currentUserId = useMapGetter('getCurrentUserID');
const accountId = useMapGetter('getCurrentAccountId');
// Observado p/ refazer a lista quando um pedido muda de estado via realtime.
const takeoverRecords = useMapGetter('takeoverRequests/getIncoming');

// display_id da conversa com ação em andamento (loading naquele card).
const busyId = ref(null);

const isFetching = computed(() => uiFlags.value.isFetching);
const hasError = computed(() => uiFlags.value.hasError);
const hasAttendances = computed(() => attendances.value.length > 0);
const currentPage = computed(() => Number(meta.value?.currentPage) || 1);
const totalItems = computed(() => meta.value?.count ?? 0);
// per_page vem do backend: duplicar o 15 aqui faria o PaginationFooter calcular
// o total de páginas errado no dia em que o controller mudasse o seu.
const itemsPerPage = computed(() => Number(meta.value?.perPage) || 15);
const pageFromRoute = computed(() => Number(route.query?.page) || 1);

// A busca mora na URL junto da página: recarregar, voltar no navegador ou mandar o link para um
// colega tem de cair na mesma lista. O campo é o espelho local, para digitar sem uma navegação por
// tecla.
const termoDaRota = computed(() => route.query?.q || '');
const termo = ref(termoDaRota.value);
// Menos de 2 caracteres não filtra nada (o backend aplica a mesma régua).
const buscaAtiva = computed(() => termoDaRota.value.trim().length >= 2);

const fetchAttendances = async (page = 1) => {
  const q = termoDaRota.value.trim();
  try {
    await store.dispatch('activeAttendances/get', { page, q });
  } catch {
    // o store já marcou hasError; a tela mostra o estado de erro + "Tentar de novo"
    return;
  }
  if (Number(route.query?.page || 1) !== page) {
    router.replace({ query: { ...route.query, page: String(page) } });
  }
};

// Buscar SEMPRE volta para a página 1: procurar estando na página 5 devolveria "nada encontrado"
// para um termo com resultado na primeira.
let esperaDaBusca = null;
const onBuscar = valor => {
  termo.value = valor;
  clearTimeout(esperaDaBusca);
  esperaDaBusca = setTimeout(() => {
    const novo = valor.trim();
    if (novo === termoDaRota.value.trim()) return;

    const query = { ...route.query, page: '1' };
    if (novo) query.q = novo;
    else delete query.q;
    router.replace({ query });
  }, 300);
};

const limparBusca = () => {
  clearTimeout(esperaDaBusca);
  termo.value = '';
  const query = { ...route.query, page: '1' };
  delete query.q;
  router.replace({ query });
};

// O termo mudou na URL (digitação, limpar, voltar do navegador) → refaz a lista.
watch(termoDaRota, valor => {
  termo.value = valor;
  fetchAttendances(1);
});

// Voltar/avançar no navegador muda só a query — sem isto a lista ficaria na
// página anterior enquanto a URL diz outra. A guarda contra currentPage evita o
// laço com o router.replace do próprio fetch.
watch(pageFromRoute, page => {
  if (page !== currentPage.value) fetchAttendances(page);
});

// Solicitar o atendimento direto da aba (D1 / Fase 3). O endpoint é
// conversa-scoped e passa pelo authorize_team_access: pedir uma conversa de
// outro TIME dá 403 (não posso pedir o que não enxergo) — tratado com mensagem
// clara em vez de erro genérico.
const TAKEOVER_ERROR_KEYS = {
  conversation_unassigned:
    'CONTACTS_LAYOUT.IN_ATTENDANCE.REQUEST.ERRORS.UNASSIGNED',
  conversation_owned_by_bot: 'CONTACTS_LAYOUT.IN_ATTENDANCE.REQUEST.ERRORS.BOT',
  takeover_request_exists:
    'CONTACTS_LAYOUT.IN_ATTENDANCE.REQUEST.ERRORS.EXISTS',
  takeover_request_self: 'CONTACTS_LAYOUT.IN_ATTENDANCE.REQUEST.ERRORS.SELF',
};

const alertForError = error => {
  const status = error?.response?.status;
  const code = error?.response?.data?.error_code;
  if (status === 403) {
    useAlert(t('CONTACTS_LAYOUT.IN_ATTENDANCE.REQUEST.ERRORS.NO_ACCESS'));
  } else if (code && TAKEOVER_ERROR_KEYS[code]) {
    useAlert(t(TAKEOVER_ERROR_KEYS[code]));
  } else {
    useAlert(t('CONTACTS_LAYOUT.IN_ATTENDANCE.REQUEST.ERRORS.GENERIC'));
  }
};

const goToConversation = conversationId => {
  router.push(
    `/app/accounts/${accountId.value}/conversations/${conversationId}`
  );
};

// Toda ação da linha passa por aqui: trava a linha (loading), age, refaz a lista
// (a linha muda de estado: assumir vira "Abrir", pedir vira "Pedido enviado") e
// traduz o erro. Refetch SEMPRE, inclusive no erro — se falhou por corrida
// (alguém assumiu antes), a lista precisa refletir a verdade nova.
const runRowAction = async ({
  conversationId,
  action,
  successKey,
  navigateTo = null,
}) => {
  if (busyId.value) return;
  busyId.value = conversationId;
  let succeeded = false;
  try {
    await action();
    succeeded = true;
    useAlert(t(successKey));
  } catch (error) {
    alertForError(error);
  } finally {
    busyId.value = null;
  }

  // Só navega se deu certo — senão o erro sumiria da vista junto com a página.
  if (succeeded && navigateTo) {
    goToConversation(navigateTo);
    return;
  }
  // Refaz a lista p/ a linha refletir o novo estado (assumir → Abrir, pedir →
  // "Pedido enviado"). Também no erro: se falhou por corrida, a verdade mudou.
  await fetchAttendances(pageFromRoute.value);
};

const onOpenConversation = ({ conversationId }) =>
  goToConversation(conversationId);

// ATENÇÃO: 'assignAgent' é RAIZ, não 'conversations/assignAgent'. O módulo
// conversations NÃO é namespaced (store/modules/conversations/index.js exporta
// sem `namespaced: true`), e o Vuex, ao receber uma action inexistente, apenas
// loga e devolve undefined — o await RESOLVE e o alerta cantava "assumido" sem
// ter atribuído nada. Foi exatamente esse o bug do falso sucesso.
const onAssumeAttendance = ({ conversationId }) =>
  runRowAction({
    conversationId,
    successKey: 'CONTACTS_LAYOUT.IN_ATTENDANCE.ASSUMED',
    // Assumiu = quer atender: vai direto para a conversa.
    navigateTo: conversationId,
    action: () =>
      store.dispatch('assignAgent', {
        conversationId,
        agentId: currentUserId.value,
        rethrow: true, // sem isto o store engole o erro e o alerta mentiria
      }),
  });

const onRequestAttendance = ({ conversationId }) =>
  runRowAction({
    conversationId,
    successKey: 'CONTACTS_LAYOUT.IN_ATTENDANCE.REQUEST.SENT',
    action: () => store.dispatch('takeoverRequests/create', { conversationId }),
  });

const onCancelRequest = ({ conversationId, requestId }) =>
  runRowAction({
    conversationId,
    successKey: 'CONTACTS_LAYOUT.IN_ATTENDANCE.REQUEST.CANCELLED',
    action: () => store.dispatch('takeoverRequests/cancel', { id: requestId }),
  });

// O dono aprovou/negou enquanto a aba está aberta → a linha precisa mudar de
// estado sem F5. handleRealtimeEvent é o ponto único desses eventos; observar o
// store de pedidos cobre criado/aprovado/negado/cancelado de uma vez.
watch(takeoverRecords, () => fetchAttendances(pageFromRoute.value));

onMounted(() => fetchAttendances(pageFromRoute.value));
</script>

<template>
  <div
    class="flex flex-col justify-between flex-1 h-full m-0 overflow-auto bg-n-surface-1"
  >
    <section
      class="flex w-full h-full gap-4 overflow-hidden justify-evenly bg-n-surface-1"
    >
      <div class="flex flex-col w-full h-full">
        <header class="sticky top-0 z-10 px-6">
          <div
            class="flex items-center justify-between w-full py-6 mx-auto max-w-5xl"
          >
            <span class="text-xl font-medium truncate text-n-slate-12">
              {{ t('CONTACTS_LAYOUT.HEADER.IN_ATTENDANCE_TITLE') }}
            </span>
            <div class="relative w-full max-w-xs ltr:ml-4 rtl:mr-4">
              <Icon
                icon="i-lucide-search"
                class="absolute size-4 -translate-y-1/2 pointer-events-none ltr:left-3 rtl:right-3 top-1/2 text-n-slate-10"
              />
              <!-- reset-base: o CSS global de input tem padding proprio e venceria o do Tailwind. -->
              <input
                :value="termo"
                type="text"
                class="w-full h-10 text-sm rounded-lg reset-base ltr:pl-9 ltr:pr-3 rtl:pr-9 rtl:pl-3 outline outline-1 outline-n-weak bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10"
                :placeholder="
                  t('CONTACTS_LAYOUT.IN_ATTENDANCE.SEARCH_PLACEHOLDER')
                "
                :aria-label="
                  t('CONTACTS_LAYOUT.IN_ATTENDANCE.SEARCH_PLACEHOLDER')
                "
                @input="onBuscar($event.target.value)"
              />
            </div>
            <div class="relative w-full max-w-xs ltr:ml-4 rtl:mr-4">
              <Icon
                icon="i-lucide-search"
                class="absolute size-4 -translate-y-1/2 pointer-events-none ltr:left-3 rtl:right-3 top-1/2 text-n-slate-10"
              />
              <!-- reset-base: o CSS global de input tem padding próprio e venceria o do Tailwind. -->
              <input
                :value="termo"
                type="text"
                class="w-full h-10 text-sm rounded-lg reset-base ltr:pl-9 ltr:pr-3 rtl:pr-9 rtl:pl-3 outline outline-1 outline-n-weak bg-n-alpha-black2 text-n-slate-12 placeholder:text-n-slate-10"
                :placeholder="
                  t('CONTACTS_LAYOUT.IN_ATTENDANCE.SEARCH_PLACEHOLDER')
                "
                :aria-label="
                  t('CONTACTS_LAYOUT.IN_ATTENDANCE.SEARCH_PLACEHOLDER')
                "
                @input="onBuscar($event.target.value)"
              />
            </div>
          </div>
        </header>

        <main class="flex-1 px-6 overflow-y-auto">
          <div class="w-full mx-auto max-w-5xl">
            <div
              v-if="isFetching"
              class="flex items-center justify-center py-10 text-n-slate-11"
            >
              <Spinner />
            </div>
            <div
              v-else-if="hasError"
              class="flex flex-col items-center justify-center gap-3 py-10"
            >
              <span class="text-base text-n-slate-11">
                {{ t('CONTACTS_LAYOUT.IN_ATTENDANCE.LOAD_ERROR') }}
              </span>
              <Button
                size="sm"
                variant="faded"
                color="slate"
                :label="t('CONTACTS_LAYOUT.IN_ATTENDANCE.RETRY')"
                @click="fetchAttendances(pageFromRoute)"
              />
            </div>
            <!-- Vazio de busca e vazio de verdade são respostas OPOSTAS: dizer "ninguém em
                 atendimento" a quem acabou de digitar um nome é a mesma mentira que a aba
                 existe para evitar. -->
            <div
              v-else-if="!hasAttendances && buscaAtiva"
              class="flex flex-col items-center justify-center gap-3 py-10"
            >
              <span class="text-base text-n-slate-11">
                {{
                  t('CONTACTS_LAYOUT.IN_ATTENDANCE.SEARCH_EMPTY', {
                    termo: termoDaRota,
                  })
                }}
              </span>
              <Button
                size="sm"
                variant="faded"
                color="slate"
                :label="t('CONTACTS_LAYOUT.IN_ATTENDANCE.SEARCH_CLEAR')"
                @click="limparBusca"
              />
            </div>
            <div
              v-else-if="!hasAttendances"
              class="flex items-center justify-center py-10"
            >
              <span class="text-base text-n-slate-11">
                {{
                  t(
                    'CONTACTS_LAYOUT.EMPTY_STATE.IN_ATTENDANCE_EMPTY_STATE_TITLE'
                  )
                }}
              </span>
            </div>
            <div v-else class="flex flex-col gap-4 pt-4 pb-6">
              <AttendanceList
                :attendances="attendances"
                :busy-id="busyId"
                @open-conversation="onOpenConversation"
                @assume-attendance="onAssumeAttendance"
                @request-attendance="onRequestAttendance"
                @cancel-request="onCancelRequest"
              />
            </div>
          </div>
        </main>

        <!-- totalItems, não hasAttendances: com ?page=99 a lista vem vazia e
             esconder o rodapé deixaria o usuário preso sem como voltar. -->
        <footer
          v-if="!isFetching && !hasError && totalItems > 0"
          class="sticky bottom-0 z-0"
        >
          <!-- Chave própria: a do contacts diz "de 21 contatos", e a linha aqui é
               um ATENDIMENTO — 21 atendimentos são 20 contatos distintos no
               staging hoje, então o rótulo emprestado é literalmente falso. -->
          <PaginationFooter
            current-page-info="CONTACTS_LAYOUT.IN_ATTENDANCE.PAGINATION_SHOWING"
            :current-page="currentPage"
            :total-items="totalItems"
            :items-per-page="itemsPerPage"
            class="max-w-[67rem]"
            @update:current-page="fetchAttendances"
          />
        </footer>
      </div>
    </section>
  </div>
</template>
