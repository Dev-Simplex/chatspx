/**
 * MECANISMO DE ACEITE DO BLOCO 4.09.
 *
 * Aceite (§2.2 / 22-plano-widget W3.9): "Simulando handoff, as 3 aparecem;
 * simulando volta à IA, as 3 também. NUNCA roxo como marcador."
 *
 * As três marcações são: **sistema** (marcador na conversa), **header** (quem
 * atende agora) e **bolha** (o rótulo colado na mensagem). Este arquivo prova a
 * regra pura; as três superfícies são provadas montadas em `specs/aiHandoff.spec.js`,
 * e a cor do marcador é medida em Chromium.
 *
 * CONTRATO COM O SERVIDOR, conferido no código e não suposto:
 * `app/views/api/v1/widget/messages/index.json.jbuilder` emite
 * `message.sender.push_event_data`, e o `type` de lá é:
 *   'user'              → agente humano   (app/models/user.rb:153)
 *   'agent_bot'         → bot             (app/models/agent_bot.rb:64)
 *   'captain_assistant' → Captain         (enterprise/.../captain/assistant.rb:116)
 * O servidor chama os dois últimos de `bot_response?` (message.rb:411).
 */
import {
  ATTENDANT,
  BOT_SENDER_TYPES,
  attendantOf,
  currentAttendant,
  handoffMarkFor,
  annotateHandoffs,
} from '../aiIdentity';

const msg = (extra = {}) => ({
  id: 1,
  message_type: 1, // OUTGOING
  content: 'oi',
  ...extra,
});
const daIA = extra => msg({ sender: { type: 'agent_bot' }, ...extra });
const doCaptain = extra =>
  msg({ sender: { type: 'captain_assistant' }, ...extra });
const doHumano = extra =>
  msg({ sender: { type: 'user', name: 'Marina' }, ...extra });
const doVisitante = extra => msg({ message_type: 0, sender: null, ...extra });

describe('4.09 — identidade de IA', () => {
  describe('contrato: os tipos de remetente que o servidor manda', () => {
    it('os dois tipos de bot são os mesmos que o servidor chama de bot_response', () => {
      expect(BOT_SENDER_TYPES).toEqual(['agent_bot', 'captain_assistant']);
    });
  });

  describe('attendantOf — quem falou nesta mensagem', () => {
    it('agent_bot é IA', () => {
      expect(attendantOf(daIA())).toBe(ATTENDANT.AI);
    });

    it('captain_assistant também é IA', () => {
      expect(attendantOf(doCaptain())).toBe(ATTENDANT.AI);
    });

    it('user é humano', () => {
      expect(attendantOf(doHumano())).toBe(ATTENDANT.HUMAN);
    });

    it('mensagem do VISITANTE não tem atendente', () => {
      expect(attendantOf(doVisitante())).toBe(ATTENDANT.UNKNOWN);
    });

    it('sem sender, ou com tipo desconhecido, NÃO inventa IA', () => {
      // Rotular de IA o que não se sabe é mentir para o visitante — e o rótulo
      // de IA existe justamente para ele saber com quem fala.
      expect(attendantOf(msg({ sender: null }))).toBe(ATTENDANT.UNKNOWN);
      expect(attendantOf(msg({ sender: { type: 'marciano' } }))).toBe(
        ATTENDANT.UNKNOWN
      );
      expect(attendantOf(undefined)).toBe(ATTENDANT.UNKNOWN);
    });

    it('mensagem de atividade não é atendente', () => {
      expect(attendantOf(msg({ message_type: 2 }))).toBe(ATTENDANT.UNKNOWN);
    });
  });

  describe('currentAttendant — quem atende AGORA (o rótulo do header)', () => {
    it('a última fala de atendente decide, não a última mensagem', () => {
      // O visitante responder depois do humano não devolve a conversa à IA.
      expect(currentAttendant([daIA(), doHumano(), doVisitante()])).toBe(
        ATTENDANT.HUMAN
      );
    });

    it('conversa só com IA é IA', () => {
      expect(currentAttendant([daIA(), doVisitante(), daIA()])).toBe(
        ATTENDANT.AI
      );
    });

    it('conversa sem atendente nenhum é desconhecida', () => {
      expect(currentAttendant([doVisitante()])).toBe(ATTENDANT.UNKNOWN);
      expect(currentAttendant([])).toBe(ATTENDANT.UNKNOWN);
    });

    it('mensagem antiga carregada DEPOIS não confunde quem atende', () => {
      // O store indexa por `message.id`, e `Object.values` sobre chave inteira
      // sai em ordem NUMERICA, não de inserção. Rolar para trás insere ids
      // menores depois; sem essa propriedade, o header passaria a dizer que
      // quem atende é quem falou primeiro.
      const store = {};
      [
        { id: 3, m: doHumano },
        { id: 1, m: daIA },
        { id: 2, m: doVisitante },
      ].forEach(({ id, m }) => {
        store[id] = { ...m(), id };
      });

      expect(Object.values(store).map(m => m.id)).toEqual([1, 2, 3]);
      expect(currentAttendant(Object.values(store))).toBe(ATTENDANT.HUMAN);
    });

    it('volta para a IA depois do humano', () => {
      expect(currentAttendant([daIA(), doHumano(), daIA()])).toBe(ATTENDANT.AI);
    });
  });

  describe('handoffMarkFor — a marcação de SISTEMA', () => {
    it('IA → humano produz a marcação de entrada da equipe', () => {
      expect(handoffMarkFor(ATTENDANT.AI, ATTENDANT.HUMAN)).toEqual({
        kind: 'to_human',
        i18nKey: 'AI_IDENTITY.HANDOFF_TO_HUMAN',
      });
    });

    it('humano → IA produz a marcação de volta ao assistente', () => {
      expect(handoffMarkFor(ATTENDANT.HUMAN, ATTENDANT.AI)).toEqual({
        kind: 'to_ai',
        i18nKey: 'AI_IDENTITY.HANDOFF_TO_AI',
      });
    });

    it('sem troca, não há marcação', () => {
      expect(handoffMarkFor(ATTENDANT.AI, ATTENDANT.AI)).toBeNull();
      expect(handoffMarkFor(ATTENDANT.HUMAN, ATTENDANT.HUMAN)).toBeNull();
    });

    it('o PRIMEIRO atendente não é handoff — ninguém foi transferido', () => {
      expect(handoffMarkFor(ATTENDANT.UNKNOWN, ATTENDANT.AI)).toBeNull();
      expect(handoffMarkFor(ATTENDANT.UNKNOWN, ATTENDANT.HUMAN)).toBeNull();
    });

    it('ir para desconhecido não marca nada', () => {
      expect(handoffMarkFor(ATTENDANT.AI, ATTENDANT.UNKNOWN)).toBeNull();
    });
  });

  describe('annotateHandoffs — onde cada marcação entra na conversa', () => {
    it('a conversa sem troca não ganha marcação nenhuma', () => {
      const anotadas = annotateHandoffs([daIA({ id: 1 }), daIA({ id: 2 })]);
      expect(anotadas.filter(m => m.handoffMark)).toHaveLength(0);
    });

    it('handoff para humano marca a mensagem em que ele fala', () => {
      const anotadas = annotateHandoffs([
        daIA({ id: 1 }),
        doVisitante({ id: 2 }),
        doHumano({ id: 3 }),
      ]);
      expect(anotadas.find(m => m.id === 3).handoffMark).toEqual({
        kind: 'to_human',
        i18nKey: 'AI_IDENTITY.HANDOFF_TO_HUMAN',
      });
      expect(anotadas.find(m => m.id === 1).handoffMark).toBeNull();
    });

    it('a VOLTA para a IA marca também — é metade do aceite', () => {
      const anotadas = annotateHandoffs([
        daIA({ id: 1 }),
        doHumano({ id: 2 }),
        daIA({ id: 3 }),
      ]);
      expect(anotadas.find(m => m.id === 2).handoffMark.kind).toBe('to_human');
      expect(anotadas.find(m => m.id === 3).handoffMark.kind).toBe('to_ai');
    });

    it('mensagem do visitante entre as duas não conta como troca', () => {
      const anotadas = annotateHandoffs([
        doHumano({ id: 1 }),
        doVisitante({ id: 2 }),
        doHumano({ id: 3 }),
      ]);
      expect(anotadas.filter(m => m.handoffMark)).toHaveLength(0);
    });

    it('cada mensagem carrega o próprio atendente — é o rótulo da BOLHA', () => {
      const anotadas = annotateHandoffs([daIA({ id: 1 }), doHumano({ id: 2 })]);
      expect(anotadas.map(m => m.attendant)).toEqual([
        ATTENDANT.AI,
        ATTENDANT.HUMAN,
      ]);
    });

    it('não muta o array nem os objetos originais', () => {
      const original = [daIA({ id: 1 })];
      const copia = JSON.parse(JSON.stringify(original));
      annotateHandoffs(original);
      expect(original).toEqual(copia);
    });

    it('lista vazia devolve lista vazia', () => {
      expect(annotateHandoffs([])).toEqual([]);
      expect(annotateHandoffs()).toEqual([]);
    });
  });
});
