import {
  AUTOR,
  autorFinal,
  tipoLinha,
  calcularAgrupamento,
  ehFormularioRespondido,
  temRespostaEmbutida,
  useMessageGrouping,
} from '../useMessageGrouping';

const doAgente = (extra = {}) => ({
  id: 1,
  message_type: 1,
  content: 'Olá',
  ...extra,
});
const doVisitante = (extra = {}) => ({
  id: 2,
  message_type: 0,
  content: 'Oi',
  ...extra,
});

describe('useMessageGrouping', () => {
  describe('quem fala em cada ponta da linha', () => {
    it('mensagem simples do agente abre e fecha com o agente', () => {
      const m = doAgente();

      expect(tipoLinha(m)).toBe(AUTOR.AGENTE);
      expect(autorFinal(m)).toBe(AUTOR.AGENTE);
    });

    it('mensagem do visitante é do visitante nas duas pontas', () => {
      const m = doVisitante();

      expect(tipoLinha(m)).toBe(AUTOR.VISITANTE);
      expect(autorFinal(m)).toBe(AUTOR.VISITANTE);
    });

    it('agente com resposta embutida FECHA com o visitante', () => {
      // É o antigo `.has-response`: a opção escolhida vira balão do visitante
      // dentro da mesma linha.
      const m = doAgente({
        content_type: 'input_select',
        content_attributes: { submitted_values: [{ title: 'Suporte' }] },
      });

      expect(tipoLinha(m)).toBe(AUTOR.AGENTE);
      expect(autorFinal(m)).toBe(AUTOR.VISITANTE);
    });

    it('formulário respondido: a LINHA continua sendo do agente', () => {
      // Ela abre desenhando os valores do visitante (a parte do agente tem
      // `v-if="!isASubmittedForm"`), mas para efeito de agrupamento o CSS
      // antigo a tratava como `.agent-message-wrap`. Chamar de "linha do
      // visitante" pareceria mais certo e mudaria o espaçamento dela.
      const m = doAgente({
        content_type: 'form',
        content_attributes: { submitted_values: [{ name: 'x', value: 'y' }] },
      });

      expect(tipoLinha(m)).toBe(AUTOR.AGENTE);
      expect(autorFinal(m)).toBe(AUTOR.VISITANTE);
    });

    it('resposta já materializada pelo backend não conta como embutida', () => {
      // Com `reply_message_id` a resposta chega pela lista como mensagem
      // própria; contar de novo duplicaria o balão.
      const m = doAgente({
        content_type: 'input_select',
        content_attributes: {
          submitted_values: [{ title: 'Suporte' }],
          reply_message_id: 99,
        },
      });

      expect(temRespostaEmbutida(m)).toBe(false);
      expect(autorFinal(m)).toBe(AUTOR.AGENTE);
    });

    it('form e input_csat não contam como resposta embutida', () => {
      const csat = doAgente({
        content_type: 'input_csat',
        content_attributes: { submitted_values: { rating: 5 } },
      });

      expect(temRespostaEmbutida(csat)).toBe(false);
    });

    it('e-mail capturado conta como resposta embutida', () => {
      const m = doAgente({
        content_type: 'input_email',
        content_attributes: { submitted_email: 'a@b.c' },
      });

      expect(autorFinal(m)).toBe(AUTOR.VISITANTE);
    });

    it('formulário sem resposta ainda é do agente', () => {
      const m = doAgente({ content_type: 'form', content_attributes: {} });

      expect(ehFormularioRespondido(m)).toBe(false);
      expect(tipoLinha(m)).toBe(AUTOR.AGENTE);
    });
  });

  // As seis regras que existiam como seletor de irmão adjacente em
  // `_conversation.scss`. Cada `it` abaixo é uma delas, traduzida.
  describe('as seis regras do CSS antigo, uma a uma', () => {
    const agrupar = messages =>
      calcularAgrupamento(messages.map((m, i) => ({ ...m, id: i + 1 })));

    it('agente depois de agente CONTINUA o grupo', () => {
      const r = agrupar([doAgente(), doAgente()]);

      expect(r[2].continuaGrupo).toBe(true);
    });

    it('visitante depois de agente ABRE bloco novo', () => {
      const r = agrupar([doAgente(), doVisitante()]);

      expect(r[2].continuaGrupo).toBe(false);
    });

    it('visitante depois de agente COM resposta embutida CONTINUA', () => {
      const comResposta = doAgente({
        content_type: 'input_select',
        content_attributes: { submitted_values: [{ title: 'A' }] },
      });
      const r = agrupar([comResposta, doVisitante()]);

      expect(r[2].continuaGrupo).toBe(true);
    });

    it('agente depois de agente COM resposta embutida ABRE bloco novo', () => {
      const comResposta = doAgente({
        content_type: 'input_select',
        content_attributes: { submitted_values: [{ title: 'A' }] },
      });
      const r = agrupar([comResposta, doAgente()]);

      expect(r[2].continuaGrupo).toBe(false);
    });

    it('visitante depois de visitante CONTINUA', () => {
      const r = agrupar([doVisitante(), doVisitante()]);

      expect(r[2].continuaGrupo).toBe(true);
    });

    it('agente depois de visitante ABRE bloco novo', () => {
      const r = agrupar([doVisitante(), doAgente()]);

      expect(r[2].continuaGrupo).toBe(false);
    });
  });

  describe('bordas', () => {
    it('a primeira mensagem nunca continua grupo', () => {
      const r = calcularAgrupamento([doAgente()]);

      expect(r[1].continuaGrupo).toBe(false);
    });

    it('lista vazia não quebra', () => {
      expect(calcularAgrupamento([])).toEqual({});
      expect(calcularAgrupamento()).toEqual({});
    });

    it('id desconhecido devolve valor neutro em vez de undefined', () => {
      const { agrupamentoDe } = useMessageGrouping([doAgente()]);

      expect(agrupamentoDe(404)).toEqual({
        tipoLinha: AUTOR.AGENTE,
        autorFinal: AUTOR.AGENTE,
        continuaGrupo: false,
      });
    });

    it('recalcula quando a lista muda', () => {
      const lista = [doAgente({ id: 1 })];
      const { agrupamento } = useMessageGrouping(() => lista);

      expect(agrupamento.value[1].continuaGrupo).toBe(false);
    });
  });
});
