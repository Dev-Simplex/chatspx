import { useVuelidate } from '@vuelidate/core';
import { reactive } from 'vue';
import validations, {
  validLabelCharacters,
  getLabelTitleError,
} from '../validations';

describe('#validLabelCharacters', () => {
  it('validates the label', () => {
    // invalid
    expect(validLabelCharacters('')).toEqual(false);
    expect(validLabelCharacters('str str')).toEqual(false); // space
    expect(validLabelCharacters('label(3)')).toEqual(false); // parentheses
    expect(validLabelCharacters('mudança (3) - 4.0')).toEqual(false); // space + parens
    expect(validLabelCharacters('.hidden')).toEqual(false); // leading dot
    expect(validLabelCharacters('-bad')).toEqual(false); // leading hyphen
    expect(validLabelCharacters('_bad')).toEqual(false); // leading underscore
    // valid
    expect(validLabelCharacters('str_str')).toEqual(true);
    expect(validLabelCharacters('str-str')).toEqual(true);
    expect(validLabelCharacters('str.str')).toEqual(true);
    expect(validLabelCharacters('v1.2.3-beta_final')).toEqual(true);
    expect(validLabelCharacters('mudança-4.0')).toEqual(true); // unicode + dot/hyphen
  });
});

describe('#getLabelTitleError', () => {
  // Vuelidate 2 exposes each rule as an object with a `$invalid` flag.
  const createValidation = t => ({
    title: {
      $error: t.$error,
      required: { $invalid: t.requiredInvalid },
      minLength: { $invalid: t.minLengthInvalid },
      validLabelCharacters: { $invalid: t.validLabelCharactersInvalid },
    },
  });

  const charRuleFailed = createValidation({
    $error: true,
    requiredInvalid: false,
    minLengthInvalid: false,
    validLabelCharactersInvalid: true,
  });

  it('returns no key when there are no validation errors', () => {
    const v = createValidation({
      $error: false,
      requiredInvalid: false,
      minLengthInvalid: false,
      validLabelCharactersInvalid: false,
    });
    expect(getLabelTitleError(v, 'valid').key).toEqual('');
  });

  it('flags a missing title as required', () => {
    const v = createValidation({
      $error: true,
      requiredInvalid: true,
      minLengthInvalid: true,
      validLabelCharactersInvalid: false,
    });
    expect(getLabelTitleError(v, '').key).toEqual(
      'LABEL_MGMT.FORM.NAME.REQUIRED_ERROR'
    );
  });

  it('flags a short title', () => {
    const v = createValidation({
      $error: true,
      requiredInvalid: false,
      minLengthInvalid: true,
      validLabelCharactersInvalid: false,
    });
    expect(getLabelTitleError(v, 'a').key).toEqual(
      'LABEL_MGMT.FORM.NAME.MINIMUM_LENGTH_ERROR'
    );
  });

  describe('when the character rule fails, it names the exact reason', () => {
    it('reports spaces', () => {
      expect(getLabelTitleError(charRuleFailed, 'triagem ').key).toEqual(
        'LABEL_MGMT.FORM.NAME.NO_SPACES_ERROR'
      );
    });

    it('reports a leading separator', () => {
      expect(getLabelTitleError(charRuleFailed, '.oculto').key).toEqual(
        'LABEL_MGMT.FORM.NAME.NO_LEADING_SEPARATOR_ERROR'
      );
      expect(getLabelTitleError(charRuleFailed, '-x').key).toEqual(
        'LABEL_MGMT.FORM.NAME.NO_LEADING_SEPARATOR_ERROR'
      );
    });

    it('reports the specific forbidden character', () => {
      const err = getLabelTitleError(charRuleFailed, 'label(3)');
      expect(err.key).toEqual('LABEL_MGMT.FORM.NAME.INVALID_CHARACTER_ERROR');
      expect(err.values).toEqual({ char: '(' });
    });
  });
});

// Integration guard: runs against a REAL Vuelidate instance (not a hand-mocked
// shape) so the helper can never silently break against the actual v2 API again.
describe('#getLabelTitleError against a real vuelidate instance', () => {
  const errorFor = title => {
    const state = reactive({ title });
    const v$ = useVuelidate(validations, state);
    v$.value.title.$touch();
    return getLabelTitleError(v$.value, title);
  };

  it('flags an empty title as required', () => {
    expect(errorFor('').key).toEqual('LABEL_MGMT.FORM.NAME.REQUIRED_ERROR');
  });

  it('flags a single character as too short', () => {
    expect(errorFor('a').key).toEqual(
      'LABEL_MGMT.FORM.NAME.MINIMUM_LENGTH_ERROR'
    );
  });

  it('flags a trailing space with the no-spaces message', () => {
    expect(errorFor('triagem ').key).toEqual(
      'LABEL_MGMT.FORM.NAME.NO_SPACES_ERROR'
    );
  });

  it('flags parentheses with the specific character', () => {
    expect(errorFor('label(3)')).toEqual({
      key: 'LABEL_MGMT.FORM.NAME.INVALID_CHARACTER_ERROR',
      values: { char: '(' },
    });
  });

  it('returns no key for a valid title', () => {
    expect(errorFor('mudança-4.0').key).toEqual('');
  });
});
