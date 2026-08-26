<script>
import validations from './helpers/validations';
import FormInput from 'v3/components/Form/Input.vue';
import { reactive, ref } from 'vue';
import { useVuelidate } from '@vuelidate/core';

import NextButton from 'dashboard/components-next/button/Button.vue';
import TeamDistribuicaoFields from './TeamDistribuicaoFields.vue';

export default {
  components: {
    NextButton,
    FormInput,
    TeamDistribuicaoFields,
  },
  props: {
    onSubmit: {
      type: Function,
      default: () => {},
    },
    submitInProgress: {
      type: Boolean,
      default: false,
    },
    formData: {
      type: Object,
      default: () => {},
    },
    submitButtonText: {
      type: String,
      default: '',
    },
    // Só na EDIÇÃO. No cadastro o time ainda não existe e, mais importante, ainda não tem
    // membros: o pool só pode ser montado com quem já é membro, porque o motor descarta
    // não-membro EM SILÊNCIO (foi assim que o time de vendas da Tozi ficou com o pool inteiro
    // inválido sem ninguém perceber). Oferecer a lista aqui produziria fila vazia ou inválida.
    teamId: {
      type: [String, Number],
      default: null,
    },
  },
  setup(props) {
    const formData = props.formData || {};
    const {
      description = '',
      name: title = '',
      allow_auto_assign: allowAutoAssign = true,
    } = formData;

    const state = reactive({
      description,
      title,
      allowAutoAssign,
    });

    // Ligado quando o rodízio do time está ativo. Serve só para o aviso dos dois motores.
    const rodizioAtivo = ref(false);

    const rules = validations;
    const v$ = useVuelidate(rules, state);
    return { state, v$, rodizioAtivo };
  },
  methods: {
    async handleSubmit() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        return;
      }
      // O rodízio salva na API dele (política é por time, tabela própria). Salvar ANTES do time
      // é de propósito: se o time falhar, o operador corrige e reenvia; se o rodízio falhasse
      // depois de o time já ter sido salvo, o botão teria "funcionado pela metade" sem dizer.
      await this.$refs.distribuicao?.salvar?.();
      this.onSubmit({
        description: this.state.description,
        name: this.state.title,
        allow_auto_assign: this.state.allowAutoAssign,
      });
    },
    aoCarregarDistribuicao({ ativo }) {
      this.rodizioAtivo = ativo;
    },
  },
};
</script>

<template>
  <div class="flex-shrink-0 w-full">
    <form class="mx-0 grid gap-4" @submit.prevent="handleSubmit">
      <FormInput
        v-model="state.title"
        name="title"
        spacing="compact"
        :label="$t('TEAMS_SETTINGS.FORM.NAME.LABEL')"
        :placeholder="$t('TEAMS_SETTINGS.FORM.NAME.PLACEHOLDER')"
        :has-error="v$.title.$error"
        :error-message="v$.title.$error ? v$.title.$errors[0].$message : ''"
        @blur="v$.title.$touch"
      />
      <FormInput
        v-model="state.description"
        name="description"
        spacing="compact"
        :label="$t('TEAMS_SETTINGS.FORM.DESCRIPTION.LABEL')"
        :placeholder="$t('TEAMS_SETTINGS.FORM.DESCRIPTION.PLACEHOLDER')"
        :has-error="v$.description.$error"
        :error-message="
          v$.description.$error ? v$.description.$errors[0].$message : ''
        "
        @blur="v$.description.$touch"
      />
      <div class="w-full flex items-center gap-2">
        <input v-model="state.allowAutoAssign" type="checkbox" :value="true" />
        <label for="conversation_creation">
          {{ $t('TEAMS_SETTINGS.FORM.AUTO_ASSIGN.LABEL') }}
        </label>
      </div>

      <!-- Dois motores DIFERENTES, e ligar os dois faz um desfazer a escolha do outro: o de cima
           é a atribuição automática nativa do Chatwoot (qualquer membro com capacidade); o de
           baixo é o Motor de Distribuição do fork (rodízio em ordem, com fila, cap e SLA). O
           aviso só aparece quando os dois estão de fato ligados. -->
      <p
        v-if="state.allowAutoAssign && rodizioAtivo"
        class="px-3 py-2 -mt-2 text-xs rounded text-n-amber-11 bg-n-amber-2"
      >
        {{ $t('TEAMS_SETTINGS.FORM.AUTO_ASSIGN.CONFLITO_RODIZIO') }}
      </p>

      <!-- No cadastro (sem teamId) só existe o checkbox acima: sem membros, não há fila a montar. -->
      <div v-if="teamId" class="w-full pt-2 border-t border-n-weak">
        <TeamDistribuicaoFields
          ref="distribuicao"
          :team-id="teamId"
          embutido
          @carregado="aoCarregarDistribuicao"
        />
      </div>
      <p v-else class="-mt-2 text-xs text-n-slate-11">
        {{ $t('TEAMS_SETTINGS.FORM.AUTO_ASSIGN.RODIZIO_DEPOIS') }}
      </p>
      <div class="flex flex-row justify-end gap-2 py-2 px-0 w-full">
        <div class="w-full">
          <NextButton
            type="submit"
            :label="submitButtonText"
            :disabled="v$.title.$invalid || submitInProgress"
            :is-loading="submitInProgress"
          />
        </div>
      </div>
    </form>
  </div>
</template>
