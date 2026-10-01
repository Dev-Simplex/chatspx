<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { getUnixTime, parseISO } from 'date-fns';
import { dynamicTime } from 'shared/helpers/timeHelper';

// Selo do espelho da Meta. O estado vem pronto do backend (`meta_status`), com a mesma régua do
// serviço que sincroniza: calcular aqui abriria espaço para o selo e o espelho discordarem.
const props = defineProps({
  produto: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

// Quem usa o selo só o monta com `meta_status` preenchido: oculto não tem estado de espelho.
const ESTADOS = {
  sincronizado: {
    rotulo: 'CATALOG_MGMT.META_STATUS.SINCRONIZADO',
    classes: 'bg-n-teal-3 text-n-teal-11',
  },
  pendente: {
    rotulo: 'CATALOG_MGMT.META_STATUS.PENDENTE',
    classes: 'bg-n-amber-3 text-n-amber-11',
  },
  incompleto: {
    rotulo: 'CATALOG_MGMT.META_STATUS.INCOMPLETO',
    classes: 'bg-n-ruby-3 text-n-ruby-11',
  },
};

const FALTAS = {
  sku: 'CATALOG_MGMT.META_STATUS.MISSING.SKU',
  foto: 'CATALOG_MGMT.META_STATUS.MISSING.FOTO',
  preco: 'CATALOG_MGMT.META_STATUS.MISSING.PRECO',
};

const status = computed(() => props.produto.meta_status);
const estado = computed(() => ESTADOS[status.value]);

const dica = computed(() => {
  if (status.value === 'incompleto') {
    const faltas = (props.produto.meta_missing || []).map(falta =>
      t(FALTAS[falta])
    );
    return t('CATALOG_MGMT.META_STATUS.MISSING_HINT', {
      missing: faltas.join(', '),
    });
  }
  if (status.value === 'pendente')
    return t('CATALOG_MGMT.META_STATUS.PENDING_HINT');
  if (!props.produto.meta_synced_at) return '';

  return t('CATALOG_MGMT.META_STATUS.SYNCED_HINT', {
    time: dynamicTime(getUnixTime(parseISO(props.produto.meta_synced_at))),
  });
});
</script>

<template>
  <span
    v-tooltip.top="dica"
    data-testid="selo-meta"
    class="px-2 py-1 rounded-md text-label-small"
    :class="estado.classes"
  >
    {{ $t(estado.rotulo) }}
  </span>
</template>
