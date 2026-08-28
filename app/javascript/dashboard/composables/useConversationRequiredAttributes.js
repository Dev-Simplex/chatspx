import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { ATTRIBUTE_TYPES } from 'dashboard/components-next/ConversationWorkflow/constants';

export const CONVERSATION_ATTRIBUTE = 'conversation_attribute';
export const CONTACT_ATTRIBUTE = 'contact_attribute';

/**
 * Composable for managing conversation required attributes workflow
 *
 * This handles the logic for checking if conversations have all required
 * custom attributes filled before they can be resolved.
 *
 * A obrigatoriedade vem do próprio atributo (`required` na definição) e vale para
 * os DOIS modelos — conversa e contato. Cada obrigatório carrega o seu
 * `attributeModel` porque quem consome precisa saber onde gravar o valor.
 */
export function useConversationRequiredAttributes() {
  const conversationAttributes = useMapGetter(
    'attributes/getConversationAttributes'
  );
  const contactAttributes = useMapGetter('attributes/getContactAttributes');

  const toRequiredOption = (attribute, attributeModel) => ({
    ...attribute,
    value: attribute.attributeKey,
    label: attribute.attributeDisplayName,
    type: attribute.attributeDisplayType,
    attributeValues: attribute.attributeValues,
    attributeModel,
  });

  const pickRequired = (attributes, attributeModel) =>
    (attributes || [])
      .filter(attribute => attribute.required === true)
      .map(attribute => toRequiredOption(attribute, attributeModel));

  /**
   * Full attribute definitions of every attribute marked as required,
   * conversation ones first, then contact ones.
   */
  const requiredAttributes = computed(() => [
    ...pickRequired(conversationAttributes.value, CONVERSATION_ATTRIBUTE),
    ...pickRequired(contactAttributes.value, CONTACT_ATTRIBUTE),
  ]);

  const requiredAttributeKeys = computed(() =>
    requiredAttributes.value.map(attribute => attribute.value)
  );

  /**
   * Check if a conversation is missing any required attributes
   *
   * @param {Object} conversationCustomAttributes - Current conversation's custom attributes
   * @param {Object} contactCustomAttributes - Custom attributes of the conversation's contact
   * @returns {Object} - Analysis result with missing attributes info
   */
  const checkMissingAttributes = (
    conversationCustomAttributes = {},
    contactCustomAttributes = {}
  ) => {
    // If no attributes are required, conversation can be resolved
    if (!requiredAttributes.value.length) {
      return { hasMissing: false, missing: [] };
    }

    // Find attributes that are missing or empty, each one looked up in the bag
    // that actually holds it
    const missing = requiredAttributes.value.filter(attribute => {
      const customAttributes =
        (attribute.attributeModel === CONTACT_ATTRIBUTE
          ? contactCustomAttributes
          : conversationCustomAttributes) || {};
      const value = customAttributes[attribute.value];

      // For checkbox/boolean attributes, only check if the key exists
      if (attribute.type === ATTRIBUTE_TYPES.CHECKBOX) {
        return !(attribute.value in customAttributes);
      }

      // For other attribute types, only consider null, undefined, empty string, or whitespace-only as missing
      // Allow falsy values like 0, false as they are valid filled values
      return value == null || String(value).trim() === '';
    });

    return {
      hasMissing: missing.length > 0,
      missing,
      all: requiredAttributes.value,
    };
  };

  /**
   * Split the flat map the resolve modal returns into the two places it has to
   * be written: the conversation and the contact.
   *
   * @param {Array} attributeList - The required attribute definitions shown in the modal
   * @param {Object} values - Values filled in the modal, keyed by attribute key
   * @returns {{ conversation: Object, contact: Object }}
   */
  const splitAttributesByModel = (attributeList = [], values = {}) =>
    attributeList.reduce(
      (acc, attribute) => {
        if (!(attribute.value in values)) return acc;

        const target =
          attribute.attributeModel === CONTACT_ATTRIBUTE
            ? acc.contact
            : acc.conversation;
        target[attribute.value] = values[attribute.value];
        return acc;
      },
      { conversation: {}, contact: {} }
    );

  return {
    requiredAttributeKeys,
    requiredAttributes,
    checkMissingAttributes,
    splitAttributesByModel,
  };
}
