import parse from 'date-fns/parse';
import getHours from 'date-fns/getHours';
import getMinutes from 'date-fns/getMinutes';
import timeZoneData from './timezones.json';

export const defaultTimeSlot = [
  {
    day: 0,
    to: '',
    from: '',
    valid: false,
  },
  {
    day: 1,
    to: '',
    from: '',
    valid: false,
  },
  {
    day: 2,
    to: '',
    from: '',
    valid: false,
  },
  {
    day: 3,
    to: '',
    from: '',
    valid: false,
  },
  {
    day: 4,
    to: '',
    from: '',
    valid: false,
  },
  {
    day: 5,
    to: '',
    from: '',
    valid: false,
  },
  {
    day: 6,
    to: '',
    from: '',
    valid: false,
  },
];

// Formato único de horário na interface: 24 h. O fork é pt-BR — a agenda se lê
// "17:00", e "05:00 PM" obrigava o usuário a converter de cabeça.
export const TIME_FORMAT = 'HH:mm';

export const MIDNIGHT = '00:00';
export const END_OF_DAY = '23:59';

export const getTime = (hour, minute) =>
  `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`;

export const generateTimeSlots = (step = 15) => {
  /*
    Lista de horários de 00:00 até o fim do dia, de `step` em `step` minutos.
    23:59 entra sempre como último slot, para fechar o dia.
  */
  const slots = [];
  for (let minutes = 0; minutes < 24 * 60; minutes += step) {
    slots.push(getTime(Math.floor(minutes / 60), minutes % 60));
  }

  if (!slots.includes(END_OF_DAY)) {
    slots.push(END_OF_DAY);
  }

  return slots;
};

export const timeSlotParse = timeSlots => {
  return timeSlots.map(slot => {
    const {
      day_of_week: day,
      open_hour: openHour,
      open_minutes: openMinutes,
      close_hour: closeHour,
      close_minutes: closeMinutes,
      closed_all_day: closedAllDay,
      open_all_day: openAllDay,
    } = slot;
    const from = closedAllDay ? '' : getTime(openHour, openMinutes);
    const to = closedAllDay ? '' : getTime(closeHour, closeMinutes);

    return {
      day,
      to,
      from,
      valid: !closedAllDay,
      openAllDay,
    };
  });
};

export const timeSlotTransform = timeSlots => {
  return timeSlots.map(slot => {
    const closed = slot.openAllDay ? false : !(slot.to && slot.from);
    const openAllDay = slot.openAllDay;
    let fromDate = '';
    let toDate = '';
    let openHour = '';
    let openMinutes = '';
    let closeHour = '';
    let closeMinutes = '';

    if (!closed) {
      fromDate = parse(slot.from, TIME_FORMAT, new Date());
      toDate = parse(slot.to, TIME_FORMAT, new Date());
      openHour = getHours(fromDate);
      openMinutes = getMinutes(fromDate);
      closeHour = getHours(toDate);
      closeMinutes = getMinutes(toDate);
    }

    return {
      day_of_week: slot.day,
      closed_all_day: closed,
      open_hour: openHour,
      open_minutes: openMinutes,
      close_hour: closeHour,
      close_minutes: closeMinutes,
      open_all_day: openAllDay,
    };
  });
};

export const timeZoneOptions = () => {
  return Object.keys(timeZoneData).map(key => ({
    label: key,
    value: timeZoneData[key],
  }));
};
