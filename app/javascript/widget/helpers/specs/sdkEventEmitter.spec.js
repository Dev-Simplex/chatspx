import {
  __resetSdkEventsForTests,
  emitLeadIdentified,
  emitSdkEvent,
  emitSdkEventOnce,
  filterByContract,
  hasEmitted,
  leadIdentifiers,
} from '../sdkEventEmitter';
import { IFrameHelper } from 'widget/helpers/utils';
import { reportWidgetError } from 'widget/helpers/telemetry';
import {
  CHATWOOT_CONVERSATION_CREATED,
  CHATWOOT_LEAD_IDENTIFIED,
  CHATWOOT_PRECHAT_SUBMITTED,
} from 'widget/constants/sdkEvents';

vi.mock('widget/helpers/utils', () => ({
  IFrameHelper: { sendMessage: vi.fn() },
}));
vi.mock('widget/helpers/telemetry', () => ({
  reportWidgetError: vi.fn(),
}));

describe('sdkEventEmitter (bloco 5.04)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    __resetSdkEventsForTests();
  });

  describe('#emitSdkEvent', () => {
    it('monta o envelope que o SDK repassa ao window do site', () => {
      expect(
        emitSdkEvent(CHATWOOT_CONVERSATION_CREATED, {
          conversation_id: 42,
          inbox_id: 7,
        })
      ).toBe(true);

      expect(IFrameHelper.sendMessage).toHaveBeenCalledWith({
        event: 'onEvent',
        eventIdentifier: 'chatwoot:conversation-created',
        data: { conversation_id: 42, inbox_id: 7 },
        // Bloco 5.10 — o MESMO fato no vocabulário de tracking, resolvido aqui
        // porque é aqui que o mapa vive. O host não duplica o mapa: ele leva o
        // nome pronto ao `dataLayer` e às tags.
        tracking: 'chatspx_conversation_started',
      });
    });

    it('não lança quando o postMessage falha, e conta o erro', () => {
      const falha = new Error('frame morto');
      IFrameHelper.sendMessage.mockImplementationOnce(() => {
        throw falha;
      });

      expect(emitSdkEvent(CHATWOOT_CONVERSATION_CREATED, {})).toBe(false);
      expect(reportWidgetError).toHaveBeenCalledWith(falha, {
        origem: 'sdkEventEmitter',
      });
    });
  });

  describe('#filterByContract', () => {
    it('descarta chave que o contrato não declara — é a guarda de PII', () => {
      // O `window` do site é legível por qualquer script de terceiro. Um e-mail
      // que escape para o payload por descuido morre aqui.
      expect(
        filterByContract(CHATWOOT_PRECHAT_SUBMITTED, {
          fields: ['emailAddress'],
          email: 'visitante@exemplo.com.br',
        })
      ).toEqual({ fields: ['emailAddress'] });
    });

    it('conta o descarte, porque chave perdida em silêncio é defeito invisível', () => {
      filterByContract(CHATWOOT_PRECHAT_SUBMITTED, {
        fields: [],
        email: 'x@y.z',
        phone_number: '+5511999999999',
      });

      expect(reportWidgetError).toHaveBeenCalledTimes(1);
      expect(reportWidgetError.mock.calls[0][0].message).toBe(
        'payload fora do contrato em chatwoot:prechat-submitted: email, phone_number'
      );
    });

    it('omite a chave declarada que veio ausente, em vez de mandar undefined', () => {
      expect(
        filterByContract(CHATWOOT_CONVERSATION_CREATED, { conversation_id: 9 })
      ).toEqual({ conversation_id: 9 });
    });

    it('deixa passar intacto o payload dos sete eventos antigos', () => {
      // `chatwoot:on-message` já está em produção carregando a mensagem
      // inteira. Este bloco não pode estreitar o que ele nunca definiu.
      const payload = { content: 'oi', id: 3 };
      expect(filterByContract('chatwoot:on-message', payload)).toBe(payload);
    });
  });

  describe('#emitSdkEventOnce', () => {
    it('emite uma vez e ignora a segunda chamada', () => {
      expect(
        emitSdkEventOnce(CHATWOOT_CONVERSATION_CREATED, { conversation_id: 1 })
      ).toBe(true);
      expect(
        emitSdkEventOnce(CHATWOOT_CONVERSATION_CREATED, { conversation_id: 1 })
      ).toBe(false);

      expect(IFrameHelper.sendMessage).toHaveBeenCalledTimes(1);
      expect(hasEmitted(CHATWOOT_CONVERSATION_CREATED)).toBe(true);
    });

    it('separa por chave, para "uma vez por campanha" e não "uma vez por evento"', () => {
      emitSdkEventOnce('chatwoot:campaign-shown', { campaign_id: 1 }, 'c:1');
      emitSdkEventOnce('chatwoot:campaign-shown', { campaign_id: 2 }, 'c:2');
      emitSdkEventOnce('chatwoot:campaign-shown', { campaign_id: 1 }, 'c:1');

      expect(IFrameHelper.sendMessage).toHaveBeenCalledTimes(2);
      expect(
        IFrameHelper.sendMessage.mock.calls.map(([msg]) => msg.data.campaign_id)
      ).toEqual([1, 2]);
    });

    it('não gasta a marca quando o envio falhou — a próxima tentativa emite', () => {
      IFrameHelper.sendMessage.mockImplementationOnce(() => {
        throw new Error('frame morto');
      });

      expect(emitSdkEventOnce(CHATWOOT_CONVERSATION_CREATED, {})).toBe(false);
      expect(hasEmitted(CHATWOOT_CONVERSATION_CREATED)).toBe(false);
      expect(emitSdkEventOnce(CHATWOOT_CONVERSATION_CREATED, {})).toBe(true);
      expect(IFrameHelper.sendMessage).toHaveBeenCalledTimes(2);
    });
  });

  describe('#leadIdentifiers', () => {
    it('devolve só os identificadores que existem, pelo NOME', () => {
      expect(
        leadIdentifiers({ email: 'a@b.com', phone_number: '', name: 'Ana' })
      ).toEqual(['email']);
      expect(
        leadIdentifiers({ email: '  ', phone_number: '+5565999990000' })
      ).toEqual(['phone_number']);
      expect(leadIdentifiers({})).toEqual([]);
      expect(leadIdentifiers(undefined)).toEqual([]);
    });
  });

  describe('#emitLeadIdentified', () => {
    it('não emite quando o contato ainda não tem identificador nenhum', () => {
      expect(emitLeadIdentified({ contact: { name: 'Ana' } })).toBe(false);
      expect(IFrameHelper.sendMessage).not.toHaveBeenCalled();
    });

    it('emite os NOMES dos identificadores e nunca os valores', () => {
      expect(
        emitLeadIdentified({
          contact: { email: 'ana@exemplo.com.br', phone_number: '+556599' },
          conversationId: 12,
        })
      ).toBe(true);

      expect(IFrameHelper.sendMessage).toHaveBeenCalledWith({
        event: 'onEvent',
        eventIdentifier: CHATWOOT_LEAD_IDENTIFIED,
        data: {
          conversation_id: 12,
          identifiers: ['email', 'phone_number'],
        },
        tracking: 'chatspx_lead',
      });

      const [[mensagem]] = IFrameHelper.sendMessage.mock.calls;
      expect(JSON.stringify(mensagem)).not.toContain('ana@exemplo.com.br');
      expect(JSON.stringify(mensagem)).not.toContain('+556599');
    });

    it('é um fato só: a segunda transição não repete o evento', () => {
      emitLeadIdentified({ contact: { email: 'a@b.com' } });
      emitLeadIdentified({ contact: { phone_number: '+5565' } });

      expect(IFrameHelper.sendMessage).toHaveBeenCalledTimes(1);
    });
  });
});
