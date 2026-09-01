import ptBR from '../locale/pt_BR/generalSettings.json';
import en from '../locale/en/generalSettings.json';

// Em 28/08/2026, ao adicionar a tela de recursos da conta, a chave GENERAL_SETTINGS.FORM.FEATURES
// foi SOBRESCRITA inteira. Ela já era usada pelos avisos de e-mail, e o resultado apareceu em
// produção como texto cru na tela: "GENERAL_SETTINGS.FORM.FEATURES.INBOUND_EMAIL_ENABLED".
//
// O erro foi escrever no lugar de mesclar. Estes exemplos travam as duas coisas que teriam pegado:
// as chaves em uso continuarem existindo, e os dois idiomas andarem juntos.
describe('chaves de generalSettings', () => {
  const chavesEmUso = {
    'FORM.FEATURES': ['INBOUND_EMAIL_ENABLED', 'CUSTOM_EMAIL_DOMAIN_ENABLED'],
    'FORM.ACCOUNT_FEATURES': ['TITLE', 'NOTE', 'GROUPS', 'HINT', 'API'],
  };

  const buscar = (obj, caminho) =>
    caminho.split('.').reduce((atual, parte) => atual?.[parte], obj.GENERAL_SETTINGS);

  describe.each(Object.entries(chavesEmUso))('%s', (caminho, esperadas) => {
    it.each([
      ['pt_BR', ptBR],
      ['en', en],
    ])('existe em %s com as chaves que a tela usa', (_idioma, dicionario) => {
      expect(Object.keys(buscar(dicionario, caminho))).toEqual(
        expect.arrayContaining(esperadas)
      );
    });
  });

  // FEATURES e ACCOUNT_FEATURES são coisas diferentes e precisam continuar separadas: a primeira é
  // aviso de e-mail, a segunda é a tela de recursos.
  it('FEATURES e ACCOUNT_FEATURES nao se misturam', () => {
    const features = Object.keys(buscar(ptBR, 'FORM.FEATURES'));
    const recursos = Object.keys(buscar(ptBR, 'FORM.ACCOUNT_FEATURES'));

    expect(features.filter(chave => recursos.includes(chave))).toEqual([]);
  });

  it('os dois idiomas tem o mesmo conjunto de chaves', () => {
    Object.keys(chavesEmUso).forEach(caminho => {
      expect(Object.keys(buscar(ptBR, caminho)).sort()).toEqual(
        Object.keys(buscar(en, caminho)).sort()
      );
    });
  });
});
