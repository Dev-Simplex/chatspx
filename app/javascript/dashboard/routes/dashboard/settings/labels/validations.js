import { required, minLength, requiredIf } from '@vuelidate/validators';

// Mirrors the backend regex (RegexHelper::UNICODE_CHARACTER_NUMBER_HYPHEN_UNDERSCORE_DOT):
// must start with a unicode letter/number and may then contain letters, numbers,
// dot, hyphen and underscore. The minimum length is enforced by the separate
// minLength rule, so a single valid char is allowed here.
export const labelCharactersPattern = /^[\p{L}\p{N}][\p{L}\p{N}._-]*$/u;

export const validLabelCharacters = (str = '') =>
  !!str && labelCharactersPattern.test(str);

// Vuelidate 2 exposes each rule as an object ({ $invalid, $message, ... }),
// so we must read `rule.$invalid` — not the rule itself (which is always truthy).
export const getLabelTitleErrorMessage = validation => {
  const title = validation.title;
  if (!title.$error) return '';
  if (title.required?.$invalid) return 'LABEL_MGMT.FORM.NAME.REQUIRED_ERROR';
  if (title.minLength?.$invalid) {
    return 'LABEL_MGMT.FORM.NAME.MINIMUM_LENGTH_ERROR';
  }
  if (title.validLabelCharacters?.$invalid) {
    return 'LABEL_MGMT.FORM.NAME.VALID_ERROR';
  }
  return '';
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
