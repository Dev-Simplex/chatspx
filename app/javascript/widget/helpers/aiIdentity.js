/**
 * BLOCO 4.09 — quem está atendendo, e quando isso muda.
 *
 * O rótulo de IA existe para o visitante saber com quem fala. Por isso este
 * arquivo é conservador de um jeito específico: **na dúvida, não diz que é IA**.
 * Rotular de assistente o que pode ser gente — ou o contrário — é pior do que
 * não rotular, porque o rótulo passa a ser ruído em vez de informação.
 *
 * CONTRATO COM O SERVIDOR, lido no código:
 * `api/v1/widget/messages/index.json.jbuilder` emite
 * `message.sender.push_event_data`, cujo `type` é:
 *
 *   | type                | origem                                   | atendente |
 *   |---------------------|------------------------------------------|-----------|
 *   | `user`              | `app/models/user.rb:153`                 | humano    |
 *   | `agent_bot`         | `app/models/agent_bot.rb:64`             | IA        |
 *   | `captain_assistant` | `enterprise/.../captain/assistant.rb:116`| IA        |
 *
 * Os dois últimos são exatamente o que o servidor chama de `bot_response?`
 * (`app/models/message.rb:411`). Se o backend acrescentar um terceiro tipo de
 * bot, ele entra NESTA lista — e enquanto não entrar, cai em `unknown`, que não
 * mente.
 */
import { MESSAGE_TYPE } from 'shared/constants/messages';

export const ATTENDANT = {
  AI: 'ai',
  HUMAN: 'human',
  UNKNOWN: 'unknown',
};

/** Espelha `bot_response?` do servidor. */
export const BOT_SENDER_TYPES = ['agent_bot', 'captain_assistant'];

const HUMAN_SENDER_TYPES = ['user'];

/**
 * Quem falou nesta mensagem.
 *
 * Só mensagem de SAÍDA tem atendente: a do visitante é dele, e a de atividade
 * não é de ninguém.
 */
export const attendantOf = message => {
  if (!message) return ATTENDANT.UNKNOWN;
  if (message.message_type !== MESSAGE_TYPE.OUTGOING) return ATTENDANT.UNKNOWN;

  const type = message.sender?.type;
  if (BOT_SENDER_TYPES.includes(type)) return ATTENDANT.AI;
  if (HUMAN_SENDER_TYPES.includes(type)) return ATTENDANT.HUMAN;
  return ATTENDANT.UNKNOWN;
};

/**
 * Quem atende AGORA — o rótulo do cabeçalho.
 *
 * É a ÚLTIMA fala de atendente, não a última mensagem: o visitante responder
 * depois do humano não devolve a conversa para a IA.
 */
export const currentAttendant = (messages = []) => {
  const atendentes = (messages || [])
    .map(attendantOf)
    .filter(quem => quem !== ATTENDANT.UNKNOWN);

  return atendentes.length
    ? atendentes[atendentes.length - 1]
    : ATTENDANT.UNKNOWN;
};

/**
 * A marcação de SISTEMA de uma troca de atendente.
 *
 * O PRIMEIRO atendente da conversa não gera marcação: ninguém foi transferido —
 * a conversa começou ali. Marcar isso encheria toda conversa de um aviso que não
 * informa nada.
 */
export const handoffMarkFor = (anterior, atual) => {
  if (anterior === ATTENDANT.UNKNOWN) return null;
  if (atual === ATTENDANT.UNKNOWN) return null;
  if (anterior === atual) return null;

  return atual === ATTENDANT.HUMAN
    ? { kind: 'to_human', i18nKey: 'AI_IDENTITY.HANDOFF_TO_HUMAN' }
    : { kind: 'to_ai', i18nKey: 'AI_IDENTITY.HANDOFF_TO_AI' };
};

/**
 * Anota cada mensagem com o próprio atendente (o rótulo da BOLHA) e com a
 * marcação de troca, quando houver (a marcação de SISTEMA).
 *
 * Devolve cópias: mutar a mensagem do store faria o rótulo virar estado
 * persistido, e ele é derivado — recalculá-lo tem de ser sempre seguro.
 */
export const annotateHandoffs = (messages = []) => {
  let anterior = ATTENDANT.UNKNOWN;

  return (messages || []).map(message => {
    const attendant = attendantOf(message);
    if (attendant === ATTENDANT.UNKNOWN) {
      return { ...message, attendant, handoffMark: null };
    }

    const handoffMark = handoffMarkFor(anterior, attendant);
    anterior = attendant;
    return { ...message, attendant, handoffMark };
  });
};
