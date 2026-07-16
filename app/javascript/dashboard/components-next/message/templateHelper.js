import { MESSAGE_TYPES } from './constants';

/**
 * @typedef {Object} TemplateInfo
 * @property {string|null} name - The template name, when the payload carries one
 */

/**
 * Reads the WhatsApp template descriptor off a message.
 *
 * Approved templates (HSM) are stored under `additional_attributes.template_params` —
 * camelized to `additionalAttributes.templateParams` by MessageList — by every sender that
 * pushes one: `Flows::ActionService#send_template`, scheduled messages and the campaign
 * dispatcher, all of which create the message as `outgoing`. A regular reply carries no
 * `templateParams`, which is what keeps the badge off ordinary messages.
 *
 * `name` is `required` in `Message::TEMPLATE_PARAMS_SCHEMA`, but this stays defensive on
 * purpose: a partial payload must degrade to an unnamed badge, never break the bubble.
 *
 * @param {Object} [message] - The camelized message
 * @param {number} [message.messageType] - One of MESSAGE_TYPES
 * @param {Object} [message.additionalAttributes] - The camelized additional attributes
 * @returns {TemplateInfo|null} The descriptor, or null when the message is not a template
 */
export const getTemplateInfo = ({ messageType, additionalAttributes } = {}) => {
  if (messageType !== MESSAGE_TYPES.OUTGOING) return null;

  const templateParams = additionalAttributes?.templateParams;
  if (
    !templateParams ||
    typeof templateParams !== 'object' ||
    Array.isArray(templateParams)
  ) {
    return null;
  }

  const name =
    typeof templateParams.name === 'string' ? templateParams.name.trim() : '';

  return { name: name || null };
};
