import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { getInboxIconByType } from 'dashboard/helper/inbox';
import camelcaseKeys from 'camelcase-keys';
import parsePhoneNumber, {
  AsYouType,
  isValidPhoneNumber,
} from 'libphonenumber-js';
import ContactAPI from 'dashboard/api/contacts';

const DEFAULT_PHONE_COUNTRY = 'BR';

// Flag emoji from ISO country code (regional indicator symbols)
const countryToFlag = countryCode => {
  if (!countryCode || typeof countryCode !== 'string') return '';
  const code = countryCode.toUpperCase();
  if (code.length !== 2) return '';
  return String.fromCodePoint(...[...code].map(c => 0x1f1a5 + c.charCodeAt(0)));
};

// Determine if a raw input string looks like a phone number.
// Accepts: leading "+", or 8+ digits once all non-digit chars stripped.
export const isPhoneLikeInput = input => {
  if (typeof input !== 'string') return false;
  const trimmed = input.trim();
  if (!trimmed) return false;
  if (trimmed.startsWith('+')) return true;
  const digitsOnly = trimmed.replace(/\D/g, '');
  if (digitsOnly.length < 8) return false;
  // Reject strings that contain letters (treat as email/name).
  return !/[a-zA-Z]/.test(trimmed);
};

// Format a phone-like string for display.
// Returns { formatted, e164, country, countryFlag, isValid }.
export const formatPhoneDisplay = (
  input,
  defaultCountry = DEFAULT_PHONE_COUNTRY
) => {
  const empty = {
    formatted: '',
    e164: '',
    country: defaultCountry,
    countryFlag: countryToFlag(defaultCountry),
    isValid: false,
  };
  if (typeof input !== 'string' || !input.trim()) return empty;

  const trimmed = input.trim();
  // If user omitted the "+", assume default country by prefixing its dial code
  // via libphonenumber-js with defaultCountry context.
  const hasPlus = trimmed.startsWith('+');
  const candidate = hasPlus ? trimmed : trimmed.replace(/\D/g, '');

  const parsed = hasPlus
    ? parsePhoneNumber(candidate)
    : parsePhoneNumber(candidate, defaultCountry);

  if (parsed) {
    const country = parsed.country || defaultCountry;
    return {
      formatted: parsed.formatInternational(),
      e164: parsed.number,
      country,
      countryFlag: countryToFlag(country),
      isValid: parsed.isValid(),
    };
  }

  // Fallback: progressive formatting via AsYouType for partial inputs
  const asYouType = new AsYouType(defaultCountry);
  const formatted = hasPlus
    ? asYouType.input(candidate)
    : asYouType.input(`+${candidate}`) || asYouType.input(candidate);
  const country = asYouType.getCountry() || defaultCountry;
  const e164 = asYouType.getNumber()?.number || '';
  return {
    formatted: formatted || trimmed,
    e164,
    country,
    countryFlag: countryToFlag(country),
    isValid: e164 ? isValidPhoneNumber(e164) : false,
  };
};

const CHANNEL_PRIORITY = {
  'Channel::Email': 1,
  'Channel::Whatsapp': 2,
  'Channel::Sms': 3,
  'Channel::TwilioSms': 4,
  'Channel::WebWidget': 5,
  'Channel::Api': 6,
};

export const generateLabelForContactableInboxesList = ({
  name,
  email,
  channelType,
  phoneNumber,
}) => {
  if (channelType === INBOX_TYPES.EMAIL) {
    return `${name} (${email})`;
  }
  if (
    channelType === INBOX_TYPES.TWILIO ||
    channelType === INBOX_TYPES.WHATSAPP
  ) {
    return phoneNumber ? `${name} (${phoneNumber})` : name;
  }
  return name;
};

const transformInbox = ({
  name,
  id,
  email,
  channelType,
  phoneNumber,
  medium,
  ...rest
}) => ({
  id,
  icon: getInboxIconByType(channelType, medium, 'line'),
  label: generateLabelForContactableInboxesList({
    name,
    email,
    channelType,
    phoneNumber,
  }),
  action: 'inbox',
  value: id,
  name,
  email,
  phoneNumber,
  channelType,
  medium,
  ...rest,
});

export const compareInboxes = (a, b) => {
  // Channels that have no priority defined should come at the end.
  const priorityA = CHANNEL_PRIORITY[a.channelType] || 999;
  const priorityB = CHANNEL_PRIORITY[b.channelType] || 999;

  if (priorityA !== priorityB) {
    return priorityA - priorityB;
  }

  const nameA = a.name || '';
  const nameB = b.name || '';
  return nameA.localeCompare(nameB);
};

export const buildContactableInboxesList = contactInboxes => {
  if (!contactInboxes) return [];

  return contactInboxes.map(transformInbox).sort(compareInboxes);
};

export const getCapitalizedNameFromEmail = email => {
  const name = email.match(/^([^@]*)@/)?.[1] || email.split('@')[0];
  return name.charAt(0).toUpperCase() + name.slice(1);
};

export const processContactableInboxes = inboxes => {
  return inboxes.map(inbox => ({
    ...inbox.inbox,
    sourceId: inbox.sourceId,
  }));
};

export const mergeInboxDetails = (inboxesData, inboxesList = []) => {
  if (!inboxesData || !inboxesData.length) {
    return [];
  }

  return inboxesData.map(inboxData => {
    const matchingInbox =
      inboxesList.find(inbox => inbox.id === inboxData.id) || {};
    return {
      ...camelcaseKeys(matchingInbox, { deep: true }),
      ...inboxData,
    };
  });
};

export const prepareAttachmentPayload = (
  attachedFiles,
  directUploadsEnabled
) => {
  const files = [];
  attachedFiles.forEach(attachment => {
    if (directUploadsEnabled) {
      files.push(attachment.blobSignedId);
    } else {
      files.push(attachment.resource.file);
    }
  });
  return files;
};

export const prepareNewMessagePayload = ({
  targetInbox,
  selectedContact,
  message,
  subject,
  ccEmails,
  bccEmails,
  currentUser,
  attachedFiles = [],
  directUploadsEnabled = false,
  teamId = null,
}) => {
  const payload = {
    inboxId: targetInbox.id,
    sourceId: targetInbox.sourceId,
    contactId: Number(selectedContact.id),
    message: { content: message },
    assigneeId: currentUser.id,
  };

  if (teamId) {
    payload.teamId = teamId;
  }

  if (attachedFiles?.length) {
    payload.files = prepareAttachmentPayload(
      attachedFiles,
      directUploadsEnabled
    );
  }

  if (subject) {
    payload.mailSubject = subject;
  }

  if (ccEmails) {
    payload.message.cc_emails = ccEmails;
  }

  if (bccEmails) {
    payload.message.bcc_emails = bccEmails;
  }

  return payload;
};

export const prepareWhatsAppMessagePayload = ({
  targetInbox,
  selectedContact,
  message,
  templateParams,
  currentUser,
  teamId = null,
}) => {
  const payload = {
    inboxId: targetInbox.id,
    sourceId: targetInbox.sourceId,
    contactId: selectedContact.id,
    message: { content: message, template_params: templateParams },
    assigneeId: currentUser.id,
  };

  if (teamId) {
    payload.teamId = teamId;
  }

  return payload;
};

// API Calls
const MIN_SEARCH_LENGTH = 2;

export const createContactSearcher = () => {
  let controller = null;

  return async (query, { skipMinLength = false } = {}) => {
    const trimmed = typeof query === 'string' ? query.trim() : '';

    controller?.abort();

    if (!trimmed || (!skipMinLength && trimmed.length < MIN_SEARCH_LENGTH))
      return [];

    controller = new AbortController();
    const { signal } = controller;

    try {
      const {
        data: { payload },
      } = await ContactAPI.search(trimmed, 1, 'name', '', { signal });

      const camelCasedPayload = camelcaseKeys(payload, { deep: true });
      // Filter contacts that have either phone_number or email
      const filteredPayload = camelCasedPayload?.filter(
        contact => contact.phoneNumber || contact.email
      );
      return filteredPayload || [];
    } catch (error) {
      // Return null for aborted requests so callers can distinguish
      // "request was cancelled" from "no results found"
      if (error?.name === 'AbortError' || error?.name === 'CanceledError') {
        return null;
      }
      throw error;
    }
  };
};

export const createNewContact = async input => {
  const trimmed = typeof input === 'string' ? input.trim() : '';
  const isPhoneLike = trimmed.startsWith('+') || /^\d{8,}$/.test(trimmed);
  const normalizedPhone = trimmed.startsWith('+') ? trimmed : `+${trimmed}`;

  const payload = isPhoneLike
    ? {
        name: normalizedPhone,
        phone_number: normalizedPhone,
        validate_whatsapp: true,
      }
    : {
        name: getCapitalizedNameFromEmail(trimmed),
        email: trimmed,
      };

  const {
    data: {
      payload: { contact: newContact },
    },
  } = await ContactAPI.create(payload);

  return camelcaseKeys(newContact, { deep: true });
};

export const fetchContactableInboxes = async contactId => {
  const {
    data: { payload: inboxes = [] },
  } = await ContactAPI.getContactableInboxes(contactId);

  const convertInboxesToCamelKeys = camelcaseKeys(inboxes, { deep: true });

  return processContactableInboxes(convertInboxesToCamelKeys);
};
