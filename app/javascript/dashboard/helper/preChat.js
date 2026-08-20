// D10 (bloco 0.8): o dashboard nao importa mais `widget/i18n`. O import trazia
// os 58 locales do widget (~205 KB de JSON) para alimentar um lookup que NUNCA
// casava: em `widget/i18n`, PRE_CHAT_FORM.FIELDS tem chaves UPPER_SNAKE
// (EMAIL_ADDRESS) e a busca era feita com o `name` do campo (emailAddress).
// Medido em runtime antes da correcao: getLabel devolvia sempre o valor
// recebido, nunca a traducao.
//
// O que isso quebrava na tela do cliente: `web_widget.rb:84-101` semeia a inbox
// nova com label em ingles cravado no Ruby e SEM placeholder nenhum. Com o
// lookup morto, o fallback de placeholder era `item.name` — o visitante lia
// "emailAddress" dentro do input.
//
// PRECEDENCIA, de proposito: o valor guardado ganha do default traduzido. O
// contrario sobrescreveria a personalizacao do cliente no proximo save, porque
// `PreChatForm/Settings.vue:78` persiste estes valores e o widget
// (`components/PreChat/Form.vue:152-157`) os renderiza verbatim, sem traduzir.
const STANDARD_FIELD_I18N_KEYS = {
  emailAddress: 'EMAIL_ADDRESS',
  fullName: 'FULL_NAME',
  phoneNumber: 'PHONE_NUMBER',
};

const translateStandardField = (name, suffix, translate) => {
  const fieldKey = STANDARD_FIELD_I18N_KEYS[name];
  if (!fieldKey || !translate) return null;

  const path = `INBOX_WIDGET.PRE_CHAT_FORM.FIELDS.${fieldKey}.${suffix}`;
  const value = translate(path);
  // vue-i18n devolve a propria chave quando ela nao existe. Chave crua na tela
  // do cliente e exatamente o defeito que este bloco esta fechando; barra aqui.
  return value && value !== path ? value : null;
};

export const standardFieldKeys = {
  emailAddress: {
    key: 'EMAIL_ADDRESS',
    label: 'Email Id',
    placeholder: 'Please enter your email address',
  },
  fullName: {
    key: 'FULL_NAME',
    label: 'Full Name',
    placeholder: 'Please enter your full name',
  },
  phoneNumber: {
    key: 'PHONE_NUMBER',
    label: 'Phone Number',
    placeholder: 'Please enter your phone number',
  },
};

export const getLabel = ({ key, label }, translate) => {
  return label || translateStandardField(key, 'LABEL', translate) || key;
};
export const getPlaceHolder = ({ key, placeholder }, translate) => {
  return (
    placeholder || translateStandardField(key, 'PLACEHOLDER', translate) || key
  );
};

export const getCustomFields = ({ standardFields, customAttributes }) => {
  let customFields = [];
  const { pre_chat_fields: preChatFields } = standardFields;
  customAttributes.forEach(attribute => {
    const itemExist = preChatFields.find(
      item => item.name === attribute.attribute_key
    );
    if (!itemExist) {
      customFields.push({
        label: attribute.attribute_display_name,
        placeholder: attribute.attribute_display_name,
        name: attribute.attribute_key,
        type: attribute.attribute_display_type,
        values: attribute.attribute_values,
        field_type: attribute.attribute_model,
        regex_pattern: attribute.regex_pattern,
        regex_cue: attribute.regex_cue,
        required: false,
        enabled: false,
      });
    }
  });
  return customFields;
};

export const getFormattedPreChatFields = ({ preChatFields }, translate) => {
  return preChatFields.map(item => {
    return {
      ...item,
      // `item.label` cru, nao `item.label || item.name`: getLabel precisa saber
      // se o valor esta guardado ou ausente para escolher entre ele e o default
      // traduzido. O fallback para `name` continua existindo, dentro do getLabel.
      label: getLabel({ key: item.name, label: item.label }, translate),
      placeholder: getPlaceHolder(
        { key: item.name, placeholder: item.placeholder },
        translate
      ),
    };
  });
};

export const getPreChatFields = (
  { preChatFormOptions = {}, customAttributes = [] },
  translate
) => {
  const { pre_chat_message, pre_chat_fields } = preChatFormOptions;
  let customFields = {};
  let preChatFields = {};

  const formattedPreChatFields = getFormattedPreChatFields(
    { preChatFields: pre_chat_fields },
    translate
  );

  customFields = getCustomFields({
    standardFields: { pre_chat_fields: formattedPreChatFields },
    customAttributes,
  });
  preChatFields = [...formattedPreChatFields, ...customFields];

  return {
    pre_chat_message,
    pre_chat_fields: preChatFields,
  };
};
