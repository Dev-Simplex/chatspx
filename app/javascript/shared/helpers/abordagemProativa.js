/**
 * QUEM MANDA NA MENSAGEM PROATIVA — bloco 4.22.
 *
 * Hoje o widget tem DOIS caminhos para falar com o visitante sem ele pedir:
 *
 *   1. a CAMPANHA legada, que roda dentro do iframe, tem `trigger_rules` e
 *      cacheia por uma hora (`widget/store/modules/campaign.js`) [M22];
 *   2. a ABORDAGEM nova (4.06/4.19/4.20), que roda no host, ao lado do lançador.
 *
 * Os dois disputam o mesmo canto da tela e o mesmo momento. Sem regra declarada, o
 * comportamento passa a ser "o que carregar primeiro ganha" — que é o pior tipo de
 * contrato: ninguém o escreveu e todo mundo depende dele.
 *
 * ─── POR QUE ESTE ARQUIVO É COMPARTILHADO, E NÃO DUAS CÓPIAS ─────────────────────
 * A condição que MONTA a abordagem (host, `IFrameHelper.montarTeaserSeConfigurado`)
 * e a condição que SUPRIME a campanha (iframe, store de campanha) têm de ser a
 * MESMA. Duas cópias da mesma regra divergem no primeiro ajuste, e a divergência
 * aqui não é cosmética: se a supressão for mais larga que a montagem, a conta perde
 * a mensagem proativa que tinha e ninguém aparece no lugar; se for mais estreita, o
 * visitante leva as duas. Por isso os dois lados importam daqui.
 *
 * ─── A REGRA, CHAVE POR CHAVE ────────────────────────────────────────────────────
 * A decisão é de CONTA, e lê uma chave só: `widgetTriggers.enabled`.
 *
 *   ausente / false  →  não há motor novo. A campanha legada roda exatamente como
 *                       hoje. É o estado de TODA a frota, e é o aceite de não
 *                       regressão: conta que só tem campanha legada não muda de
 *                       comportamento.
 *   true             →  o motor novo assume a mensagem proativa da conta. A campanha
 *                       legada continua listada, editável e válida — ela só não
 *                       DISPARA sozinha.
 *
 * ─── E O ESTADO DO VISITANTE? (a pergunta que o coordenador fez) ─────────────────
 * Dispensa do teaser (`cw_teaser_dismissed`) e degradação por familiaridade
 * (`cw_approach`, 4.19) **NÃO** devolvem a vez à campanha legada. É decisão, não
 * esquecimento:
 *
 *   · os dois estados significam "o produto decidiu poupar ESTE visitante";
 *   · se a campanha legada disparasse ali, o visitante que dispensou o convite
 *     receberia outro convite por outro caminho — e quem caiu da escada de
 *     familiaridade voltaria ao topo por uma porta lateral. A degradação do 4.19
 *     viraria enfeite.
 *
 * Consequência aceita: um visitante que dispensou o teaser não vê mensagem proativa
 * nenhuma naquela sessão. É o objetivo, não o efeito colateral.
 *
 * ─── O QUE ESTA REGRA NÃO FAZ ────────────────────────────────────────────────────
 * Não desliga, não apaga e não esconde campanha nenhuma. A campanha vinculada
 * continua sendo a MENSAGEM do convite (4.05 — "campanha é mensagem, gatilho é
 * momento"), e é por isso que a supressão é do DISPARO automático e não do registro:
 * apagar a campanha apagaria o texto que o cliente escreveu na tela do teaser.
 */

/**
 * O motor novo está no ar para esta conta?
 *
 * `enabled` ausente é silêncio, nunca `true` — o mesmo contrato que o 4.04 fixou
 * para o SDK: ausência de configuração não pode ligar comportamento novo na frota.
 */
export const abordagemNovaNoAr = canal =>
  canal?.widgetTriggers?.enabled === true;

/** O espelho: enquanto o motor novo estiver no ar, a campanha legada não dispara. */
export const campanhaLegadaSuprimida = canal => abordagemNovaNoAr(canal);
