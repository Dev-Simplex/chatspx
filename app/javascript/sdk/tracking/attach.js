import { originAttributes } from './index';
import { FIRST } from './keys';

/**
 * Bloco 5.08 (T-C2.6) — entrega da origem ao widget, **pelo caminho de menor atrito**.
 *
 * ESTE ARQUIVO NÃO ESTÁ NO `sdk.js`. Ele mora no artefato sob demanda, junto com o resto do
 * coletor — e isso foi uma decisão tomada COM A BALANÇA NA MÃO: com ele no lado eager, o
 * delta do `sdk.js` era +728 B gzip; movido para cá, ver o número no relatório da trilha.
 * O que fica eager é só capturar e buscar.
 *
 * Nada de contrato novo: os dois eventos usados já existem no bridge do widget, e o que
 * está do outro lado deles também já existe.
 *
 *  · `set-custom-attributes`              → `contacts/setCustomAttributes`
 *  · `set-conversation-custom-attributes` → `conversation/setCustomAttributes`, que quando
 *    ainda NÃO há conversa guarda como `pendingCustomAttributes` e envia junto com a
 *    primeira mensagem (`conversation/actions.js`). É exatamente o que o aceite pede:
 *    "a conversa NASCE com o `first_utm_source` e o `gclid` certos".
 *
 * A DIVISÃO DE ESCOPO espelha o backend, e não é arbitrária: `Tracking::OriginRecorder`
 * grava `first_*` no CONTATO (write-once, quem trouxe a pessoa) e `last_*` na CONVERSA (o
 * que trouxe esta conversa). Mandar tudo para os dois lados duplicaria dado e faria o
 * painel mostrar a mesma coisa duas vezes.
 */

const split = attributes =>
  Object.entries(attributes).reduce(
    (acc, [key, value]) => {
      if (key.startsWith(FIRST)) acc.contato[key] = value;
      else acc.conversa[key] = value;
      return acc;
    },
    { contato: {}, conversa: {} }
  );

/**
 * Coleta e entrega. `sendMessage` é injetado (na produção, `IFrameHelper.sendMessage`) para
 * este arquivo ser testável sem iframe.
 *
 * NUNCA LANÇA: roda no boot do widget no site do cliente.
 */
export const attachOriginAttributes = async ({
  tracking = {},
  sendMessage,
}) => {
  try {
    const attributes = await originAttributes({
      measurementId: tracking.ga4_measurement_id,
    });
    if (!Object.keys(attributes).length) return {};

    const { contato, conversa } = split(attributes);
    if (Object.keys(contato).length)
      sendMessage('set-custom-attributes', { customAttributes: contato });
    if (Object.keys(conversa).length)
      sendMessage('set-conversation-custom-attributes', {
        customAttributes: conversa,
      });

    return attributes;
  } catch {
    return {};
  }
};
