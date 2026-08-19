import {
  PURPOSES,
  GRANTED,
  DENIED,
  consentState,
  isGranted,
  hasAnyConsent,
  defaultsWerePublished,
  publishDefaults,
  updateConsent,
  withConsent,
  resetConsentForTests,
  applyInboxConsentMode,
  consentModeIsActive,
  isAllowed,
  withConsentForInbox,
} from '../consent';

// Bloco 5.09 — consentimento (Consent Mode v2 e LGPD).
//
// O aceite e uma ASSERCAO NEGATIVA: com a CMP negando, ZERO disparos client-side. Contar os
// disparos permitidos provaria que o caminho feliz funciona; so contar os proibidos prova que o
// gate existe. E a ORDEM faz parte do aceite: default antes de tudo, update depois.
describe('5.09 — consentimento', () => {
  let empurrados;

  beforeEach(() => {
    empurrados = [];
    resetConsentForTests(payload => empurrados.push(payload));
  });

  describe('o padrao, antes de qualquer decisao', () => {
    it('todos os quatro propositos nascem NEGADOS', () => {
      expect(consentState()).toEqual({
        ad_storage: DENIED,
        ad_user_data: DENIED,
        ad_personalization: DENIED,
        analytics_storage: DENIED,
      });
    });

    it('nenhum proposito esta concedido e hasAnyConsent e falso', () => {
      expect(PURPOSES.some(isGranted)).toBe(false);
      expect(hasAnyConsent()).toBe(false);
    });
  });

  describe('ACEITE — com a CMP negando, ZERO disparos client-side', () => {
    it('nenhum dos quatro propositos executa, e o contador fica em zero', () => {
      publishDefaults();
      updateConsent({
        ad_storage: DENIED,
        ad_user_data: DENIED,
        ad_personalization: DENIED,
        analytics_storage: DENIED,
      });

      let disparos = 0;
      PURPOSES.forEach(purpose => {
        withConsent(purpose, () => {
          disparos += 1;
        });
      });

      expect(disparos).toBe(0);
    });

    it('o gate devolve undefined e NAO executa a funcao, mesmo chamado dez vezes', () => {
      let disparos = 0;
      const resultados = Array.from({ length: 10 }, () =>
        withConsent('analytics_storage', () => {
          disparos += 1;
          return 'disparou';
        })
      );

      expect(disparos).toBe(0);
      expect(resultados.every(r => r === undefined)).toBe(true);
    });

    it('consentimento parcial nao vaza para o proposito vizinho', () => {
      updateConsent({ analytics_storage: GRANTED });

      let anuncio = 0;
      let analise = 0;
      withConsent('ad_storage', () => {
        anuncio += 1;
      });
      withConsent('analytics_storage', () => {
        analise += 1;
      });

      expect(anuncio).toBe(0);
      expect(analise).toBe(1);
    });
  });

  describe('ACEITE — aceitando depois, o update chega e os SEGUINTES disparam', () => {
    it('o que foi negado antes nao e reproduzido; o que vem depois dispara', () => {
      let disparos = 0;
      const tentar = () =>
        withConsent('analytics_storage', () => {
          disparos += 1;
        });

      tentar();
      tentar();
      expect(disparos).toBe(0);

      updateConsent({ analytics_storage: GRANTED });

      tentar();
      tentar();
      expect(disparos).toBe(2);
    });

    it('o update chega ao dataLayer com o estado completo', () => {
      publishDefaults();
      updateConsent({ analytics_storage: GRANTED });

      const [verbo, acao, estado] = empurrados.at(-1);
      expect(verbo).toBe('consent');
      expect(acao).toBe('update');
      expect(estado.analytics_storage).toBe(GRANTED);
      expect(estado.ad_storage).toBe(DENIED);
    });

    it('negar depois de aceitar volta a bloquear', () => {
      updateConsent({ analytics_storage: GRANTED });
      updateConsent({ analytics_storage: DENIED });

      let disparos = 0;
      withConsent('analytics_storage', () => {
        disparos += 1;
      });

      expect(disparos).toBe(0);
    });
  });

  describe('A ORDEM DE EXECUCAO E O ACEITE, nao detalhe', () => {
    it('o default vai ANTES do update, sempre', () => {
      publishDefaults();
      updateConsent({ analytics_storage: GRANTED });

      expect(empurrados.map(p => p[1])).toEqual(['default', 'update']);
    });

    it('update sem default publicado publica o default ANTES, em vez de mandar update solto', () => {
      expect(defaultsWerePublished()).toBe(false);

      updateConsent({ analytics_storage: GRANTED });

      expect(empurrados.map(p => p[1])).toEqual(['default', 'update']);
      expect(empurrados[0][2].analytics_storage).toBe(DENIED);
    });

    it('publicar o default duas vezes nao empurra dois — o segundo apagaria um update ja recebido', () => {
      publishDefaults();
      updateConsent({ analytics_storage: GRANTED });
      publishDefaults();

      expect(empurrados.map(p => p[1])).toEqual(['default', 'update']);
      expect(consentState().analytics_storage).toBe(GRANTED);
    });

    it('o default respeita o que a CMP ja sabia, sem inventar concessao', () => {
      publishDefaults({ analytics_storage: GRANTED, ad_storage: DENIED });

      expect(consentState().analytics_storage).toBe(GRANTED);
      expect(consentState().ad_storage).toBe(DENIED);
      expect(consentState().ad_user_data).toBe(DENIED);
    });
  });

  // Bloco 5.01 forneceu `consent_mode` na config publica da inbox; aqui ele decide se o gate opera.
  describe('o modo da inbox decide se o Consent Mode opera', () => {
    it('disabled e o padrao, e mantem o comportamento de HOJE: dispara sem gate', () => {
      expect(consentModeIsActive()).toBe(false);

      let disparos = 0;
      withConsentForInbox('analytics_storage', () => {
        disparos += 1;
      });

      expect(disparos).toBe(1);
    });

    it('basic liga o gate: com a CMP negando, ZERO disparos', () => {
      applyInboxConsentMode('basic');

      let disparos = 0;
      PURPOSES.forEach(purpose => {
        withConsentForInbox(purpose, () => {
          disparos += 1;
        });
      });

      expect(disparos).toBe(0);
      expect(isAllowed('analytics_storage')).toBe(false);
    });

    it('basic e depois aceitar: os SEGUINTES disparam', () => {
      applyInboxConsentMode('basic');
      let disparos = 0;
      const tentar = () =>
        withConsentForInbox('analytics_storage', () => {
          disparos += 1;
        });

      tentar();
      expect(disparos).toBe(0);

      updateConsent({ analytics_storage: GRANTED });
      tentar();

      expect(disparos).toBe(1);
    });

    it('advanced publica o default na hora — a linha de base nao espera a CMP', () => {
      applyInboxConsentMode('advanced');

      expect(defaultsWerePublished()).toBe(true);
      expect(empurrados.map(p => p[1])).toEqual(['default']);
      expect(empurrados[0][2].analytics_storage).toBe(DENIED);
    });

    it('modo desconhecido cai em disabled, e nao em "liga tudo"', () => {
      expect(applyInboxConsentMode('inventado')).toBe('disabled');
      expect(consentModeIsActive()).toBe(false);
    });
  });

  describe('entrada torta nao vira concessao', () => {
    it.each([
      ['true', true],
      ['string qualquer', 'sim'],
      ['1', 1],
      ['null', null],
    ])('%s nao concede nada', (_rotulo, valor) => {
      updateConsent({ analytics_storage: valor });

      expect(isGranted('analytics_storage')).toBe(false);
    });

    it('proposito desconhecido e ignorado, e nao entra no estado', () => {
      updateConsent({ inventado: GRANTED });

      expect('inventado' in consentState()).toBe(false);
    });
  });
});
