import { useVuelidate } from '@vuelidate/core';
import { reactive } from 'vue';
import validations, {
  validLabelCharacters,
  getLabelTitleErrorMessage,
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

describe('#getLabelTitleErrorMessage', () => {
  // Vuelidate 2 exposes each rule as an object with a `$invalid` flag.
  const createValidation = titleValidation => ({
    title: {
      $error: titleValidation.$error,
      required: { $invalid: titleValidation.requiredInvalid },
      minLength: { $invalid: titleValidation.minLengthInvalid },
      validLabelCharacters: {
        $invalid: titleValidation.validLabelCharactersInvalid,
      },
    },
  });

  it('returns an empty string when there are no validation errors', () => {
    const validation = createValidation({
      $error: false,
      requiredInvalid: false,
      minLengthInvalid: false,
      validLabelCharactersInvalid: false,
    });

    expect(getLabelTitleErrorMessage(validation)).toEqual('');
  });

  it('returns a required error message when the title is required but not provided', () => {
    const validation = createValidation({
      $error: true,
      requiredInvalid: true,
      minLengthInvalid: true,
      validLabelCharactersInvalid: false,
    });

    expect(getLabelTitleErrorMessage(validation)).toEqual(
      'LABEL_MGMT.FORM.NAME.REQUIRED_ERROR'
    );
  });

  it('returns a minimum length error message when the title is too short', () => {
    const validation = createValidation({
      $error: true,
      requiredInvalid: false,
      minLengthInvalid: true,
      validLabelCharactersInvalid: false,
    });

    expect(getLabelTitleErrorMessage(validation)).toEqual(
      'LABEL_MGMT.FORM.NAME.MINIMUM_LENGTH_ERROR'
    );
  });

  it('returns a valid label characters error message when the title has invalid characters', () => {
    const validation = createValidation({
      $error: true,
      requiredInvalid: false,
      minLengthInvalid: false,
      validLabelCharactersInvalid: true,
    });

    expect(getLabelTitleErrorMessage(validation)).toEqual(
      'LABEL_MGMT.FORM.NAME.VALID_ERROR'
    );
  });

  // Integration guard: runs against a REAL Vuelidate instance (not a hand-mocked
  // shape) so the helper can never silently break against the actual v2 API again.
  describe('against a real vuelidate instance', () => {
    const messageFor = title => {
      const state = reactive({ title });
      const v$ = useVuelidate(validations, state);
      v$.value.title.$touch();
      return getLabelTitleErrorMessage(v$.value);
    };

    it('flags an empty title as required', () => {
      expect(messageFor('')).toEqual('LABEL_MGMT.FORM.NAME.REQUIRED_ERROR');
    });

    it('flags a single character as too short', () => {
      expect(messageFor('a')).toEqual(
        'LABEL_MGMT.FORM.NAME.MINIMUM_LENGTH_ERROR'
      );
    });

    it('flags invalid characters with the valid-characters message', () => {
      expect(messageFor('mudança (3) - 4.0')).toEqual(
        'LABEL_MGMT.FORM.NAME.VALID_ERROR'
      );
    });

    it('returns no message for a valid title', () => {
      expect(messageFor('mudança-4.0')).toEqual('');
    });
  });
});
