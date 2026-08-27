import {
  regraValeNoDia,
  regraDoDia,
  proximasOcorrencias,
  dataDaEnesimaOcorrencia,
  situacaoDaUnidade,
  comoTextoISO,
} from '../unitSchedule';

// Regra de agenda no formato que a API devolve.
const regra = extras => ({
  name: 'Regra',
  category: 'feriado',
  starts_on: '2026-09-01',
  ends_on: null,
  closed_all_day: true,
  frequency: 'nao_repete',
  repeat_interval: 1,
  weekdays: [],
  week_positions: [],
  month_days: [],
  until_date: null,
  open_hour: null,
  open_minutes: null,
  close_hour: null,
  close_minutes: null,
  ...extras,
});

const dia = texto => {
  const [ano, mes, diaDoMes] = texto.split('-').map(Number);
  return new Date(ano, mes - 1, diaDoMes, 12);
};

const datas = ocorrencias => ocorrencias.map(comoTextoISO);

describe('#regraValeNoDia', () => {
  it('data única vale só no próprio dia', () => {
    const natal = regra({ starts_on: '2026-12-25' });
    expect(regraValeNoDia(natal, dia('2026-12-25'))).toBe(true);
    expect(regraValeNoDia(natal, dia('2026-12-24'))).toBe(false);
    expect(regraValeNoDia(natal, dia('2027-12-25'))).toBe(false);
  });

  it('casa também com data construída à meia-noite (é o que o calendário monta)', () => {
    const natal = regra({ starts_on: '2026-12-25' });
    const meiaNoite = new Date(2026, 11, 25);
    expect(regraValeNoDia(natal, meiaNoite)).toBe(true);
    const fimDoDia = new Date(2026, 11, 25, 23, 59);
    expect(regraValeNoDia(natal, fimDoDia)).toBe(true);
  });

  it('período cobre todos os dias entre início e fim, inclusive a virada do ano', () => {
    const ferias = regra({ starts_on: '2026-12-20', ends_on: '2027-01-05' });
    expect(regraValeNoDia(ferias, dia('2026-12-20'))).toBe(true);
    expect(regraValeNoDia(ferias, dia('2026-12-31'))).toBe(true);
    expect(regraValeNoDia(ferias, dia('2027-01-05'))).toBe(true);
    expect(regraValeNoDia(ferias, dia('2027-01-06'))).toBe(false);
    expect(regraValeNoDia(ferias, dia('2026-12-19'))).toBe(false);
  });

  it('anual ignora o ano cadastrado', () => {
    const natal = regra({ starts_on: '2025-12-25', frequency: 'anual' });
    expect(regraValeNoDia(natal, dia('2026-12-25'))).toBe(true);
    expect(regraValeNoDia(natal, dia('2030-12-25'))).toBe(true);
    expect(regraValeNoDia(natal, dia('2026-12-26'))).toBe(false);
  });

  it('anual a cada 2 anos pula o ano do meio', () => {
    const bienal = regra({
      starts_on: '2026-07-10',
      frequency: 'anual',
      repeat_interval: 2,
    });
    expect(regraValeNoDia(bienal, dia('2026-07-10'))).toBe(true);
    expect(regraValeNoDia(bienal, dia('2027-07-10'))).toBe(false);
    expect(regraValeNoDia(bienal, dia('2028-07-10'))).toBe(true);
  });

  it('semanal a cada 2 semanas mantém o ritmo ao cruzar a virada do ano', () => {
    // 2026-12-20 é domingo; a cada 2 semanas => 20/12, 03/01, 17/01
    const quinzenal = regra({
      starts_on: '2026-12-20',
      frequency: 'semanal',
      repeat_interval: 2,
      weekdays: [0],
    });
    expect(regraValeNoDia(quinzenal, dia('2026-12-20'))).toBe(true);
    expect(regraValeNoDia(quinzenal, dia('2026-12-27'))).toBe(false);
    expect(regraValeNoDia(quinzenal, dia('2027-01-03'))).toBe(true);
    expect(regraValeNoDia(quinzenal, dia('2027-01-17'))).toBe(true);
  });

  it('mensal no 1º e 3º domingo acerta os domingos certos por seis meses', () => {
    const domingos = regra({
      starts_on: '2026-09-01',
      frequency: 'mensal',
      weekdays: [0],
      week_positions: [1, 3],
      closed_all_day: false,
      open_hour: 8,
      open_minutes: 0,
      close_hour: 12,
      close_minutes: 0,
    });
    [
      '2026-09-06',
      '2026-09-20',
      '2026-10-04',
      '2026-10-18',
      '2026-11-01',
      '2026-11-15',
    ].forEach(data => expect(regraValeNoDia(domingos, dia(data))).toBe(true));
    ['2026-09-13', '2026-09-27', '2026-10-11', '2026-09-07'].forEach(data =>
      expect(regraValeNoDia(domingos, dia(data))).toBe(false)
    );
  });

  it('mensal no último dia do mês acerta fevereiro comum e bissexto', () => {
    const inventario = regra({
      starts_on: '2026-01-31',
      frequency: 'mensal',
      month_days: [-1],
    });
    expect(regraValeNoDia(inventario, dia('2026-02-28'))).toBe(true);
    expect(regraValeNoDia(inventario, dia('2026-02-27'))).toBe(false);
    expect(regraValeNoDia(inventario, dia('2028-02-29'))).toBe(true);
    expect(regraValeNoDia(inventario, dia('2028-02-28'))).toBe(false);
  });

  it('mensal na última semana acerta o 5º domingo quando existe', () => {
    const ultimo = regra({
      starts_on: '2026-09-01',
      frequency: 'mensal',
      weekdays: [0],
      week_positions: [-1],
    });
    expect(regraValeNoDia(ultimo, dia('2026-09-27'))).toBe(true);
    expect(regraValeNoDia(ultimo, dia('2026-09-20'))).toBe(false);
  });

  it('não vale antes do início nem depois do limite, e o limite é inclusivo', () => {
    const temporada = regra({
      starts_on: '2026-09-06',
      frequency: 'semanal',
      weekdays: [0],
      until_date: '2026-09-20',
    });
    expect(regraValeNoDia(temporada, dia('2026-08-30'))).toBe(false);
    expect(regraValeNoDia(temporada, dia('2026-09-20'))).toBe(true);
    expect(regraValeNoDia(temporada, dia('2026-09-27'))).toBe(false);
  });
});

describe('#regraDoDia', () => {
  it('a mais específica vence a mais genérica', () => {
    const unidade = {
      exceptions: [
        regra({
          name: 'Todo domingo',
          frequency: 'semanal',
          weekdays: [0],
          starts_on: '2026-01-01',
        }),
        regra({ name: 'Só neste domingo', starts_on: '2026-09-06' }),
      ],
    };
    expect(regraDoDia(unidade, dia('2026-09-06')).name).toBe(
      'Só neste domingo'
    );
    expect(regraDoDia(unidade, dia('2026-09-13')).name).toBe('Todo domingo');
  });

  it('empate na especificidade: vence a que fecha', () => {
    const unidade = {
      exceptions: [
        regra({
          name: 'Abre no plantão',
          frequency: 'semanal',
          weekdays: [0],
          starts_on: '2026-01-01',
          closed_all_day: false,
          open_hour: 8,
          open_minutes: 0,
          close_hour: 12,
          close_minutes: 0,
        }),
        regra({
          name: 'Fechada',
          frequency: 'semanal',
          weekdays: [0],
          starts_on: '2026-01-01',
        }),
      ],
    };
    expect(regraDoDia(unidade, dia('2026-09-06')).name).toBe('Fechada');
  });

  it('devolve null quando nenhuma regra cai no dia', () => {
    const unidade = { exceptions: [regra({ starts_on: '2026-12-25' })] };
    expect(regraDoDia(unidade, dia('2026-09-06'))).toBeNull();
  });
});

describe('#proximasOcorrencias', () => {
  it('lista os próximos 1º e 3º domingos a partir de uma data', () => {
    const domingos = regra({
      starts_on: '2026-09-01',
      frequency: 'mensal',
      weekdays: [0],
      week_positions: [1, 3],
    });
    expect(
      datas(proximasOcorrencias(domingos, 4, dia('2026-09-01')))
    ).toStrictEqual(['2026-09-06', '2026-09-20', '2026-10-04', '2026-10-18']);
  });

  it('não devolve nada quando o limite já passou', () => {
    const vencida = regra({
      starts_on: '2026-09-06',
      frequency: 'semanal',
      weekdays: [0],
      until_date: '2026-09-20',
    });
    expect(proximasOcorrencias(vencida, 3, dia('2026-10-01'))).toStrictEqual(
      []
    );
  });
});

describe('#dataDaEnesimaOcorrencia', () => {
  it('converte "após N ocorrências" na data-limite equivalente', () => {
    const quinzenal = regra({
      starts_on: '2026-12-20',
      frequency: 'semanal',
      repeat_interval: 2,
      weekdays: [0],
    });
    // 20/12, 03/01, 17/01 -> a 3ª ocorrência é o limite
    expect(dataDaEnesimaOcorrencia(quinzenal, 3)).toBe('2027-01-17');
  });
});

describe('#situacaoDaUnidade', () => {
  const grade = [0, 1, 2, 3, 4, 5, 6].map(diaSemana => ({
    day_of_week: diaSemana,
    closed_all_day: [0, 6].includes(diaSemana),
    open_all_day: false,
    open_hour: 8,
    open_minutes: 0,
    close_hour: 18,
    close_minutes: 0,
  }));

  it('a regra ABRE um domingo que a grade da semana fecha', () => {
    const unidade = {
      timezone: 'America/Cuiaba',
      working_hours: grade,
      exceptions: [
        regra({
          name: 'Plantão de domingo',
          category: 'evento',
          starts_on: '2026-09-01',
          frequency: 'mensal',
          weekdays: [0],
          week_positions: [1, 3],
          closed_all_day: false,
          open_hour: 8,
          open_minutes: 0,
          close_hour: 12,
          close_minutes: 0,
        }),
      ],
    };
    // 06/09/2026 é 1º domingo; 13:00 UTC = 09:00 em Cuiabá
    const situacao = situacaoDaUnidade(
      unidade,
      new Date('2026-09-06T13:00:00Z')
    );
    expect(situacao.aberta).toBe(true);
    expect(situacao.faixa).toBe('08:00 – 12:00');
    expect(situacao.excecao).toBe('Plantão de domingo');
    expect(situacao.categoria).toBe('evento');

    // domingo sem regra: a grade manda, e a grade fecha
    const semRegra = situacaoDaUnidade(
      unidade,
      new Date('2026-09-13T13:00:00Z')
    );
    expect(semRegra.aberta).toBe(false);
    expect(semRegra.excecao).toBe('');
  });

  it('período de férias fecha um dia útil no meio', () => {
    const unidade = {
      timezone: 'America/Cuiaba',
      working_hours: grade,
      exceptions: [
        regra({
          name: 'Férias coletivas',
          starts_on: '2026-12-20',
          ends_on: '2027-01-05',
        }),
      ],
    };
    // 30/12/2026 é quarta-feira
    const situacao = situacaoDaUnidade(
      unidade,
      new Date('2026-12-30T15:00:00Z')
    );
    expect(situacao.aberta).toBe(false);
    expect(situacao.excecao).toBe('Férias coletivas');
  });
});

describe('parada para o almoço', () => {
  const comAlmoco = {
    timezone: 'America/Cuiaba',
    working_hours: [0, 1, 2, 3, 4, 5, 6].map(diaSemana => ({
      day_of_week: diaSemana,
      closed_all_day: [0, 6].includes(diaSemana),
      open_all_day: false,
      open_hour: 8,
      open_minutes: 0,
      close_hour: 18,
      close_minutes: 0,
      break_start_hour: 12,
      break_start_minutes: 0,
      break_end_hour: 13,
      break_end_minutes: 30,
    })),
    exceptions: [],
  };

  // 02/09/2026 é quarta-feira. UTC-4 em Cuiabá.
  const naHora = hora => new Date(`2026-09-02T${hora}:00Z`);

  it('fecha durante o almoço e diz a que horas volta', () => {
    const almocando = situacaoDaUnidade(comAlmoco, naHora('16:30')); // 12:30 local
    expect(almocando.aberta).toBe(false);
    expect(almocando.voltaAs).toBe('13:30');
  });

  it('abre antes e depois da parada', () => {
    expect(situacaoDaUnidade(comAlmoco, naHora('14:00')).aberta).toBe(true); // 10:00
    expect(situacaoDaUnidade(comAlmoco, naHora('18:00')).aberta).toBe(true); // 14:00
  });

  it('o limite da volta é inclusivo: 13:30 já está aberta', () => {
    const naVolta = situacaoDaUnidade(comAlmoco, naHora('17:30')); // 13:30 local
    expect(naVolta.aberta).toBe(true);
    expect(naVolta.voltaAs).toBe('');
  });

  it('a faixa legível mostra os dois turnos', () => {
    expect(situacaoDaUnidade(comAlmoco, naHora('14:00')).faixa).toBe(
      '08:00 – 12:00 · 13:30 – 18:00'
    );
  });

  it('dia sem pausa continua com uma faixa só', () => {
    const semPausa = {
      ...comAlmoco,
      working_hours: comAlmoco.working_hours.map(hora => ({
        ...hora,
        break_start_hour: null,
        break_start_minutes: null,
        break_end_hour: null,
        break_end_minutes: null,
      })),
    };
    const situacao = situacaoDaUnidade(semPausa, naHora('16:30'));
    expect(situacao.aberta).toBe(true);
    expect(situacao.faixa).toBe('08:00 – 18:00');
    expect(situacao.voltaAs).toBe('');
  });
});
