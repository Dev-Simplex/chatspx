<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import { duracao, nivelDaEspera } from './tempo';

// "Tem alguém esperando AGORA, e com quem?" — a única pergunta da tela que pede ação. Por isso
// vem antes dos números do mês. Ignora o período de propósito (o backend já faz assim): lead
// parado desde o mês passado continua sendo problema de hoje.
const props = defineProps({
  // `sem_movimento` do backend: { total, limiar_minutos, leads: [...] }
  parados: { type: Object, required: true },
  decorrido: { type: Number, default: 0 },
  accountId: { type: [Number, String], required: true },
});

const emit = defineEmits(['porQue', 'verTodos']);

const { t } = useI18n();

// Cinco cabem sem empurrar o resto da tela para baixo; o resto fica a um clique, na aba de leads.
const VISIVEIS = 5;

const prazo = computed(() => (props.parados.limiar_minutos || 0) * 60);

const COR = {
  atencao: 'bg-n-amber-9',
  estourou: 'bg-n-ruby-9',
};

const linhas = computed(() =>
  (props.parados.leads || []).slice(0, VISIVEIS).map(lead => {
    const segundos = (lead.minutos_parado || 0) * 60 + props.decorrido;
    const nivel = nivelDaEspera(segundos, prazo.value);
    const tempo = duracao(t, segundos);
    return {
      id: lead.conversation_id,
      lead,
      quem: lead.contato || lead.telefone || `#${lead.display_id}`,
      frase: lead.corretor
        ? t('AGENTS_RODIZIO.NOW.WAITING', {
            nome: lead.corretor.split(' ')[0],
            tempo,
          })
        : t('AGENTS_RODIZIO.NOW.WAITING_QUEUE', { tempo }),
      cor: COR[nivel] || COR.atencao,
      link: frontendURL(
        conversationUrl({ accountId: props.accountId, id: lead.display_id })
      ),
    };
  })
);

const total = computed(() => props.parados.total || 0);

// Vermelho quando alguém já passou do DOBRO do prazo; âmbar quando só passou do prazo.
const estourado = computed(() =>
  (props.parados.leads || []).some(
    lead =>
      prazo.value &&
      (lead.minutos_parado || 0) * 60 + props.decorrido > prazo.value * 2
  )
);

const titulo = computed(() =>
  total.value === 1
    ? t('AGENTS_RODIZIO.NOW.TITLE_ONE')
    : t('AGENTS_RODIZIO.NOW.TITLE_MANY', { n: total.value })
);

const prazoTexto = computed(() =>
  t('AGENTS_RODIZIO.NOW.DEADLINE', { sla: duracao(t, prazo.value) })
);
</script>

<template>
  <section
    v-if="total"
    class="flex flex-col gap-3 px-5 py-4 border rounded-2xl"
    :class="
      estourado
        ? 'bg-n-ruby-2 border-n-ruby-6'
        : 'bg-n-amber-2 border-n-amber-6'
    "
  >
    <div class="flex flex-wrap items-baseline justify-between gap-2">
      <h2
        class="flex items-center gap-2 m-0 text-base font-medium text-n-slate-12"
      >
        <span
          class="i-lucide-alarm-clock size-4"
          :class="estourado ? 'text-n-ruby-11' : 'text-n-amber-11'"
        />
        {{ titulo }}
      </h2>
      <span class="text-xs text-n-slate-11">{{ prazoTexto }}</span>
    </div>

    <ul class="flex flex-col gap-1.5 m-0 list-none">
      <li
        v-for="linha in linhas"
        :key="linha.id"
        class="flex flex-wrap items-center gap-x-3 gap-y-1 px-3 py-2 rounded-lg bg-white dark:bg-n-solid-2"
      >
        <span class="rounded-full size-2.5 shrink-0" :class="linha.cor" />
        <span class="text-sm font-medium text-n-slate-12">
          {{ linha.quem }}
        </span>
        <span class="text-sm tabular-nums text-n-slate-11">
          {{ linha.frase }}
        </span>
        <span class="flex items-center gap-3 ml-auto">
          <button
            class="text-xs underline text-n-slate-10 underline-offset-4"
            @click="emit('porQue', linha.lead)"
          >
            {{ t('AGENTS_RODIZIO.NOW.WHY') }}
          </button>
          <a
            :href="linha.link"
            class="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium border rounded-lg border-n-weak text-n-slate-12 transition-shadow hover:shadow-md"
          >
            <span class="i-lucide-message-circle size-3.5" />
            {{ t('AGENTS_RODIZIO.NOW.OPEN') }}
          </a>
        </span>
      </li>
    </ul>

    <button
      v-if="total > linhas.length"
      class="self-start text-sm underline text-n-slate-11 underline-offset-4"
      @click="emit('verTodos')"
    >
      {{ t('AGENTS_RODIZIO.NOW.SEE_ALL', { n: total }) }}
    </button>
  </section>

  <section
    v-else
    class="flex items-center gap-2 px-5 py-3 bg-white border rounded-2xl dark:bg-n-solid-2 border-n-weak"
  >
    <span class="i-lucide-circle-check size-4 text-n-teal-11" />
    <span class="text-sm text-n-slate-11">
      {{ t('AGENTS_RODIZIO.NOW.NONE') }}
    </span>
  </section>
</template>
