/**
 * Bloco 2.18 — as duas funções que foram COPIADAS do dashboard para o widget
 * não podem divergir em silêncio.
 *
 * O corte de peso trocou dois imports de `dashboard/` por cópias locais, porque
 * o módulo de origem arrastava para o first-paint do widget coisas que a função
 * copiada não usa (a tabela de ~200 idiomas do filtro avançado; `date-fns/parse`
 * e a tabela de fusos). O ganho é real, mas cópia é dívida: se o original mudar,
 * o widget passa a responder diferente do dashboard e ninguém percebe.
 *
 * Estes exemplos comparam SAÍDA contra SAÍDA, não implementação contra
 * implementação — é o contrato que importa, e é ele que tem de continuar igual.
 */
import { getLanguageDirection as doWidget } from '../languageDirection';
import { getLanguageDirection as doDashboard } from 'dashboard/components/widgets/conversation/advancedFilterItems/languages';
import { getTime as horaDoWidget } from '../horaLegivel';
import { getTime as horaDoDashboard } from 'dashboard/routes/dashboard/settings/inbox/helpers/businessHour';
import idiomas from 'dashboard/components/widgets/conversation/advancedFilterItems/languages';

describe('paridade com o dashboard (bloco 2.18)', () => {
  describe('getLanguageDirection', () => {
    it('responde igual para TODOS os idiomas da tabela do dashboard', () => {
      const divergentes = idiomas
        .map(idioma => idioma.id)
        .filter(codigo => doWidget(codigo) !== doDashboard(codigo));
      expect(divergentes).toEqual([]);
    });

    it('responde igual para os códigos que o widget realmente recebe', () => {
      // Códigos com variação (`pt_BR`) e vazios chegam aqui pelo `$i18n.locale`.
      [
        'pt_BR',
        'pt',
        'en',
        'ar',
        'he',
        'fa',
        'ku',
        'ur',
        'as',
        '',
        undefined,
      ].forEach(codigo => {
        expect(doWidget(codigo)).toBe(doDashboard(codigo));
      });
    });
  });

  describe('getTime', () => {
    it('responde igual em todas as 1.440 combinações de hora e minuto', () => {
      const divergentes = [];
      for (let hora = 0; hora < 24; hora += 1) {
        for (let minuto = 0; minuto < 60; minuto += 1) {
          if (horaDoWidget(hora, minuto) !== horaDoDashboard(hora, minuto)) {
            divergentes.push(`${hora}:${minuto}`);
          }
        }
      }
      expect(divergentes).toEqual([]);
    });
  });
});
