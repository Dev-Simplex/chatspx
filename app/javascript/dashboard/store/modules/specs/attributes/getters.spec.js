import { getters } from '../../attributes';
import attributesList from './fixtures';

describe('#getters', () => {
  it('getAttributes', () => {
    const state = { records: attributesList };
    expect(getters.getAttributes(state)).toEqual([
      {
        attribute_display_name: 'Language',
        attribute_display_type: 1,
        attribute_description: 'The conversation language',
        attribute_key: 'language',
        attribute_model: 0,
      },
      {
        attribute_display_name: 'Language one',
        attribute_display_type: 2,
        attribute_description: 'The conversation language one',
        attribute_key: 'language_one',
        attribute_model: 1,
      },
    ]);
  });

  it('getAttributes deixa de fora os campos do catálogo', () => {
    const catalogo = {
      attribute_display_name: 'Dormitórios',
      attribute_key: 'dormitorios',
      attribute_model: 'catalog_attribute',
    };
    const state = { records: [...attributesList, catalogo] };

    expect(getters.getAttributes(state)).toEqual(attributesList);
    expect(getters.getAttributesByModel(state)('catalog_attribute')).toEqual([
      catalogo,
    ]);
  });

  it('getAttributesByModel', () => {
    const state = { records: attributesList };
    expect(getters.getAttributesByModel(state)(1)).toEqual([
      {
        attribute_display_name: 'Language one',
        attribute_display_type: 2,
        attribute_description: 'The conversation language one',
        attribute_key: 'language_one',
        attribute_model: 1,
      },
    ]);
  });

  it('getUIFlags', () => {
    const state = {
      uiFlags: {
        isFetching: true,
        isCreating: false,
      },
    };
    expect(getters.getUIFlags(state)).toEqual({
      isFetching: true,
      isCreating: false,
    });
  });
});
