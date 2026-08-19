<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import CampaignsAPI from 'dashboard/api/campaigns';

/**
 * O MODO ANTIGO — bloco 4.22.
 *
 * É rampa, não corte, e esta seção é a rampa aparecendo na tela. A campanha legada
 * continua listada e editável; o que muda é que, com o gatilho novo ligado, ela
 * deixa de disparar sozinha — e o cliente precisa VER isso, senão ele vai procurar
 * o defeito no lugar errado quando a campanha parar de aparecer no site dele.
 *
 * O aviso é o produto aqui. Uma seção que só listasse campanhas seria pior que
 * nenhuma: mostraria "ativa" ao lado de algo que não dispara mais.
 *
 * NOME ACESSÍVEL EM TODO CONTROLE: o botão de importar tem texto visível E
 * `aria-label` com o nome da campanha, porque três botões "Importar" na mesma tela
 * são três nomes idênticos para o leitor de tela. O rótulo é texto limpo — se o
 * cliente puser emoji no título da campanha, ele fica na tela e sai do nome.
 */
const props = defineProps({
  inboxId: { type: [String, Number], required: true },
  /** O gatilho novo está ligado? É o que decide o aviso desta seção. */
  gatilhoAtivo: { type: Boolean, default: false },
});

const emit = defineEmits(['imported']);

const { t } = useI18n();
const store = useStore();

const PICTOGRAFICO = /\p{Extended_Pictographic}/gu;

const campanhas = useMapGetter('campaigns/getLiveChatCampaigns');
const importando = ref(null);

/**
 * As campanhas DESTA inbox que ainda estão ligadas. A importada sai da lista sozinha
 * (o servidor a desativa), e é assim que o cliente vê o progresso da migração.
 */
const legadas = computed(() =>
  campanhas.value.filter(
    campanha =>
      Number(campanha.inbox?.id ?? campanha.inbox_id) ===
        Number(props.inboxId) && campanha.enabled
  )
);

const nomeLimpo = titulo =>
  String(titulo || '')
    .replace(PICTOGRAFICO, '')
    .replace(/\s+/g, ' ')
    .trim() || t('INBOX_WIDGET.TRIGGERS.LEGACY.UNNAMED');

const rotuloImportar = campanha =>
  t('INBOX_WIDGET.TRIGGERS.LEGACY.IMPORT_ARIA', {
    campanha: nomeLimpo(campanha.title),
  });

const importar = async campanha => {
  importando.value = campanha.id;
  try {
    await CampaignsAPI.importToTrigger(campanha.display_id ?? campanha.id);
    await store.dispatch('campaigns/get');
    useAlert(t('INBOX_WIDGET.TRIGGERS.LEGACY.IMPORTED'));
    emit('imported');
  } catch (error) {
    useAlert(t('INBOX_WIDGET.TRIGGERS.LEGACY.IMPORT_ERROR'));
  } finally {
    importando.value = null;
  }
};
</script>

<template>
  <section
    v-if="legadas.length"
    class="flex flex-col gap-3"
    data-testid="modo-antigo"
  >
    <h3 class="text-heading-2 text-n-slate-12">
      {{ t('INBOX_WIDGET.TRIGGERS.LEGACY.SECTION') }}
    </h3>

    <!-- O aviso muda com o estado, e é o ponto da seção: o cliente tem de saber que
      a campanha não dispara enquanto o gatilho estiver ligado.

      A COR NÃO É `amber`, e a escolha foi MEDIDA no Chromium, não sentida: o par do
      `amber` (texto `-11` sobre fundo `-3`) dá **4,25:1** no tema claro, abaixo do AA
      de 4,5:1 para texto pequeno. O `slate`, que é o default do Banner, dá 4,14:1 — os
      dois reprovam, e a medição está roteada ao dono do design system. `teal` (5,40:1)
      e `blue` (5,78:1 — neste fork o "blue" é o verde da marca) passam.

      Só um dos dois banners aparece por vez, então a proximidade de matiz entre eles
      não é problema: o que distingue os estados é o texto. -->
    <Banner
      :color="gatilhoAtivo ? 'teal' : 'blue'"
      :content="
        gatilhoAtivo
          ? t('INBOX_WIDGET.TRIGGERS.LEGACY.SUPPRESSED')
          : t('INBOX_WIDGET.TRIGGERS.LEGACY.STILL_RUNNING')
      "
      data-testid="modo-antigo-aviso"
    />

    <ul class="flex flex-col gap-2 p-0 m-0 list-none">
      <li
        v-for="campanha in legadas"
        :key="campanha.id"
        class="flex items-center justify-between gap-3 px-3 py-2 border rounded-lg border-n-weak"
      >
        <div class="flex flex-col min-w-0">
          <span class="text-sm font-medium truncate text-n-slate-12">
            {{ campanha.title }}
          </span>
          <span class="text-xs truncate text-n-slate-11">
            {{ campanha.message }}
          </span>
        </div>
        <NextButton
          sm
          faded
          :label="t('INBOX_WIDGET.TRIGGERS.LEGACY.IMPORT')"
          :aria-label="rotuloImportar(campanha)"
          :is-loading="importando === campanha.id"
          :disabled="importando !== null"
          data-testid="importar-campanha"
          @click="importar(campanha)"
        />
      </li>
    </ul>
  </section>
</template>
