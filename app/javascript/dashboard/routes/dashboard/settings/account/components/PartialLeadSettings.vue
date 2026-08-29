<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import PartialLeadSettingsAPI from 'dashboard/api/partialLeadSettings';
import SectionLayout from './SectionLayout.vue';
import Switch from 'next/switch/Switch.vue';
import NextInput from 'next/input/Input.vue';

/**
 * Bloco 4.18 — "Quem responde pela metade" (mockup 22 §3).
 *
 * As quatro decisões existiam no servidor com padrão declarado e sem porta nenhuma: dava para
 * mudá-las por console e mais nada. Uma retenção de dado pessoal que só a infraestrutura
 * consegue mexer não é configurável, e o aceite do bloco cobra configurável por um motivo de
 * LGPD — quem abandona o pré-chat não consentiu com nada.
 *
 * TRÊS DECISÕES DE TELA, cada uma com razão:
 *
 *  1. **Os valores vêm do servidor, não daqui.** A tela nunca escreve "5" nem "30" como
 *     padrão próprio: ela desenha o que o `show` devolveu, que é o valor RESOLVIDO. Um padrão
 *     repetido no cliente é uma segunda fonte de verdade que envelhece calada.
 *  2. **Salva ao confirmar, não a cada tecla.** Retenção e janela são números: salvar a cada
 *     dígito gravaria "3" no caminho de "30".
 *  3. **Ela é POR CONTA, e o texto diz isso.** O armazenamento é `account`, e o mockup desenha
 *     a seção dentro da tela por inbox. Enquanto for por conta, dizer o contrário na tela seria
 *     a mesma mentira que este bloco existe para consertar.
 */
const { t } = useI18n();

const enabled = ref(false);
const abandonAfterMinutes = ref(5);
const retentionDays = ref(30);
const label = ref('');
const isLoading = ref(true);
const hasError = ref(false);

const aplicar = data => {
  enabled.value = !!data.partial_lead_capture_enabled;
  abandonAfterMinutes.value = data.partial_lead_abandon_after_minutes;
  retentionDays.value = data.partial_lead_retention_days;
  label.value = data.partial_lead_label ?? '';
};

const carregar = async () => {
  try {
    const { data } = await PartialLeadSettingsAPI.get();
    aplicar(data);
  } catch {
    hasError.value = true;
  } finally {
    isLoading.value = false;
  }
};

onMounted(carregar);

const salvar = async payload => {
  try {
    const { data } = await PartialLeadSettingsAPI.set(payload);
    // O servidor devolve o valor NORMALIZADO e a tela adota o dele: digitar "para sempre" na
    // retenção tem de voltar como 30, senão o campo continua exibindo uma configuração que não
    // existe.
    aplicar(data);
    useAlert(t('GENERAL_SETTINGS.FORM.PARTIAL_LEAD.API.SUCCESS'));
  } catch {
    useAlert(t('GENERAL_SETTINGS.FORM.PARTIAL_LEAD.API.ERROR'));
    carregar();
  }
};

const alternarCaptura = () =>
  salvar({ partial_lead_capture_enabled: enabled.value });

const salvarJanela = () =>
  salvar({
    partial_lead_abandon_after_minutes: Number(abandonAfterMinutes.value),
  });

const salvarRetencao = () =>
  salvar({ partial_lead_retention_days: Number(retentionDays.value) });

const salvarEtiqueta = () => salvar({ partial_lead_label: label.value });

// O aviso de LGPD só faz sentido quando a captura está ligada: com ela desligada nada é
// guardado, e um alerta permanente vira ruído que ninguém lê.
const mostraAvisoDeRetencao = computed(() => enabled.value && !hasError.value);
</script>

<template>
  <SectionLayout
    :title="t('GENERAL_SETTINGS.FORM.PARTIAL_LEAD.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.PARTIAL_LEAD.NOTE')"
    with-border
  >
    <template #headerActions>
      <div class="flex justify-end">
        <Switch
          v-model="enabled"
          data-testid="partial-lead-enabled"
          :disabled="isLoading"
          @change="alternarCaptura"
        />
      </div>
    </template>

    <div
      v-if="hasError"
      data-testid="partial-lead-error"
      class="p-4 rounded-lg bg-n-ruby-2 text-n-ruby-11 text-body-main"
    >
      {{ t('GENERAL_SETTINGS.FORM.PARTIAL_LEAD.API.ERROR') }}
    </div>

    <div v-else-if="!isLoading" class="flex flex-col gap-6">
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <NextInput
          v-model="abandonAfterMinutes"
          type="number"
          min="1"
          data-testid="partial-lead-abandon"
          :label="t('GENERAL_SETTINGS.FORM.PARTIAL_LEAD.ABANDON_AFTER.LABEL')"
          :message="t('GENERAL_SETTINGS.FORM.PARTIAL_LEAD.ABANDON_AFTER.HELP')"
          @blur="salvarJanela"
        />
        <NextInput
          v-model="retentionDays"
          type="number"
          min="1"
          data-testid="partial-lead-retention"
          :label="t('GENERAL_SETTINGS.FORM.PARTIAL_LEAD.RETENTION.LABEL')"
          :message="t('GENERAL_SETTINGS.FORM.PARTIAL_LEAD.RETENTION.HELP')"
          @blur="salvarRetencao"
        />
      </div>

      <NextInput
        v-model="label"
        data-testid="partial-lead-label"
        :label="t('GENERAL_SETTINGS.FORM.PARTIAL_LEAD.LABEL.LABEL')"
        :message="t('GENERAL_SETTINGS.FORM.PARTIAL_LEAD.LABEL.HELP')"
        @blur="salvarEtiqueta"
      />

      <p
        v-if="mostraAvisoDeRetencao"
        data-testid="partial-lead-lgpd"
        class="text-body-small text-n-slate-11"
      >
        {{
          t('GENERAL_SETTINGS.FORM.PARTIAL_LEAD.LGPD', { days: retentionDays })
        }}
      </p>
    </div>
  </SectionLayout>
</template>
