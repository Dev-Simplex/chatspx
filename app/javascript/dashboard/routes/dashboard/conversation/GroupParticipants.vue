<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { formatDistanceToNowStrict } from 'date-fns';
import { enUS, ptBR } from 'date-fns/locale';

import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useGroupConversation } from 'dashboard/composables/useGroupConversation';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { frontendURL } from 'dashboard/helper/URLHelper';
import ContactAPI from 'dashboard/api/contacts';
import GroupParticipantsAPI from 'dashboard/api/groupParticipants';
import GroupParticipantRow from 'dashboard/components-next/GroupParticipants/GroupParticipantRow.vue';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

// Acima disto a lista ganha campo de busca e passa a mostrar só os primeiros.
const COLLAPSED_LIMIT = 8;

/** Larguras do skeleton — irregulares de propósito, para parecer texto real. */
const SKELETON_WIDTHS = ['58%', '42%', '50%'];

const { t, locale } = useI18n();
const store = useStore();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');

const {
  participants,
  participantCount,
  hasSnapshot,
  unresolvedCount,
  syncedAt,
} = useGroupConversation();

const isSyncing = ref(false);
const syncFailed = ref(false);
const searchQuery = ref('');
const isExpanded = ref(false);

const dateLocale = computed(() =>
  String(locale.value || '').startsWith('pt') ? ptBR : enUS
);

const hasSearch = computed(() => participants.value.length > COLLAPSED_LIMIT);

const filteredParticipants = computed(() => {
  const query = searchQuery.value.trim().toLowerCase();
  if (!query) return participants.value;
  return participants.value.filter(participant =>
    [participant.name, participant.formattedPhone, participant.phone]
      .filter(Boolean)
      .some(value => String(value).toLowerCase().includes(query))
  );
});

const visibleParticipants = computed(() => {
  if (isExpanded.value || searchQuery.value) return filteredParticipants.value;
  return filteredParticipants.value.slice(0, COLLAPSED_LIMIT);
});

const hiddenCount = computed(
  () => filteredParticipants.value.length - visibleParticipants.value.length
);

/** Índice onde o bloco de admins termina — vira o separador do design 3.3. */
const adminCount = computed(
  () => visibleParticipants.value.filter(p => p.admin).length
);

const syncedLabel = computed(() => {
  if (!syncedAt.value) return '';
  return t('GROUP_INFO.SYNCED_AT', {
    relative: formatDistanceToNowStrict(syncedAt.value, {
      addSuffix: true,
      locale: dateLocale.value,
    }),
  });
});

/**
 * Rodapé: quando sincronizou e quantos não deram para identificar. Sync em
 * andamento tem prioridade sobre o "sincronizado há X".
 */
const footerText = computed(() => {
  if (isSyncing.value) return t('GROUP_INFO.SYNCING');
  if (!unresolvedCount.value) return syncedLabel.value;

  const partial = t('GROUP_INFO.PARTIALLY_RESOLVED', {
    unresolved: unresolvedCount.value,
    total: participantCount.value,
  });
  return syncedLabel.value ? `${syncedLabel.value} · ${partial}` : partial;
});

/**
 * Skeleton só enquanto NÃO há nada para mostrar. Quando já existe lista, uma
 * sincronização em andamento não pode apagá-la da tela.
 */
const isLoadingFirstList = computed(
  () => isSyncing.value && !participants.value.length
);

const showEmptyState = computed(
  () => !isSyncing.value && !hasSnapshot.value && !participants.value.length
);

/**
 * "Sincronizar agora".
 *
 * O endpoint responde SEMPRE 200 — falha da WAHA não pode quebrar a tela —, e é
 * o corpo (`ok`/`status`) que diz o que aconteceu. Tratar 200 como sucesso aqui
 * faria a UI mentir justamente quando a WAHA está fora.
 */
const syncParticipants = async () => {
  if (isSyncing.value) return;
  isSyncing.value = true;
  syncFailed.value = false;
  try {
    const { data } = await GroupParticipantsAPI.sync(props.conversationId);
    const status = data?.status;

    if (status === 'throttled') {
      // Apertou duas vezes seguidas: nada de errado, só cedo demais.
      useAlert(t('GROUP_INFO.SYNC_THROTTLED'));
      return;
    }
    if (data?.ok === false) {
      syncFailed.value = true;
      return;
    }

    await store.dispatch('getConversation', props.conversationId);
    if (status === 'synced') useAlert(t('GROUP_INFO.SYNC_SUCCESS'));
  } catch {
    // Rede/sessão: mantém a última lista visível, marcada como desatualizada.
    syncFailed.value = true;
  } finally {
    isSyncing.value = false;
  }
};

// --- Popover de ações -----------------------------------------------------
// Clicar num integrante NÃO navega: abrir conversa 1:1 direto tira o agente do
// grupo que ele está lendo. O popover mostra o que dá para fazer e desabilita,
// com tooltip honesto, o que não dá.
const activeParticipant = ref(null);
const popoverStyle = ref({});
const popoverRef = ref(null);
const lookup = ref({ status: 'idle', contactId: null, conversationId: null });

const closePopover = () => {
  activeParticipant.value = null;
};

const handleOutsideClick = event => {
  // A linha do integrante para a propagação (@click.stop); sem isso o mesmo
  // clique que abre o popover chegaria aqui e o fecharia no ato.
  if (popoverRef.value?.contains(event.target)) return;
  closePopover();
};

watch(activeParticipant, async participant => {
  await nextTick();
  if (participant) {
    document.addEventListener('click', handleOutsideClick);
  } else {
    document.removeEventListener('click', handleOutsideClick);
  }
});

onBeforeUnmount(() => {
  document.removeEventListener('click', handleOutsideClick);
});

/**
 * Descobre, sob demanda, se o participante já existe como contato e se ele tem
 * conversa 1:1. Uma requisição por clique — nunca uma por linha da lista.
 */
const resolveContact = async participant => {
  lookup.value = { status: 'loading', contactId: null, conversationId: null };
  if (!participant.phone) {
    lookup.value = { status: 'missing', contactId: null, conversationId: null };
    return;
  }
  try {
    const { data } = await ContactAPI.search(`+${participant.phone}`);
    const contact = (data?.payload || [])[0];
    if (!contact?.id) {
      lookup.value = {
        status: 'missing',
        contactId: null,
        conversationId: null,
      };
      return;
    }
    const { data: conversations } = await ContactAPI.getConversations(
      contact.id
    );
    const list = conversations?.payload || [];
    lookup.value = {
      status: 'found',
      contactId: contact.id,
      conversationId: list[0]?.id || null,
    };
  } catch {
    lookup.value = { status: 'missing', contactId: null, conversationId: null };
  }
};

const openPopover = (participant, anchor) => {
  if (activeParticipant.value?.key === participant.key) {
    closePopover();
    return;
  }
  if (!anchor?.getBoundingClientRect) return;
  const rect = anchor.getBoundingClientRect();
  const estimatedHeight = 190;
  const top =
    rect.bottom + estimatedHeight > window.innerHeight
      ? Math.max(8, rect.top - estimatedHeight)
      : rect.bottom + 4;
  popoverStyle.value = {
    position: 'fixed',
    top: `${top}px`,
    left: `${Math.max(8, rect.left)}px`,
    width: `${Math.min(rect.width, 280)}px`,
    zIndex: 9999,
  };
  activeParticipant.value = participant;
  resolveContact(participant);
};

const canOpenDm = computed(
  () => lookup.value.status === 'found' && Boolean(lookup.value.conversationId)
);

const canViewContact = computed(
  () => lookup.value.status === 'found' && Boolean(lookup.value.contactId)
);

const openDmTooltip = computed(() => {
  if (lookup.value.status === 'loading' || canOpenDm.value) return '';
  return t('GROUP_INFO.ACTIONS.OPEN_DM_DISABLED');
});

const openDm = () => {
  if (!canOpenDm.value) return;
  router.push(
    frontendURL(
      `accounts/${accountId.value}/conversations/${lookup.value.conversationId}`
    )
  );
  closePopover();
};

const viewContact = () => {
  if (!canViewContact.value) return;
  router.push(
    frontendURL(
      `accounts/${accountId.value}/contacts/${lookup.value.contactId}`
    )
  );
  closePopover();
};

const copyPhone = async () => {
  const participant = activeParticipant.value;
  if (!participant?.formattedPhone) return;
  await copyTextToClipboard(participant.formattedPhone);
  useAlert(t('GROUP_INFO.ACTIONS.PHONE_COPIED'));
  closePopover();
};
</script>

<template>
  <div class="flex flex-col group-participants">
    <!-- WAHA fora do ar: avisa, oferece nova tentativa e NUNCA some com a lista. -->
    <div
      v-if="syncFailed"
      class="flex items-start gap-2 px-4 py-2 text-[12px] leading-snug border-b text-n-amber-11 bg-n-amber-3/40 border-n-weak"
    >
      <span class="i-lucide-triangle-alert size-3.5 mt-px flex-shrink-0" />
      <span>
        {{
          participants.length
            ? $t('GROUP_INFO.LOAD_ERROR_KEEPING_LIST')
            : $t('GROUP_INFO.LOAD_ERROR')
        }}
        <button
          type="button"
          class="p-0 font-semibold underline border-0 bg-transparent text-n-amber-11"
          @click="syncParticipants"
        >
          {{ $t('GROUP_INFO.LOAD_ERROR_RETRY') }}
        </button>
      </span>
    </div>

    <!-- Carregando a primeira lista -->
    <div v-if="isLoadingFirstList" class="flex flex-col gap-3 px-4 py-3">
      <div
        v-for="(width, row) in SKELETON_WIDTHS"
        :key="row"
        class="flex items-center gap-2.5 animate-pulse motion-reduce:animate-none"
      >
        <div class="rounded-full size-8 bg-n-slate-4" />
        <div class="flex-1 space-y-1.5">
          <div class="h-2.5 rounded bg-n-slate-4" :style="{ width }" />
          <div class="w-5/12 h-2 rounded bg-n-slate-3" />
        </div>
      </div>
    </div>

    <!-- Nunca sincronizado -->
    <div v-else-if="showEmptyState" class="px-5 py-6 text-center">
      <div
        class="grid mx-auto mb-3 rounded-full size-12 place-items-center bg-n-slate-3"
      >
        <span class="i-lucide-users size-5 text-n-slate-11" />
      </div>
      <h4 class="mb-1 text-[13.5px] font-semibold text-n-slate-12">
        {{ $t('GROUP_INFO.EMPTY_TITLE') }}
      </h4>
      <p class="mb-3.5 text-[12.5px] leading-snug text-n-slate-11">
        {{ $t('GROUP_INFO.EMPTY_BODY') }}
      </p>
      <button
        type="button"
        class="px-3.5 py-1.5 text-[12.5px] font-medium text-white border-0 rounded-lg bg-n-brand hover:bg-n-brand/90"
        @click="syncParticipants"
      >
        {{ $t('GROUP_INFO.SYNC_NOW') }}
      </button>
    </div>

    <template v-else>
      <div v-if="hasSearch" class="px-4 pt-2 pb-1">
        <div class="relative">
          <span
            class="absolute i-lucide-search size-3.5 top-2 left-2.5 text-n-slate-10"
          />
          <input
            v-model="searchQuery"
            type="search"
            :placeholder="$t('GROUP_INFO.SEARCH_PLACEHOLDER')"
            class="w-full h-8 py-1 pl-8 pr-2 text-[13px] border rounded-lg reset-base bg-n-alpha-black2 dark:bg-n-solid-1 border-n-weak text-n-slate-12 focus:outline-none"
          />
        </div>
      </div>

      <template
        v-for="(participant, index) in visibleParticipants"
        :key="participant.key"
      >
        <div
          v-if="index === adminCount && index > 0 && !searchQuery"
          class="h-px mx-4 my-1.5 bg-n-weak"
        />
        <GroupParticipantRow
          :participant="participant"
          :is-active="activeParticipant?.key === participant.key"
          @select="anchor => openPopover(participant, anchor)"
        />
      </template>

      <p
        v-if="!filteredParticipants.length"
        class="px-4 py-3 text-[12.5px] text-n-slate-11"
      >
        {{ $t('CONVERSATION_PARTICIPANTS.NO_RECORDS_FOUND') }}
      </p>

      <button
        v-if="hiddenCount > 0"
        type="button"
        class="px-4 py-2 text-[12.5px] font-medium border-0 bg-transparent text-n-brand"
        @click="isExpanded = true"
      >
        {{ $t('GROUP_INFO.SHOW_ALL', { count: participantCount }) }}
      </button>
      <button
        v-else-if="isExpanded && participants.length > COLLAPSED_LIMIT"
        type="button"
        class="px-4 py-2 text-[12.5px] font-medium border-0 bg-transparent text-n-brand"
        @click="isExpanded = false"
      >
        {{ $t('GROUP_INFO.SHOW_LESS') }}
      </button>

      <div
        class="flex items-start gap-2 px-4 py-2 mt-1 text-[11px] leading-snug border-t text-n-slate-11 border-n-weak"
      >
        <span class="flex-1 min-w-0">{{ footerText }}</span>
        <button
          v-tooltip="$t('GROUP_INFO.SYNC_TOOLTIP')"
          type="button"
          class="p-0 ml-auto border-0 bg-transparent text-n-slate-11 hover:text-n-slate-12"
          :disabled="isSyncing"
          @click="syncParticipants"
        >
          <span
            class="i-lucide-refresh-cw size-3.5"
            :class="{ 'animate-spin motion-reduce:animate-none': isSyncing }"
          />
        </button>
      </div>
    </template>

    <Teleport to="body">
      <div
        v-if="activeParticipant"
        ref="popoverRef"
        :style="popoverStyle"
        class="flex flex-col p-1 border shadow-lg rounded-xl border-n-weak bg-n-solid-1"
      >
        <div class="px-3 py-2 border-b border-n-weak">
          <p class="mb-0 text-[13px] font-medium truncate text-n-slate-12">
            {{
              activeParticipant.isUnknown
                ? $t('GROUP_INFO.UNKNOWN_PARTICIPANT')
                : activeParticipant.name || activeParticipant.formattedPhone
            }}
          </p>
          <p
            v-if="activeParticipant.name && activeParticipant.formattedPhone"
            class="mb-0 text-[11.5px] text-n-slate-11 tabular-nums"
          >
            {{ activeParticipant.formattedPhone }}
          </p>
        </div>
        <span v-tooltip="openDmTooltip" class="block">
          <button
            type="button"
            class="inline-flex items-center w-full h-8 gap-2 px-3 text-[13px] border-0 rounded-lg bg-transparent text-n-slate-12 hover:bg-n-slate-3/50 disabled:opacity-50"
            :disabled="!canOpenDm"
            @click="openDm"
          >
            <span class="i-lucide-message-circle size-3.5" />
            {{ $t('GROUP_INFO.ACTIONS.OPEN_DM') }}
          </button>
        </span>
        <span v-tooltip="canViewContact ? '' : openDmTooltip" class="block">
          <button
            type="button"
            class="inline-flex items-center w-full h-8 gap-2 px-3 text-[13px] border-0 rounded-lg bg-transparent text-n-slate-12 hover:bg-n-slate-3/50 disabled:opacity-50"
            :disabled="!canViewContact"
            @click="viewContact"
          >
            <span class="i-lucide-user size-3.5" />
            {{ $t('GROUP_INFO.ACTIONS.VIEW_CONTACT') }}
          </button>
        </span>
        <span
          v-tooltip="
            activeParticipant.formattedPhone
              ? ''
              : $t('GROUP_INFO.ACTIONS.COPY_PHONE_DISABLED')
          "
          class="block"
        >
          <button
            type="button"
            class="inline-flex items-center w-full h-8 gap-2 px-3 text-[13px] border-0 rounded-lg bg-transparent text-n-slate-12 hover:bg-n-slate-3/50 disabled:opacity-50"
            :disabled="!activeParticipant.formattedPhone"
            @click="copyPhone"
          >
            <span class="i-lucide-copy size-3.5" />
            {{ $t('GROUP_INFO.ACTIONS.COPY_PHONE') }}
          </button>
        </span>
      </div>
    </Teleport>
  </div>
</template>
