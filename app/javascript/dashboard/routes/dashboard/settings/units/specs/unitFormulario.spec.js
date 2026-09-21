import {
  formatarCep,
  formatarTelefone,
  copiarHorarioParaDias,
} from '../unitFormulario';

describe('formatarCep', () => {
  it('escreve como o CEP é escrito: ponto no segundo, traço no quinto', () => {
    expect(formatarCep('78550041')).toBe('78.550-041');
  });

  it('aceita colado com traço ou com ponto', () => {
    expect(formatarCep('78550-041')).toBe('78.550-041');
    expect(formatarCep('78.550-041')).toBe('78.550-041');
  });

  it('descarta letra e corta no oitavo dígito', () => {
    expect(formatarCep('78a550b041999')).toBe('78.550-041');
  });

  it('não inventa pontuação enquanto o CEP está incompleto', () => {
    expect(formatarCep('78')).toBe('78');
    expect(formatarCep('785')).toBe('78.5');
    expect(formatarCep('')).toBe('');
    expect(formatarCep(null)).toBe('');
  });
});

describe('formatarTelefone', () => {
  it('poe o parentese assim que o DDD e digitado', () => {
    expect(formatarTelefone('6')).toBe('(6');
    expect(formatarTelefone('66')).toBe('(66');
    expect(formatarTelefone('663')).toBe('(66) 3');
  });

  it('fecha fixo com quatro digitos antes do traco', () => {
    expect(formatarTelefone('6635310000')).toBe('(66) 3531-0000');
  });

  it('fecha celular com cinco digitos antes do traco', () => {
    expect(formatarTelefone('66999998888')).toBe('(66) 99999-8888');
  });

  it('tira o 55 do numero colado em vez de cortar o final', () => {
    expect(formatarTelefone('+55 66 99999-8888')).toBe('(66) 99999-8888');
  });

  it('aceita o que ja vem formatado e o vazio', () => {
    expect(formatarTelefone('(66) 3531-0000')).toBe('(66) 3531-0000');
    expect(formatarTelefone('')).toBe('');
    expect(formatarTelefone(null)).toBe('');
  });
});

describe('copiarHorarioParaDias', () => {
  const grade = [
    { day: 0, from: '', to: '' },
    {
      day: 1,
      from: '07:48',
      to: '18:00',
      breakFrom: '12:00',
      breakTo: '13:00',
      valid: true,
    },
    {
      day: 2,
      from: '09:00',
      to: '17:00',
      breakFrom: '',
      breakTo: '',
      valid: true,
    },
    {
      day: 3,
      from: '09:00',
      to: '17:00',
      breakFrom: '',
      breakTo: '',
      valid: true,
    },
  ];

  it('copia para os dias abertos e diz quantos mudaram', () => {
    const { slots, dias } = copiarHorarioParaDias(grade, grade[1]);

    expect(dias).toEqual([2, 3]);
    expect(slots[2]).toMatchObject({
      from: '07:48',
      to: '18:00',
      breakFrom: '12:00',
      breakTo: '13:00',
    });
    expect(slots[3]).toMatchObject({ from: '07:48', to: '18:00' });
  });

  it('não abre o dia que está fechado', () => {
    const { slots } = copiarHorarioParaDias(grade, grade[1]);

    expect(slots[0]).toMatchObject({ day: 0, from: '', to: '' });
  });

  it('não mexe no dia de origem', () => {
    const { slots } = copiarHorarioParaDias(grade, grade[1]);

    expect(slots[1]).toBe(grade[1]);
  });
});
