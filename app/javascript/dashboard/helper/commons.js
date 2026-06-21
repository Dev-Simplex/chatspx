/* eslint no-param-reassign: 0 */

import getUuid from 'widget/helpers/uuid';
import { MESSAGE_STATUS, MESSAGE_TYPE } from 'shared/constants/messages';

export default () => {
  if (!Array.prototype.last) {
    Object.assign(Array.prototype, {
      last() {
        return this[this.length - 1];
      },
    });
  }
};

export const isEmptyObject = obj =>
  Object.keys(obj).length === 0 && obj.constructor === Object;

export const isJSONValid = value => {
  try {
    JSON.parse(value);
  } catch (e) {
    return false;
  }
  return true;
};

export const getTypingUsersText = (users = []) => {
  const count = users.length;
  const [firstUser, secondUser] = users;

  if (count === 1) {
    return ['TYPING.ONE', { user: firstUser.name }];
  }

  if (count === 2) {
    return [
      'TYPING.TWO',
      { user: firstUser.name, secondUser: secondUser.name },
    ];
  }

  return ['TYPING.MULTIPLE', { user: firstUser.name, count: count - 1 }];
};

export const createPendingMessage = data => {
  const timestamp = Math.floor(new Date().getTime() / 1000);
  const tempMessageId = getUuid();
  const { message, file, pendingAttachments } = data;

  // Rich optimistic attachments (in-conversation "uploading" bubble): each
  // carries a LOCAL preview (objectURL) + upload state so the message bubble
  // renders the media WHILE it transfers. On completion the server copy (same
  // echo_id) replaces it. Snake_case to match server shape — useCamelCase in the
  // message list turns these into fileType/dataUrl/uploadStatus/etc.
  let attachments = null;
  if (pendingAttachments?.length) {
    attachments = pendingAttachments.map((att, index) => ({
      id: `${tempMessageId}-${index}`,
      message_id: tempMessageId,
      file_type: att.fileType,
      data_url: att.dataUrl,
      thumb_url: att.thumbUrl || att.dataUrl,
      file_size: att.fileSize,
      extension: att.extension,
      file_name: att.fileName,
      upload_status: 'uploading',
      upload_progress: att.uploadProgress ?? null,
      upload_id: att.uploadId,
    }));
  } else if (file) {
    attachments = [{ id: tempMessageId }];
  }

  const pendingMessage = {
    ...data,
    content: message || null,
    id: tempMessageId,
    echo_id: tempMessageId,
    status: MESSAGE_STATUS.PROGRESS,
    created_at: timestamp,
    message_type: MESSAGE_TYPE.OUTGOING,
    conversation_id: data.conversationId,
    attachments,
  };

  return pendingMessage;
};

export const convertToAttributeSlug = text => {
  return text
    .toLowerCase()
    .replace(/[^\w ]+/g, '')
    .replace(/ +/g, '_');
};

export const convertToCategorySlug = text => {
  return text
    .toLowerCase()
    .replace(/[^\w ]+/g, '')
    .replace(/ +/g, '-');
};

export const convertToPortalSlug = text => {
  return text
    .toLowerCase()
    .replace(/[^\w ]+/g, '')
    .replace(/ +/g, '-');
};

/**
 * Strip curly braces, commas and leading/trailing whitespace from a search key.
 * Eg. "{{contact.name}}," => "contact.name"
 * @param {string} searchKey
 * @returns {string}
 */
export const sanitizeVariableSearchKey = (searchKey = '') => {
  return searchKey
    .replace(/[{}]/g, '') // remove all curly braces
    .replace(/,/g, '') // remove commas
    .trim();
};

/**
 * Check if a source_id is an unresolved WhatsApp LID.
 * @param {string} sourceId
 * @returns {boolean}
 */
export const isUnresolvedLid = sourceId => {
  return typeof sourceId === 'string' && sourceId.endsWith('@lid');
};

/**
 * Returns a display-safe contact name, masking LID identifiers.
 * @param {object} contact - Contact object with name, phoneNumber, sourceId
 * @returns {string}
 */
export const getSafeContactName = contact => {
  if (!contact) return '';
  const name = contact.name || contact.availableName || '';
  const sourceId =
    contact.sourceId ||
    contact.source_id ||
    contact.contactInboxes?.[0]?.sourceId ||
    '';

  if (
    isUnresolvedLid(sourceId) &&
    !contact.phoneNumber &&
    !contact.phone_number
  ) {
    if (name.match(/^[a-z]+-[a-z]+-\d+$/)) {
      return 'Identificando contato...';
    }
  }
  return name;
};

/**
 * Convert underscore-separated string to title case.
 * Eg. "round_robin" => "Round Robin"
 * @param {string} str
 * @returns {string}
 */
export const formatToTitleCase = str => {
  return (
    str
      ?.replace(/_/g, ' ')
      .replace(/\b\w/g, l => l.toUpperCase())
      .trim() || ''
  );
};
