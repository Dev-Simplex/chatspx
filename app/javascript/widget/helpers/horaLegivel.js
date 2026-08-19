/**
 * Hora em 12 h para o texto de disponibilidade — bloco 2.18.
 *
 * `AvailabilityText.vue` importava `getTime` de
 * `dashboard/routes/dashboard/settings/inbox/helpers/businessHour.js`. A função
 * é aritmética pura, seis linhas — mas o módulo de onde ela vinha importa
 * `date-fns/parse` e `timezones.json`, e os dois entravam no first-paint do
 * widget: 74.189 B crus de `parse` mais 6.831 B da tabela de fusos, medidos no
 * grafo de produção. Nenhum dos dois é usado por esta função.
 *
 * A implementação é a MESMA do original, e há um teste que compara as duas
 * saídas hora a hora — se lá mudar, aqui reprova.
 */
export const getTime = (hour, minute) => {
  const merdian = hour > 11 ? 'PM' : 'AM';
  const modHour = hour > 12 ? hour % 12 : hour || 12;
  const parsedHour = modHour < 10 ? `0${modHour}` : modHour;
  const parsedMinute = minute < 10 ? `0${minute}` : minute;
  return `${parsedHour}:${parsedMinute} ${merdian}`;
};
