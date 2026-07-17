<script setup>
import { onMounted, computed, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';

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

const isFetching = computed(() => uiFlags.value.isFetching);
const hasError = computed(() => uiFlags.value.hasError);
const hasAttendances = computed(() => attendances.value.length > 0);
const currentPage = computed(() => Number(meta.value?.currentPage) || 1);
const totalItems = computed(() => meta.value?.count ?? 0);
// per_page vem do backend: duplicar o 15 aqui faria o PaginationFooter calcular
// o total de páginas errado no dia em que o controller mudasse o seu.
const itemsPerPage = computed(() => Number(meta.value?.perPage) || 15);
const pageFromRoute = computed(() => Number(route.query?.page) || 1);

const fetchAttendances = async (page = 1) => {
  try {
    await store.dispatch('activeAttendances/get', { page });
  } catch {
    // o store já marcou hasError; a tela mostra o estado de erro + "Tentar de novo"
    return;
  }
  if (Number(route.query?.page || 1) !== page) {
    router.replace({ query: { ...route.query, page: String(page) } });
  }
};

// Voltar/avançar no navegador muda só a query — sem isto a lista ficaria na
// página anterior enquanto a URL diz outra. A guarda contra currentPage evita o
// laço com o router.replace do próprio fetch.
watch(pageFromRoute, page => {
  if (page !== currentPage.value) fetchAttendances(page);
});

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
              <AttendanceList :attendances="attendances" />
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
