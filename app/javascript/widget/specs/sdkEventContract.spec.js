/**
 * A GUARDA DE RENOMEAÇÃO do bloco 5.04.
 *
 * O aceite do bloco diz: *"renomear um evento quebra o CI"*. O motivo é
 * concreto — nome de evento de `window` é contrato público. O site do cliente
 * escreveu `window.addEventListener('chatwoot:conversation-created', …)` no GTM
 * dele; renomear a constante no nosso lado não quebra build nenhum, não acende
 * console nenhum, e o GTM do cliente simplesmente **para de disparar**. O
 * primeiro sinal seria a queda de conversão num relatório de mídia, semanas
 * depois.
 *
 * ── POR QUE ISTO NÃO É TAUTOLÓGICO ───────────────────────────────────────────
 *
 * O teste não repete os nomes que a implementação declara: ele os LÊ do
 * DOCUMENTO de contrato, `docs/tracking/contrato-de-eventos.md`, que é de outra
 * trilha (bloco 5.03) e é a fonte da verdade declarada no próprio documento
 * ("Quem for emitir, consumir ou entregar um evento lê daqui — não do código").
 *
 * São duas fontes independentes:
 *   · o documento, escrito por quem definiu o contrato;
 *   · `constants/sdkEvents.js`, de onde TODO emissor importa.
 *
 * Renomear em um lado só reprova, nomeando o evento. Renomear nos dois é uma
 * mudança de contrato consciente — que é exatamente o que se quer exigir.
 */
import { readFileSync } from 'node:fs';
import * as sdkEvents from 'widget/constants/sdkEvents';

const CONTRATO = 'docs/tracking/contrato-de-eventos.md';

/**
 * Extrai as linhas da tabela da §1 do contrato ("Dois vocabulários, uma
 * emissão"), que é onde vive o mapa 1:1 entre o evento de `window` e o evento
 * de tracking.
 *
 * A extração é por token de código (crase), não por posição de coluna: se a
 * tabela for reformatada o teste continua lendo os nomes, e se um NOME mudar
 * ele reprova. É a granularidade certa — o contrato é o nome, não o layout.
 */
const linhasDoMapaDeVocabularios = () => {
  const texto = readFileSync(CONTRATO, 'utf8');
  const secao = texto.match(
    /##\s*1\.\s*Dois vocabulários, uma emissão([\s\S]*?)\n---/
  );
  if (!secao) {
    throw new Error(
      `não localizei a §1 (mapa de vocabulários) em ${CONTRATO} — o contrato mudou de forma`
    );
  }

  return secao[1]
    .split('\n')
    .filter(linha => linha.trim().startsWith('|') && linha.includes('`'))
    .map(linha => {
      const codigos = [...linha.matchAll(/`([^`]+)`/g)].map(m => m[1]);
      return {
        linha: linha.trim(),
        window: codigos.find(c => c.startsWith('chatwoot:')) || null,
        tracking: codigos.find(c => c.startsWith('chatspx_')) || null,
      };
    })
    .filter(item => item.window || item.tracking);
};

const nomesDeWindowExportados = () =>
  Object.entries(sdkEvents)
    .filter(([, valor]) => typeof valor === 'string')
    .filter(([, valor]) => valor.startsWith('chatwoot:'))
    .map(([, valor]) => valor);

describe('contrato dos eventos de window (bloco 5.04)', () => {
  const linhas = linhasDoMapaDeVocabularios();

  it('lê um mapa de vocabulários não vazio do documento de contrato', () => {
    // Se o documento for movido ou a §1 apagada, TODOS os testes abaixo
    // passariam por vacuidade — `[].forEach` não afirma nada. Esta é a asserção
    // que impede o verde vazio.
    expect(linhas.length).toBe(7);
  });

  it.each(linhas.filter(l => l.window))(
    'o evento $window do contrato existe em sdkEvents.js com a MESMA string',
    ({ window: nomeNoContrato }) => {
      expect(nomesDeWindowExportados()).toContain(nomeNoContrato);
    }
  );

  it.each(linhas.filter(l => l.window))(
    'o evento $window aponta para o evento de tracking que o contrato declara',
    ({ window: nomeNoContrato, tracking }) => {
      const entrada = sdkEvents.SDK_EVENT_CONTRACT[nomeNoContrato];
      expect(entrada).toBeDefined();
      // `null` quando a linha do contrato não nomeia nenhum `chatspx_*` —
      // `chatwoot:message-sent` (sinal interno), `chatwoot:campaign-shown` e
      // `chatwoot:csat-submitted` (§6 ponto 1: não implementar antes de
      // decidir). Acrescentar um `chatspx_csat_submitted` ao mapa sem a decisão
      // registrada no contrato reprova aqui.
      expect(entrada.tracking).toBe(tracking);
    }
  );

  /**
   * ── A DIVERGÊNCIA DECLARADA, congelada para não passar despercebida ────────
   *
   * O contrato de 5.03 registra o fato "contato passou a ter e-mail ou
   * telefone" como **server-side puro**: a coluna do evento de `window` traz
   * "— (server-side)".
   *
   * O aceite do bloco 5.04, porém, exige a ordem
   * `widget_opened → conversation_created → prechat_submitted → lead_identified`
   * **observável por `addEventListener` em navegador real** — o que só é
   * possível se o fato também chegar ao `window`.
   *
   * A resolução implementada (e ESCALADA ao coordenador, não combinada com a
   * outra trilha) é: o evento de TRACKING `chatspx_lead` continua nascendo só
   * no servidor, onde a transição é verificável; o evento de `window`
   * `chatwoot:lead-identified` é acrescentado, sem valor de PII, apenas com os
   * NOMES dos identificadores.
   *
   * Este teste congela as duas pontas. Se o contrato passar a nomear um evento
   * de `window` para essa linha, ele reprova e obriga a reconciliação.
   */
  it('a linha do lead segue sem evento de window no contrato — divergência aberta', () => {
    const linhaDoLead = linhas.find(l => l.tracking === 'chatspx_lead');
    expect(linhaDoLead).toBeDefined();
    expect(linhaDoLead.window).toBeNull();
    expect(sdkEvents.CHATWOOT_LEAD_IDENTIFIED).toBe('chatwoot:lead-identified');
    expect(
      sdkEvents.SDK_EVENT_CONTRACT['chatwoot:lead-identified'].tracking
    ).toBe('chatspx_lead');
  });

  /**
   * `chatwoot:reset-completed` (T-I4.5) não aparece no contrato de 5.03 porque
   * aquela tabela só lista fatos que têm contrapartida no vocabulário de
   * tracking, e este não tem: é sinal de ciclo de vida da API JS, não conversão.
   * A fonte dele é `24-plano-backend-dados.md` §17.1, e o nome fica congelado
   * aqui pelo mesmo motivo que os outros.
   */
  it('congela os nomes que o contrato de 5.03 não cobre', () => {
    expect(sdkEvents.CHATWOOT_RESET_COMPLETED).toBe('chatwoot:reset-completed');
    expect(sdkEvents.SDK_EVENT_CONTRACT['chatwoot:reset-completed']).toEqual({
      tracking: null,
      payload: [],
    });
  });

  it('todo evento do mapa respeita o formato de nome do vocabulário de window', () => {
    Object.keys(sdkEvents.SDK_EVENT_CONTRACT).forEach(nome => {
      expect(nome).toMatch(/^chatwoot:[a-z]+(-[a-z]+)*$/);
    });
  });

  it('todo nome de tracking respeita as três regras do contrato (§1)', () => {
    // As mesmas três que `TrackingEvent` verifica no servidor: prefixo
    // `chatspx_`, snake_case e ≤ 40 caracteres (limite do GA4). Verificadas
    // também aqui porque o mapa deste arquivo é o que 5.10 vai usar para montar
    // o `dataLayer` — um nome inválido só falharia no GA4 do cliente.
    Object.values(sdkEvents.SDK_EVENT_CONTRACT)
      .map(entrada => entrada.tracking)
      .filter(Boolean)
      .forEach(nome => {
        expect(nome).toMatch(/^chatspx_[a-z][a-z0-9_]*$/);
        expect(nome.length).toBeLessThanOrEqual(40);
      });
  });

  it('os sete nomes que já estavam em produção continuam intactos', () => {
    // Renomear qualquer um destes derruba integração de cliente EM PRODUÇÃO.
    // A lista é literal de propósito: aqui a duplicação é o mecanismo, não o
    // defeito — é o registro congelado do que já foi publicado.
    expect(sdkEvents.CHATWOOT_ERROR).toBe('chatwoot:error');
    expect(sdkEvents.CHATWOOT_ON_MESSAGE).toBe('chatwoot:on-message');
    expect(sdkEvents.CHATWOOT_ON_START_CONVERSATION).toBe(
      'chatwoot:on-start-conversation'
    );
    expect(sdkEvents.CHATWOOT_POSTBACK).toBe('chatwoot:postback');
    expect(sdkEvents.CHATWOOT_READY).toBe('chatwoot:ready');
    expect(sdkEvents.CHATWOOT_OPENED).toBe('chatwoot:opened');
    expect(sdkEvents.CHATWOOT_CLOSED).toBe('chatwoot:closed');
  });
});
