<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import AccountFeaturesAPI from 'dashboard/api/accountFeatures';
import SectionLayout from './SectionLayout.vue';
import Switch from 'next/switch/Switch.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Ligar e desligar feature da conta pela TELA. Antes disto só havia o console, o super_admin ou a
// Platform API, e o resultado prático era a mesma funcionalidade existir numa máquina e não noutra.
//
// A lista NÃO é escrita aqui: vem do backend, derivada do `config/features.yml`. É de propósito —
// uma lista mantida no front vira segunda fonte de verdade e sai de sincronia, que é exatamente o
// que aconteceu com `dashboard/featureFlags.js`, hoje já defasado em relação ao YAML.
const { t } = useI18n();

const carregando = ref(true);
const salvando = ref(null);
const features = ref([]);

const carregar = async () => {
  carregando.value = true;
  try {
    const { data } = await AccountFeaturesAPI.get();
    features.value = data.features || [];
  } catch (erro) {
    useAlert(t('GENERAL_SETTINGS.FORM.FEATURES.API.ERROR'));
  }
  carregando.value = false;
};

onMounted(carregar);

// Três grupos, e a ordem importa: o que o produto entrega vem primeiro, e o que exige preparo fica
// embaixo com o motivo à vista.
const grupos = computed(() =>
  [
    {
      chave: 'ativas',
      titulo: t('GENERAL_SETTINGS.FORM.FEATURES.GROUPS.ON'),
      itens: features.value.filter(f => f.enabled && f.available),
    },
    {
      chave: 'disponiveis',
      titulo: t('GENERAL_SETTINGS.FORM.FEATURES.GROUPS.OFF'),
      itens: features.value.filter(f => !f.enabled && f.available),
    },
    {
      chave: 'indisponiveis',
      titulo: t('GENERAL_SETTINGS.FORM.FEATURES.GROUPS.BLOCKED'),
      itens: features.value.filter(f => !f.available),
    },
    // Grupo vazio some AQUI e não no template: `v-for` com `v-if` na mesma tag avalia o `v-if` por
    // item já dentro do laço, e o vue/eslint barra por isso.
  ].filter(grupo => grupo.itens.length)
);

// O aviso sai de DADO (as marcações do features.yml), não de uma lista de nomes escrita à mão.
const aviso = feature => {
  if (!feature.available)
    return t('GENERAL_SETTINGS.FORM.FEATURES.HINT.NO_BIT');
  if (feature.deprecated)
    return t('GENERAL_SETTINGS.FORM.FEATURES.HINT.DEPRECATED');
  if (feature.premium) return t('GENERAL_SETTINGS.FORM.FEATURES.HINT.PREMIUM');
  if (feature.internal)
    return t('GENERAL_SETTINGS.FORM.FEATURES.HINT.INTERNAL');
  return '';
};

const alternar = async feature => {
  // Interruptor travado não emite nada: ligar uma feature sem bit estoura no banco (RangeError), e o
  // backend recusa. Barrar aqui evita a viagem e a mensagem de erro sem propósito.
  if (!feature.available) return;

  salvando.value = feature.name;
  const desejado = !feature.enabled;
  try {
    // Manda SÓ a que mudou: o backend faz merge, então isto não apaga as demais.
    const { data } = await AccountFeaturesAPI.update({
      [feature.name]: desejado,
    });
    features.value = data.features || features.value;
    useAlert(t('GENERAL_SETTINGS.FORM.FEATURES.API.SUCCESS'));
  } catch (erro) {
    useAlert(
      erro.response?.data?.error ||
        t('GENERAL_SETTINGS.FORM.FEATURES.API.ERROR')
    );
  }
  salvando.value = null;
};
</script>

<template>
  <SectionLayout
    :title="$t('GENERAL_SETTINGS.FORM.FEATURES.TITLE')"
    :description="$t('GENERAL_SETTINGS.FORM.FEATURES.NOTE')"
  >
    <div v-if="carregando" class="flex items-center justify-center py-6">
      <Spinner class="text-n-blue-11" />
    </div>

    <div v-else class="flex flex-col gap-6">
      <div
        v-for="grupo in grupos"
        :key="grupo.chave"
        class="flex flex-col gap-2"
      >
        <span class="text-xs font-medium uppercase text-n-slate-10">
          {{ grupo.titulo }}
        </span>

        <div
          v-for="feature in grupo.itens"
          :key="feature.name"
          class="flex items-start justify-between gap-4 py-2 border-b border-n-weak last:border-0"
        >
          <div class="flex flex-col">
            <span class="text-sm font-medium text-n-slate-12">
              {{ feature.display_name || feature.name }}
            </span>
            <span class="text-xs text-n-slate-11">{{ feature.name }}</span>
            <span v-if="aviso(feature)" class="mt-1 text-xs text-n-amber-11">
              {{ aviso(feature) }}
            </span>
          </div>

          <Switch
            :model-value="feature.enabled"
            :disabled="!feature.available || salvando === feature.name"
            @update:model-value="alternar(feature)"
          />
        </div>
      </div>
    </div>
  </SectionLayout>
</template>
