import { required, minLength, requiredIf } from '@vuelidate/validators';

// Mirrors the backend regex (RegexHelper::UNICODE_CHARACTER_NUMBER_HYPHEN_UNDERSCORE_DOT):
// must start with a unicode letter/number and may then contain letters, numbers,
// dot, hyphen and underscore. The minimum length is enforced by the separate
// minLength rule, so a single valid char is allowed here.
export const labelCharactersPattern = /^[\p{L}\p{N}][\p{L}\p{N}._-]*$/u;
// A single character that is allowed anywhere except as the first one.
const allowedCharPattern = /[\p{L}\p{N}._-]/u;

export const validLabelCharacters = (str = '') =>
  !!str && labelCharactersPattern.test(str);

// Pinpoints WHY the character rule failed so the message can name the exact
// problem (a space, a bad starting char, or the specific forbidden character).
const getInvalidCharactersError = (title = '') => {
  if (/\s/.test(title)) {
    return { key: 'LABEL_MGMT.FORM.NAME.NO_SPACES_ERROR', values: {} };
  }
  if (/^[._-]/.test(title)) {
    return {
      key: 'LABEL_MGMT.FORM.NAME.NO_LEADING_SEPARATOR_ERROR',
      values: {},
    };
  }
  const invalidChar = Array.from(title).find(
    char => !allowedCharPattern.test(char)
  );
  if (invalidChar) {
    return {
      key: 'LABEL_MGMT.FORM.NAME.INVALID_CHARACTER_ERROR',
      values: { char: invalidChar },
    };
  }
  return { key: 'LABEL_MGMT.FORM.NAME.VALID_ERROR', values: {} };
};

// Vuelidate 2 exposes each rule as an object ({ $invalid, $message, ... }),
// so we must read `rule.$invalid` — not the rule itself (which is always truthy).
// Returns an { key, values } pair so the caller can interpolate via i18n.
export const getLabelTitleError = (validation, title = '') => {
  const field = validation.title;
  if (!field.$error) return { key: '', values: {} };
  if (field.required?.$invalid) {
    return { key: 'LABEL_MGMT.FORM.NAME.REQUIRED_ERROR', values: {} };
  }
  if (field.minLength?.$invalid) {
    return { key: 'LABEL_MGMT.FORM.NAME.MINIMUM_LENGTH_ERROR', values: {} };
  }
  if (field.validLabelCharacters?.$invalid) {
    return getInvalidCharactersError(title);
  }
  return { key: '', values: {} };
};

export default {
  title: {
    required,
    minLength: minLength(2),
    validLabelCharacters,
  },
  description: {},
  color: {
    required,
  },
  showOnSidebar: {},
  visibility: {},
  // team_id is only required when the label is scoped to a team.
  teamId: {
    required: requiredIf((_value, model) => model?.visibility === 'team'),
  },
};
