import {
  parseWhatsAppReaction,
  collectWhatsAppReactions,
} from '../whatsappReactionHelper';

const buildMessage = (overrides = {}) => ({
  id: 1,
  content: null,
  contentAttributes: {},
  messageType: 0,
  attachments: [],
  ...overrides,
});

describe('parseWhatsAppReaction', () => {
  it('reconhece reação de grupo legada e devolve o autor sem o identificador técnico', () => {
    const reaction = parseWhatsAppReaction(
      buildMessage({
        id: 24969,
        content:
          '👥 *Rogerio José Da Silva (229480102662169@lid)*\n\n*Reagiu com* 👍',
        contentAttributes: { inReplyTo: 24968 },
      })
    );

    expect(reaction).toEqual({
      emoji: '👍',
      targetId: 24968,
      authorLabel: 'Rogerio José Da Silva',
      authorKey: 'Rogerio José Da Silva',
    });
    expect(JSON.stringify(reaction)).not.toContain('@lid');
  });

  it('prefere o autor estruturado ao nome extraído do texto', () => {
    const reaction = parseWhatsAppReaction(
      buildMessage({
        content: '*Reagiu com* 🚀',
        contentAttributes: {
          inReplyTo: 10,
          groupSender: {
            name: 'Angela Tozi',
            lid: '209424283527170@lid',
            phone: '',
          },
        },
      })
    );

    expect(reaction.authorLabel).toBe('Angela Tozi');
    // A identidade estável (LID) é chave de dedupe — nunca rótulo de tela.
    expect(reaction.authorKey).toBe('209424283527170@lid');
  });

  it('reconhece reação de conversa 1:1, sem autor identificado', () => {
    const reaction = parseWhatsAppReaction(
      buildMessage({ content: '*Reagiu com* 🚀', contentAttributes: {} })
    );

    expect(reaction).toMatchObject({
      emoji: '🚀',
      targetId: null,
      authorLabel: null,
    });
  });

  it('aceita emoji com modificador de tom de pele', () => {
    expect(
      parseWhatsAppReaction(buildMessage({ content: '*Reagiu com* 👎🏽' })).emoji
    ).toBe('👎🏽');
  });

  it('aceita o marcador em inglês', () => {
    expect(
      parseWhatsAppReaction(buildMessage({ content: '*Reacted with* 🔥' }))
        .emoji
    ).toBe('🔥');
  });

  it('aceita o formato snake_case do payload não camelizado', () => {
    expect(
      parseWhatsAppReaction(
        buildMessage({
          content: '*Reagiu com* 👍',
          contentAttributes: { in_reply_to: 77 },
        })
      ).targetId
    ).toBe(77);
  });

  it.each([
    ['mensagem normal', 'Bom dia, tudo certo?'],
    ['conteúdo vazio', ''],
    [
      'notificação que apenas CITA uma reação',
      '*📱 Enviado do WhatsApp*\n\n💬 **Mensagem (às 15:12):**\n"**Reagiu com** 👍"',
    ],
    ['marcador sem emoji', '*Reagiu com*'],
    ['texto depois do emoji', '*Reagiu com* 👍 e comentou'],
  ])('não trata "%s" como reação', (_label, content) => {
    expect(parseWhatsAppReaction(buildMessage({ content }))).toBeNull();
  });

  it('ignora mensagem com anexo mesmo que o texto case', () => {
    expect(
      parseWhatsAppReaction(
        buildMessage({
          content: '*Reagiu com* 👍',
          attachments: [{ id: 1, fileType: 'image' }],
        })
      )
    ).toBeNull();
  });
});

describe('collectWhatsAppReactions', () => {
  it('não faz nada quando não há reação no fio', () => {
    const messages = [
      buildMessage({ id: 1, content: 'oi' }),
      buildMessage({ id: 2, content: 'tudo bem?' }),
    ];

    const { hiddenMessageIds, reactionsByMessageId, standaloneReactions } =
      collectWhatsAppReactions(messages);

    expect(hiddenMessageIds.size).toBe(0);
    expect(reactionsByMessageId.size).toBe(0);
    expect(standaloneReactions.size).toBe(0);
  });

  it('tira a reação do fio e a ancora na mensagem reagida', () => {
    const messages = [
      buildMessage({ id: 10, content: 'Resolvido ✅' }),
      buildMessage({
        id: 11,
        content: '👥 *Angela Tozi (229480102662169@lid)*\n\n*Reagiu com* 👍',
        contentAttributes: { inReplyTo: 10 },
      }),
    ];

    const { hiddenMessageIds, reactionsByMessageId } =
      collectWhatsAppReactions(messages);

    expect(hiddenMessageIds.has(11)).toBe(true);
    expect(reactionsByMessageId.get(10)).toEqual([
      { emoji: '👍', count: 1, authors: ['Angela Tozi'] },
    ]);
  });

  it('agrega várias pessoas no mesmo chip e mantém a ordem de chegada', () => {
    const messages = [
      buildMessage({ id: 10, content: 'Aviso' }),
      buildMessage({
        id: 11,
        content: '👥 *Ana (229480102662169@lid)*\n\n*Reagiu com* 👍',
        contentAttributes: { inReplyTo: 10 },
      }),
      buildMessage({
        id: 12,
        content: '👥 *Bruno (115036504772668@lid)*\n\n*Reagiu com* 🎉',
        contentAttributes: { inReplyTo: 10 },
      }),
      buildMessage({
        id: 13,
        content: '👥 *Carla (254275552862323@lid)*\n\n*Reagiu com* 👍',
        contentAttributes: { inReplyTo: 10 },
      }),
    ];

    expect(
      collectWhatsAppReactions(messages).reactionsByMessageId.get(10)
    ).toEqual([
      { emoji: '👍', count: 2, authors: ['Ana', 'Carla'] },
      { emoji: '🎉', count: 1, authors: ['Bruno'] },
    ]);
  });

  it('conta só a última reação de cada pessoa (troca de emoji não infla)', () => {
    const messages = [
      buildMessage({ id: 10, content: 'Aviso' }),
      buildMessage({
        id: 11,
        content: '*Reagiu com* 👍',
        contentAttributes: {
          inReplyTo: 10,
          groupSender: { name: 'Ana', lid: '229480102662169@lid' },
        },
      }),
      buildMessage({
        id: 12,
        content: '*Reagiu com* 😢',
        contentAttributes: {
          inReplyTo: 10,
          groupSender: { name: 'Ana', lid: '229480102662169@lid' },
        },
      }),
    ];

    expect(
      collectWhatsAppReactions(messages).reactionsByMessageId.get(10)
    ).toEqual([{ emoji: '😢', count: 1, authors: ['Ana'] }]);
  });

  it('mantém visível, como chip solto, a reação sem alvo carregado', () => {
    const messages = [
      buildMessage({ id: 10, content: 'Mensagem' }),
      buildMessage({
        id: 11,
        content: '👥 *Ana (229480102662169@lid)*\n\n*Reagiu com* 👍',
        // 9999 ficou numa página anterior do histórico
        contentAttributes: { inReplyTo: 9999 },
      }),
      buildMessage({
        id: 12,
        content: '*Reagiu com* 🚀',
        contentAttributes: {},
      }),
    ];

    const { hiddenMessageIds, standaloneReactions } =
      collectWhatsAppReactions(messages);

    expect(hiddenMessageIds.size).toBe(0);
    expect(standaloneReactions.get(11)).toEqual([
      { emoji: '👍', count: 1, authors: ['Ana'] },
    ]);
    expect(standaloneReactions.get(12)).toEqual([
      { emoji: '🚀', count: 1, authors: [] },
    ]);
  });

  it('não ancora uma reação em outra reação', () => {
    const messages = [
      buildMessage({
        id: 11,
        content: '*Reagiu com* 👍',
        contentAttributes: { inReplyTo: 10 },
      }),
      buildMessage({
        id: 12,
        content: '*Reagiu com* 🎉',
        contentAttributes: { inReplyTo: 11 },
      }),
    ];

    const { hiddenMessageIds, standaloneReactions } =
      collectWhatsAppReactions(messages);

    expect(hiddenMessageIds.size).toBe(0);
    expect(standaloneReactions.size).toBe(2);
  });

  it('nunca vaza o identificador técnico em nenhum rótulo agregado', () => {
    const messages = [
      buildMessage({ id: 10, content: 'Aviso' }),
      buildMessage({
        id: 11,
        content:
          '👥 *‎Rogerio José Da Silva (229480102662169@lid)*\n\n*Reagiu com* 👎🏽',
        contentAttributes: { inReplyTo: 10 },
      }),
    ];

    const chips =
      collectWhatsAppReactions(messages).reactionsByMessageId.get(10);

    expect(JSON.stringify(chips)).not.toContain('@lid');
    expect(chips[0].authors[0]).toBe('Rogerio José Da Silva');
  });
});
