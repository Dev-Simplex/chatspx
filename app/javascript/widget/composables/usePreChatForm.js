import { computed, getCurrentInstance, onBeforeUnmount, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { isEmptyObject } from 'widget/helpers/utils';
import { savePartialLead } from 'widget/api/partialLead';
import {
  fieldErrorFor,
  fieldsForStep,
  maskFieldValue,
  resolveFieldValue,
  stepsOf,
  visibleFields,
} from 'widget/helpers/preChatFieldRules';

/**
 * O ESTADO DO PRÉ-CHAT — bloco 3.15.
 *
 * Sai de dentro de `PreChat/Form.vue` pela mesma razão que o 2.05 esvaziou
 * `ChatInputWrap`: aquele arquivo é campo minado (R15). O upstream o reescreve a
 * cada minor (+39/−33 medidos), e um fork de 570 linhas dentro dele produz
 * conflito grande e caro toda vez. O aceite mede menos de 60 linhas na casca — e
 * é este arquivo, mais `widget/ui/WField.vue`, que devolvem essas linhas.
 *
 * A REGRA não mora aqui: `show_if`, etapa, máscara e validação vivem em
 * `widget/helpers/preChatFieldRules.js`, puras e testáveis sem montar nada. Aqui
 * fica só o estado do formulário e a ligação com o store.
 */
export const usePreChatForm = ({ options, emit }) => {
  const store = useStore();
  const { formatMessage } = useMessageFormatter();

  // `$t` vem da instância, e não de `useI18n()`, porque o widget instala o i18n
  // pela API global (o `$t` do proxy) e é ele que os specs substituem por mock.
  // `useI18n()` aqui exigiria uma segunda forma de instalação só para o teste.
  const instancia = getCurrentInstance();
  // Repasse, não montagem de chave: as chaves são literais nos chamadores
  // (`fieldErrorFor` as tira de um mapa fechado, conferido por teste). O lint
  // não distingue as duas coisas e acusaria toda função de repasse.
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  const t = (...args) => instancia.proxy.$t(...args);

  const formValues = ref({});
  // Bloco 3.15 — etapa corrente e campos já visitados. `touchedFields` existe
  // porque erro de formato tem de aparecer no BLUR: acusar "CPF inválido" no
  // terceiro dígito é ruído, não ajuda.
  const currentStep = ref(1);
  const touchedFields = ref([]);
  // Bloco 4.18 — temporizador do rascunho do lead incompleto. Por instância, não
  // por módulo: dois pré-chats montados (widget e campanha) não podem cancelar o
  // rascunho um do outro.
  let partialLeadTimer = null;
  let partialLeadSent = '';

  const isCreating = computed(
    () => store.getters['conversation/getIsCreating']
  );
  const isConversationRouting = computed(
    () => store.getters['appConfig/getIsUpdatingRoute']
  );
  const activeCampaign = computed(
    () => store.getters['campaign/getActiveCampaign']
  );
  const currentUser = computed(() => store.getters['contacts/getCurrentUser']);

  const isCreatingConversation = computed(
    () => isCreating.value || isConversationRouting.value
  );
  const hasActiveCampaign = computed(
    () => !isEmptyObject(activeCampaign.value)
  );
  const preChatFormEnabled = computed(
    () => window.chatwootWebChannel?.preChatFormEnabled
  );

  const headerMessage = computed(() => {
    if (preChatFormEnabled.value) return options.value.preChatMessage;
    if (hasActiveCampaign.value) return t('PRE_CHAT_FORM.CAMPAIGN_HEADER');
    return '';
  });
  const shouldShowHeaderMessage = computed(
    () =>
      hasActiveCampaign.value ||
      (preChatFormEnabled.value && !!headerMessage.value)
  );
  const headerMessageHtml = computed(() =>
    formatMessage(headerMessage.value, false)
  );

  const preChatFields = computed(() =>
    preChatFormEnabled.value ? options.value.preChatFields : []
  );

  const filteredPreChatFields = computed(() => {
    const isUserEmailAvailable = currentUser.value.has_email;
    const isUserPhoneNumberAvailable = currentUser.value.has_phone_number;
    const isUserIdentifierAvailable = !!currentUser.value.identifier;
    const isUserNameAvailable = !!(
      isUserIdentifierAvailable ||
      isUserEmailAvailable ||
      isUserPhoneNumberAvailable
    );

    return preChatFields.value.filter(field => {
      if (isUserEmailAvailable && field.name === 'emailAddress') return false;
      if (isUserPhoneNumberAvailable && field.name === 'phoneNumber') {
        return false;
      }
      if (isUserNameAvailable && field.name === 'fullName') return false;
      return true;
    });
  });

  /**
   * Bloco 3.15, e é a linha que carrega o bloco: filtrar AQUI faz o `show_if`
   * valer para tudo que deriva daqui — o que renderiza, o que é validado, o que
   * é enviado e o que conta para o rascunho de lead. Campo escondido não existe
   * para nenhum deles, que é a única leitura coerente de "escondido".
   *
   * O tipo NÃO é mapeado aqui: `WField` faz o mapeamento na hora de renderizar,
   * e as regras (`resolveFieldValue`) leem o tipo CRU do painel, que é onde
   * `list` ainda se chama `list`.
   */
  const enabledPreChatFields = computed(() =>
    visibleFields(
      filteredPreChatFields.value.filter(field => field.enabled),
      formValues.value
    )
  );

  // Bloco 3.15 — as etapas ocupadas, já depois do `show_if`: um condicional
  // escondido não pode criar etapa vazia.
  const visibleSteps = computed(() => stepsOf(enabledPreChatFields.value));
  const fieldsOfCurrentStep = computed(() =>
    fieldsForStep(enabledPreChatFields.value, currentStep.value)
  );
  const isLastStep = computed(() => {
    const steps = visibleSteps.value;
    return currentStep.value >= steps[steps.length - 1];
  });
  const hasMultipleSteps = computed(() => visibleSteps.value.length > 1);

  /**
   * O valor do campo como ele viaja no envio — resolvido pelo MESMO helper que
   * o `show_if` usa. Uma resolução só: se a condicional entende `'0'` como
   * "Empresa", o atributo gravado no contato tem de entender igual.
   */
  const getValue = field =>
    resolveFieldValue(field, formValues.value[field.name]) || null;

  const attributesOf = kind =>
    enabledPreChatFields.value
      .filter(field => field.field_type === kind)
      .reduce((acc, field) => ({ ...acc, [field.name]: getValue(field) }), {});

  const conversationCustomAttributes = computed(() =>
    attributesOf('conversation_attribute')
  );
  const contactCustomAttributes = computed(() =>
    attributesOf('contact_attribute')
  );

  /**
   * Bloco 3.15 — máscara enquanto digita, delegada ao helper do 3.13.
   *
   * Reentrante de propósito: reescrever `formValues` dispara o watcher outra
   * vez, mas a segunda passada devolve o mesmo texto e a recursão para na
   * comparação. Máscara desconhecida devolve o valor intacto — máscara que não
   * existe não pode comer o que foi digitado.
   */
  const applyFieldMasks = () => {
    enabledPreChatFields.value.forEach(field => {
      const atual = formValues.value[field.name];
      if (typeof atual !== 'string' || !atual) return;
      const mascarado = maskFieldValue(atual, field);
      if (mascarado !== atual) formValues.value[field.name] = mascarado;
    });
  };

  const filledAnswers = () => {
    const answers = {};
    enabledPreChatFields.value.forEach(field => {
      const value = formValues.value[field.name];
      if (String(value ?? '').trim() !== '') answers[field.name] = value;
    });
    return answers;
  };

  /**
   * A ETAPA EM QUE PAROU é o primeiro campo habilitado ainda vazio — é essa a
   * resposta que o relatório precisa para dizer ONDE se perde o lead. Com tudo
   * preenchido, a etapa é a última: a pessoa chegou ao fim e ainda assim não
   * enviou.
   */
  const stoppedAt = answers => {
    const fields = enabledPreChatFields.value;
    const index = fields.findIndex(field => !(field.name in answers));
    return index === -1
      ? { step: fields.length, stepKey: fields[fields.length - 1]?.name }
      : { step: index + 1, stepKey: fields[index].name };
  };

  /**
   * Bloco 4.18 — LEAD INCOMPLETO.
   *
   * A cada campo respondido, o rascunho vai para o servidor ANTES de existir
   * conversa. Sem isto, quem preenche nome e e-mail e fecha a aba no terceiro
   * campo some sem deixar rastro. Espera 1,2 s de silêncio para não mandar uma
   * requisição por tecla, e não repete um rascunho idêntico ao último enviado.
   */
  const sendPartialLead = () => {
    const answers = filledAnswers();
    if (!Object.keys(answers).length) return;

    const payload = JSON.stringify(answers);
    if (payload === partialLeadSent) return;
    partialLeadSent = payload;

    const { step, stepKey } = stoppedAt(answers);
    savePartialLead({ answers, step, stepKey });
  };

  const schedulePartialLead = () => {
    clearTimeout(partialLeadTimer);
    partialLeadTimer = setTimeout(sendPartialLead, 1200);
  };

  const markTouched = name => {
    if (!touchedFields.value.includes(name)) touchedFields.value.push(name);
  };

  /**
   * Bloco 3.15 — o erro ESPECÍFICO do campo, que é metade do aceite.
   *
   * Só aparece depois do blur e só com conteúdo escrito: o campo obrigatório
   * vazio já é assunto da regra `required` do FormKit, e acusar formato em campo
   * intocado é ruído. `error_message` do administrador vence o catálogo — quem
   * escreveu a regra sabe explicá-la melhor que uma mensagem genérica.
   */
  const delegatedErrors = field => {
    if (!touchedFields.value.includes(field.name)) return [];
    const valor = formValues.value[field.name];
    if (String(valor ?? '').trim() === '') return [];
    const erro = fieldErrorFor(field, valor, { t });
    return erro ? [erro.message] : [];
  };

  /**
   * Avança de etapa. Só passa quando a etapa atual não tem obrigatório vazio nem
   * erro de formato — validar no avanço é o que impede alguém chegar ao fim e
   * descobrir que o problema estava três telas atrás.
   */
  const canLeaveCurrentStep = () =>
    fieldsOfCurrentStep.value.every(field => {
      const valor = formValues.value[field.name];
      const vazio = String(valor ?? '').trim() === '';
      if (field.required && vazio) return false;
      if (vazio) return true;
      const erro = fieldErrorFor(field, valor, { t });
      return !erro || erro.severity === 'warning';
    });

  const goToNextStep = () => {
    fieldsOfCurrentStep.value.forEach(field => markTouched(field.name));
    if (!canLeaveCurrentStep()) return;
    const proxima = visibleSteps.value.find(step => step > currentStep.value);
    if (proxima) currentStep.value = proxima;
  };

  const onSubmit = () => {
    // O envio conclui o pré-chat: o rascunho pendente não pode chegar DEPOIS e
    // reabrir como incompleto um lead que já virou conversa.
    clearTimeout(partialLeadTimer);
    const { message } = formValues.value;
    // Bloco 3.15. Os quatro campos padrão saíam de `formValues` direto, sem
    // passar por `enabledPreChatFields` — então um campo que FICOU escondido
    // depois de preenchido (o gatilho mudou de resposta) ainda viajava com o
    // valor velho. Escondido é escondido para o envio também.
    const visivel = nome =>
      enabledPreChatFields.value.some(field => field.name === nome);
    const doCampo = nome =>
      visivel(nome) ? formValues.value[nome] : undefined;

    emit('submitPreChat', {
      fullName: doCampo('fullName'),
      phoneNumber: doCampo('phoneNumber'),
      emailAddress: doCampo('emailAddress'),
      message,
      activeCampaignId: activeCampaign.value.id,
      conversationCustomAttributes: conversationCustomAttributes.value,
      contactCustomAttributes: contactCustomAttributes.value,
    });
  };

  watch(
    formValues,
    () => {
      applyFieldMasks();
      schedulePartialLead();
    },
    { deep: true }
  );

  // O `show_if` pode esconder a etapa em que estamos (o gatilho mudou de
  // resposta). Sem isto o visitante fica numa etapa que já não tem campo.
  watch(visibleSteps, steps => {
    if (!steps.includes(currentStep.value)) currentStep.value = steps[0] ?? 1;
  });

  onBeforeUnmount(() => clearTimeout(partialLeadTimer));

  return {
    formValues,
    currentStep,
    touchedFields,
    isCreatingConversation,
    hasActiveCampaign,
    shouldShowHeaderMessage,
    headerMessage,
    headerMessageHtml,
    preChatFields,
    enabledPreChatFields,
    visibleSteps,
    fieldsOfCurrentStep,
    isLastStep,
    hasMultipleSteps,
    conversationCustomAttributes,
    contactCustomAttributes,
    getValue,
    applyFieldMasks,
    filledAnswers,
    schedulePartialLead,
    markTouched,
    delegatedErrors,
    canLeaveCurrentStep,
    goToNextStep,
    onSubmit,
  };
};
