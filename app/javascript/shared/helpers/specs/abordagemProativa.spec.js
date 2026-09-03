import { readFileSync } from 'node:fs';
import {
  abordagemNovaNoAr,
  campanhaLegadaSuprimida,
} from 'shared/helpers/abordagemProativa';

/**
 * 4.22 — a REGRA DE PRECEDÊNCIA, chave por chave.
 *
 * Este arquivo existe para que a regra seja legível sem abrir o store nem o SDK:
 * quem quiser saber "quem aparece quando os dois estão ativos" lê os nomes dos
 * exemplos daqui.
 */
describe('4.22 — quem manda na mensagem proativa', () => {
  describe('a conta que nunca configurou gatilho', () => {
    it('mantém a campanha legada disparando — é o estado de toda a frota', () => {
      expect(campanhaLegadaSuprimida({ widgetTriggers: {} })).toBe(false);
    });

    it('trata `enabled` ausente como silêncio, nunca como ligado', () => {
      expect(abordagemNovaNoAr({ widgetTriggers: { triggers: [] } })).toBe(
        false
      );
    });

    it('sobrevive a um canal ausente sem derrubar o widget', () => {
      expect(campanhaLegadaSuprimida(undefined)).toBe(false);
      expect(campanhaLegadaSuprimida(null)).toBe(false);
      expect(campanhaLegadaSuprimida({})).toBe(false);
    });

    it('não aceita `enabled` verdadeiro-ish — só o booleano true liga', () => {
      expect(abordagemNovaNoAr({ widgetTriggers: { enabled: 'true' } })).toBe(
        false
      );
      expect(abordagemNovaNoAr({ widgetTriggers: { enabled: 1 } })).toBe(false);
    });
  });

  describe('a conta com gatilho ativo', () => {
    const comGatilho = { widgetTriggers: { enabled: true } };

    it('entrega a mensagem proativa ao motor novo', () => {
      expect(abordagemNovaNoAr(comGatilho)).toBe(true);
    });

    it('suprime o disparo automático da campanha legada', () => {
      expect(campanhaLegadaSuprimida(comGatilho)).toBe(true);
    });

    it('suprime também quando o gatilho está ativo mas desligado depois', () => {
      expect(
        campanhaLegadaSuprimida({ widgetTriggers: { enabled: false } })
      ).toBe(false);
    });
  });

  // A pergunta que o coordenador fez, respondida por teste e não por comentário.
  describe('o visitante que já dispensou, ou que a degradação decidiu poupar', () => {
    it('não devolve a vez à campanha legada — a regra é de CONTA, não de visitante', () => {
      // O predicado não recebe estado de visitante, e isso é a resposta: nem a
      // dispensa do teaser nem a escada do 4.19 entram nesta decisão. Se
      // entrassem, quem dissesse "não" ao convite receberia outro convite por
      // outro caminho, e a degradação viraria enfeite.
      expect(campanhaLegadaSuprimida.length).toBe(1);
      expect(
        campanhaLegadaSuprimida({ widgetTriggers: { enabled: true } })
      ).toBe(true);
    });
  });

  // A GUARDA CONTRA A REINCIDÊNCIA. O defeito original deste bloco não era uma
  // regra errada — era a MESMA regra escrita em dois lugares, livre para divergir.
  // Este exemplo falha se alguém voltar a escrever a condição na mão em qualquer
  // um dos dois lados, que é como a divergência voltaria.
  describe('os dois lados leem a MESMA fonte', () => {
    const ler = caminho =>
      readFileSync(new URL(caminho, import.meta.url), 'utf8');

    it('o host (SDK) importa o predicado em vez de comparar `enabled` na mão', () => {
      const fonte = ler('../../../sdk/IFrameHelper.js');

      expect(fonte).toContain("from 'shared/helpers/abordagemProativa'");
      expect(fonte).not.toMatch(/gatilhos\.enabled\s*!==\s*true/);
    });

    it('o widget importa o predicado em vez de comparar `enabled` na mão', () => {
      const fonte = ler('../../../widget/store/modules/campaign.js');

      expect(fonte).toContain("from 'shared/helpers/abordagemProativa'");
      expect(fonte).not.toMatch(/widgetTriggers\?\.enabled/);
    });
  });

  describe('o espelho entre os dois lados do iframe', () => {
    it('suprimir a campanha e montar a abordagem são a MESMA condição', () => {
      const casos = [
        undefined,
        {},
        { widgetTriggers: {} },
        { widgetTriggers: { enabled: false } },
        { widgetTriggers: { enabled: true } },
      ];

      casos.forEach(canal => {
        expect(campanhaLegadaSuprimida(canal)).toBe(abordagemNovaNoAr(canal));
      });
    });
  });
});
