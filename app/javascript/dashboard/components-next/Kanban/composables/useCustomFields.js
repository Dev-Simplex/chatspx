// Kanban v2 (Fase 2) — shared helpers for funnel custom fields. Pure functions
// so they're safe to call in render. Field definitions come camelCased from the
// store (key, label, fieldType, attributeKey, showOnCard, options). Values live
// in conversation.custom_attributes under `funnel_<id>_<key>`.

// Types the MVP can render AND edit. Mirrors FunnelCustomField::FIELD_TYPES.
export const FIELD_TYPES = [
  { value: 'text', icon: 'i-lucide-type' },
  { value: 'long_text', icon: 'i-lucide-text' },
  { value: 'number', icon: 'i-lucide-hash' },
  { value: 'date', icon: 'i-lucide-calendar' },
  { value: 'dropdown', icon: 'i-lucide-list' },
  { value: 'checkbox', icon: 'i-lucide-check-square' },
  { value: 'rating', icon: 'i-lucide-star' },
  { value: 'phone', icon: 'i-lucide-phone' },
  { value: 'email', icon: 'i-lucide-mail' },
  { value: 'link', icon: 'i-lucide-link' },
];

export const NUMERIC_TYPES = ['number', 'rating'];

// The fully-qualified key inside conversation.custom_attributes.
export const fieldAttributeKey = field =>
  field?.attributeKey || `funnel_${field?.funnelId}_${field?.key}`;

// Raw stored value for a field on a conversation (string|undefined).
export const rawFieldValue = (field, customAttributes = {}) => {
  if (!field || !customAttributes) return undefined;
  return customAttributes[fieldAttributeKey(field)];
};

// Parse a dropdown's options (stored as { choices: [..] } or a CSV string).
export const dropdownChoices = field => {
  const choices = field?.options?.choices;
  if (Array.isArray(choices)) return choices.filter(c => c != null && c !== '');
  if (typeof choices === 'string') {
    return choices
      .split(',')
      .map(c => c.trim())
      .filter(Boolean);
  }
  return [];
};

// Human-readable, compact display value for a card chip / read-only view.
export const formatFieldValue = (field, rawValue) => {
  if (rawValue === undefined || rawValue === null || rawValue === '') return '';
  switch (field?.fieldType) {
    case 'checkbox':
      return rawValue === true || rawValue === 'true' || rawValue === '1'
        ? '✓'
        : '✗';
    case 'rating': {
      const n = Math.max(0, Math.min(5, Math.round(Number(rawValue) || 0)));
      return '★'.repeat(n) + '☆'.repeat(5 - n);
    }
    case 'number': {
      const n = Number(rawValue);
      return Number.isFinite(n) ? n.toLocaleString() : String(rawValue);
    }
    case 'date': {
      const d = new Date(rawValue);
      return Number.isNaN(d.getTime())
        ? String(rawValue)
        : d.toLocaleDateString();
    }
    default:
      return String(rawValue);
  }
};

// Whether a chip/value should be treated as "filled" (worth showing on a card).
export const hasFieldValue = (field, rawValue) => {
  if (rawValue === undefined || rawValue === null || rawValue === '')
    return false;
  if (field?.fieldType === 'checkbox') {
    return rawValue === true || rawValue === 'true' || rawValue === '1';
  }
  return true;
};

// Coerce an editor input value into what we persist (always a string in jsonb,
// or '' to clear). Checkbox persists 'true'/'' so the backend regex/merge is happy.
export const serializeFieldValue = (field, inputValue) => {
  if (field?.fieldType === 'checkbox') {
    return inputValue ? 'true' : '';
  }
  if (inputValue === undefined || inputValue === null) return '';
  return String(inputValue).trim();
};
