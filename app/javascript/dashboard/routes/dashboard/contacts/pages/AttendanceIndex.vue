<script setup>
import { onMounted, computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import AttendanceList from 'dashboard/components-next/Contacts/Pages/AttendanceList.vue';

// Página PRÓPRIA em vez de mais um modo dentro do ContactsIndex: aquele arquivo
// serve 4 rotas e é todo costurado em torno do store de contatos (busca,
// ordenação, segmentos, filtros, ações em massa). Um atendimento não tem nada
// disso, e cada branch a mais ali é risco para as abas que já funcionam. O preço
// é redesenhar o cabeçalho/rodapé — ~20 linhas, contra ~5 flags novas atravessando
// 3 componentes compartilhados.
const ITEMS_PER_PAGE = 15;

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const attendances = useMapGetter('activeAttendances/getAttendances');
const meta = useMapGetter('activeAttendances/getMeta');
const uiFlags = useMapGetter('activeAttendances/getUIFlags');

const isFetching = computed(() => uiFlags.value.isFetching);
const hasAttendances = computed(() => attendances.value.length > 0);
const currentPage = computed(() => Number(meta.value?.currentPage) || 1);
const totalItems = computed(() => meta.value?.count ?? 0);
const pageFromRoute = computed(() => Number(route.query?.page) || 1);

const fetchAttendances = async (page = 1) => {
  await store.dispatch('activeAttendances/get', { page });
  if (Number(route.query?.page || 1) !== page) {
    router.replace({ query: { ...route.query, page: String(page) } });
  }
};

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

        <footer
          v-if="!isFetching && hasAttendances"
          class="sticky bottom-0 z-0"
        >
          <PaginationFooter
            current-page-info="CONTACTS_LAYOUT.PAGINATION_FOOTER.SHOWING"
            :current-page="currentPage"
            :total-items="totalItems"
            :items-per-page="ITEMS_PER_PAGE"
            class="max-w-[67rem]"
            @update:current-page="fetchAttendances"
          />
        </footer>
      </div>
    </section>
  </div>
</template>
