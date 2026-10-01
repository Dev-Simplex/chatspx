import { paraCentavos } from '../catalogoPreco';

describe('paraCentavos', () => {
  it('lê a vírgula como decimal e o ponto como milhar', () => {
    expect(paraCentavos('1.299,90')).toBe(129990);
    expect(paraCentavos('89,9')).toBe(8990);
  });

  // Preço de imóvel é digitado assim; ler como decimal transformava 450 mil em R$ 450,00.
  it('lê ponto seguido de três dígitos como milhar, mesmo sem vírgula', () => {
    expect(paraCentavos('450.000')).toBe(45000000);
    expect(paraCentavos('1.250.000')).toBe(125000000);
  });

  it('lê os outros pontos como decimal', () => {
    expect(paraCentavos('12.5')).toBe(1250);
    expect(paraCentavos('749')).toBe(74900);
  });

  it('devolve nulo para campo vazio', () => {
    expect(paraCentavos('')).toBeNull();
  });
});
