import {
  generateTimeSlots,
  getTime,
  timeSlotParse,
  timeSlotTransform,
  timeZoneOptions,
} from '../businessHour';

describe('#generateTimeSlots', () => {
  it('returns correct number of time slots for 15-minute intervals', () => {
    const slots = generateTimeSlots(15);
    // 24 horas * 4 slots por hora + 1 para 23:59 = 97 slots
    expect(slots.length).toStrictEqual(97);
  });

  it('returns correct number of time slots for 30-minute intervals', () => {
    const slots = generateTimeSlots(30);
    // 24 horas * 2 slots por hora + 1 para 23:59 = 49 slots
    expect(slots.length).toStrictEqual(49);
  });

  it('returns correct time slots for 4-hour intervals', () => {
    expect(generateTimeSlots(240)).toStrictEqual([
      '00:00',
      '04:00',
      '08:00',
      '12:00',
      '16:00',
      '20:00',
      '23:59',
    ]);
  });

  it('always starts with 00:00', () => {
    expect(generateTimeSlots(15)[0]).toStrictEqual('00:00');
    expect(generateTimeSlots(30)[0]).toStrictEqual('00:00');
    expect(generateTimeSlots(60)[0]).toStrictEqual('00:00');
  });

  it('always ends with 23:59', () => {
    const slots15 = generateTimeSlots(15);
    const slots30 = generateTimeSlots(30);
    const slots60 = generateTimeSlots(60);

    expect(slots15[slots15.length - 1]).toStrictEqual('23:59');
    expect(slots30[slots30.length - 1]).toStrictEqual('23:59');
    expect(slots60[slots60.length - 1]).toStrictEqual('23:59');
  });

  it('includes 23:59 even when it would not be in regular intervals', () => {
    const slots = generateTimeSlots(30);
    expect(slots).toContain('23:59');
    expect(slots).toContain('23:30'); // Regular interval
  });

  it('does not duplicate 23:59 if it already exists in regular intervals', () => {
    // Com intervalo de 1 minuto o 23:59 aparece naturalmente
    const slots = generateTimeSlots(1);
    const count11_59 = slots.filter(slot => slot === '23:59').length;
    expect(count11_59).toStrictEqual(1);
  }, 15000);

  it('generates correct time format', () => {
    const slots = generateTimeSlots(60);
    expect(slots).toContain('01:00');
    expect(slots).toContain('12:00');
    expect(slots).toContain('13:00');
    expect(slots).toContain('23:00');
  });

  it('handles edge case with very large step', () => {
    const slots = generateTimeSlots(1440); // 24 hours
    expect(slots).toStrictEqual(['00:00', '23:59']);
  });
});

describe('#getTime', () => {
  it('formats afternoon hours in 24h', () => {
    expect(getTime(15, 30)).toStrictEqual('15:30');
  });
  it('pads midnight and single digits', () => {
    expect(getTime(0, 0)).toStrictEqual('00:00');
    expect(getTime(9, 5)).toStrictEqual('09:05');
  });
});

describe('#timeSlotParse', () => {
  it('returns parses correctly', () => {
    const slot = {
      day_of_week: 1,
      open_hour: 1,
      open_minutes: 30,
      close_hour: 4,
      close_minutes: 30,
      closed_all_day: false,
      open_all_day: false,
    };

    expect(timeSlotParse([slot])).toStrictEqual([
      {
        day: 1,
        from: '01:30',
        to: '04:30',
        valid: true,
        openAllDay: false,
      },
    ]);
  });
});

describe('#timeSlotTransform', () => {
  it('returns transforms correctly', () => {
    const slot = {
      day: 1,
      from: '01:30',
      to: '04:30',
      valid: true,
      openAllDay: false,
    };

    expect(timeSlotTransform([slot])).toStrictEqual([
      {
        day_of_week: 1,
        open_hour: 1,
        open_minutes: 30,
        close_hour: 4,
        close_minutes: 30,
        closed_all_day: false,
        open_all_day: false,
      },
    ]);
  });
});

describe('#timeZoneOptions', () => {
  it('returns transforms correctly', () => {
    expect(timeZoneOptions()[0]).toStrictEqual({
      value: 'Etc/GMT+12',
      label: 'International Date Line West (GMT−12:00)',
    });
  });
});
