<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';

/**
 * A MENSAGEM do convite (bloco 4.05).
 *
 * A divisao que este componente materializa: **campanha e mensagem, gatilho e
 * momento**. O que dizer ja existe no produto — a campanha de chat ao vivo tem
 * titulo, texto, remetente, horario comercial e `enabled`, e o motor dela
 * funciona. O que nasceu nesta onda e o QUANDO.
 *
 * Por isso esta tela **nao cria uma campanha por gatilho**: ela vincula a
 * campanha que a inbox ja tem, e editar o texto aqui edita AQUELA campanha.
 * Duas listas concorrentes de "mensagem proativa" no mesmo produto e o caminho
 * conhecido para o cliente editar uma e o visitante receber a outra.
 *
 * O vinculo e a propria inbox: a campanha de chat ao vivo dela. Nao inventamos
 * um `campaign_id` dentro de `widget_triggers` — o schema recusa chave nova
 * (`additionalProperties: false`), e um segundo apontador para o mesmo fato
 * seria mais uma ponta para divergir.
 */
const props = defineProps({
  inboxId: { type: [String, Number], required: true },
});

const { t } = useI18n();
const store = useStore();

const campanhas = useMapGetter('campaigns/getLiveChatCampaigns');
const todasCampanhas = useMapGetter('campaigns/getAllCampaigns');
const uiFlags = useMapGetter('campaigns/getUIFlags');

/**
 * Quem CARREGA a campanha. Ler o getter nao busca nada, e nenhuma rota da inbox
 * despacha `campaigns/get`: em visita direta ou F5 a lista chegava `[]`, a tela
 * caia no banner "esta caixa ainda nao tem campanha" — falso, com a campanha
 * existindo no banco — e nao oferecia campo nenhum para editar. O convite virava
 * letra morta pelo caminho mais comum de chegar nele.
 *
 * A guarda evita repetir o GET a cada remontagem do componente (trocar de aba na
 * configuracao do widget e voltar), e deixa a lista pronta para os outros
 * consumidores desta mesma tela — a secao "modo antigo" (4.22) le a MESMA lista.
 * Ela olha `getAllCampaigns` (todos os registros), e nao a lista ja filtrada de
 * chat ao vivo, porque conta que so tem campanha de disparo tem registros
 * carregados e nenhuma campanha de chat: filtrar antes de decidir faria a tela
 * buscar de novo toda vez.
 */
onMounted(() => {
  if (todasCampanhas.value.length || uiFlags.value.isFetching) return;
  store.dispatch('campaigns/get');
});

/** A campanha desta inbox — a que o teaser vai mostrar. */
const vinculada = computed(() =>
  campanhas.value.find(
    campanha =>
      Number(campanha.inbox?.id ?? campanha.inbox_id) === Number(props.inboxId)
  )
);

const rascunho = ref({ title: '', message: '' });
const sujo = ref(false);

watch(
  vinculada,
  campanha => {
    if (!campanha || sujo.value) return;
    rascunho.value = {
      title: campanha.title ?? '',
      message: campanha.message ?? '',
    };
  },
  { immediate: true }
);

const editar = (campo, valor) => {
  sujo.value = true;
  rascunho.value = { ...rascunho.value, [campo]: valor };
};

const salvar = async () => {
  if (!vinculada.value) return;
  try {
    // `update`, nunca `create`: o aceite do bloco e que editar o texto edite a
    // campanha vinculada, e que nao nasca uma campanha por gatilho.
    await store.dispatch('campaigns/update', {
      id: vinculada.value.id,
      ...rascunho.value,
    });
    sujo.value = false;
    useAlert(t('INBOX_WIDGET.TRIGGERS.TEASER.SAVED'));
  } catch (erro) {
    useAlert(erro.message || t('INBOX_WIDGET.TRIGGERS.TEASER.SAVE_ERROR'));
  }
};

defineExpose({ vinculada, rascunho });
</script>

<template>
  <div class="flex flex-col gap-3" data-testid="teaser-composer">
    <p class="text-sm text-n-slate-11">
      {{ t('INBOX_WIDGET.TRIGGERS.TEASER.EXPLANATION') }}
    </p>

    <template v-if="vinculada">
      <Input
        class="max-w-md"
        :model-value="rascunho.title"
        :label="t('INBOX_WIDGET.TRIGGERS.TEASER.TITLE_LABEL')"
        data-testid="teaser-title"
        @update:model-value="editar('title', $event)"
      />
      <TextArea
        class="max-w-md"
        :model-value="rascunho.message"
        :label="t('INBOX_WIDGET.TRIGGERS.TEASER.MESSAGE_LABEL')"
        data-testid="teaser-message"
        @update:model-value="editar('message', $event)"
      />
      <div class="flex items-center gap-3">
        <NextButton
          :label="t('INBOX_WIDGET.TRIGGERS.TEASER.SAVE')"
          :is-loading="uiFlags.isUpdating"
          :disabled="!sujo || uiFlags.isUpdating"
          data-testid="teaser-save"
          @click="salvar"
        />
        <span class="text-sm text-n-slate-11" data-testid="teaser-link">
          {{
            t('INBOX_WIDGET.TRIGGERS.TEASER.LINKED', {
              campaign: vinculada.title,
            })
          }}
        </span>
      </div>
    </template>

    <!-- Enquanto a busca esta no ar a tela ainda nao SABE se ha campanha, entao
      nao afirma nada: o banner so entra depois que a lista chegou. Afirmar
      "esta caixa ainda nao tem campanha" antes da resposta era metade do defeito
      deste bloco — a outra metade era a busca que nunca acontecia. -->
    <Banner
      v-else-if="!uiFlags.isFetching"
      color="slate"
      data-testid="teaser-empty"
    >
      <span class="text-n-slate-12">
        {{ t('INBOX_WIDGET.TRIGGERS.TEASER.EMPTY') }}
      </span>
    </Banner>
  </div>
</template>
