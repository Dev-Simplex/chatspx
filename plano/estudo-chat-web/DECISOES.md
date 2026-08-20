# Decisões em aberto — consolidado das três sínteses

**Data:** 12/08/2026 · Estudo encerrado, nada implementado.
Fontes: `10-gap-analysis.md` §7 (negócio, 10) · `frontend/16-spec-redesenho.md` §10 (front, 8) ·
`integracao/20-spec-integracao.md` §7 (integração, 6). **24 decisões, todas com recomendação.**

---

## Parte 0 — O que NÃO depende de decisão

Seis defeitos verificados por leitura de código ou medição em browser. Não são questão de
escopo: estão errados hoje, em produção, para todos os clientes.

| # | Defeito | Prova | Esforço |
|---|---|---|---|
| B1 | `widget_color` por inbox não chega ao header, botão de enviar, links nem foco | `ChatHeader.vue:28`, `ChatHeaderExpanded.vue:34`, `ChatSendButton.vue:27` usam `bg-n-brand` literal; `--widget-color` é escrita em `App.vue:121` e **não tem um único consumidor em CSS** | P |
| B2 | Contraste reprovando AA | Header verde com texto branco = **2,25:1** (mín. 4,5:1, e reprova até o mínimo de componente 3:1). Bolha do visitante 3,07:1; link do agente 2,27:1 | P |
| B3 | Webhook de conta **sem retry efetivo** | `WebhookJob` tem `retry_on ... attempts: 5`, mas `Webhooks::Trigger#execute` engole a exceção antes de subir. Só agent bot dá `raise` | P |
| B4 | `postMessage` sem validação de origem **nos dois lados** | `IFrameHelper.js:104-117` e `widget/helpers/utils.js:18-21` (via `App.vue:260-264`) | P |
| B5 | Enforcement de HMAC com duas portas abertas | `before_action :validate_hmac, only: [:set_user]` deixa `PATCH /widget/contact` livre; e o early return em `contacts_controller.rb:59` desliga a checagem quando vem `custom_attributes` sem `identifier` | P |
| B6 | Atributo sem definição prévia é gravado, alimenta a IA e **some do painel** | `CustomAttributes.vue:76-89` itera as **definições**, não os valores. Não dá para filtrar nem entra em relatório. Caso real: `enviar_fotos_imovel_tool.rb` grava dados que a IA vê e o corretor não | M |

**B6 é pré-requisito comercial.** Enquanto existir, qualquer melhoria de integração chega ao
cliente como "não funcionou".

---

## Parte 1 — As que travam outras decisões

Decidir primeiro; o resto depende.

| # | Pergunta | Recomendação |
|---|---|---|
| **N1** | Comprador-alvo do widget: marketing ou suporte? | **Marketing, sem abandonar suporte.** Única leitura em que o widget vira ativo de receita. Consequência: dois compradores, duas telas de config |
| **N2** | Arquitetura: manter iframe, Shadow DOM, ou híbrido? | **Manter iframe.** Conclusão convergente de 3 relatórios. **Precisa ser decidida antes de qualquer código de captura**, porque muda onde o teaser é implementado |
| **I2** | Formato de credencial daqui pra frente: HMAC ou JWT? | **JWT.** O mercado migrou (Intercom recomenda parar de gerar `user_hash`; Zendesk nasceu em JWT). Nosso HMAC não tem `exp`. A infra já está em casa |
| **I4** | Dono do `track()`: frente de integração ou de tracking? | **Tracking.** Evita construir duas vezes o mesmo evento |

---

## Parte 2 — Front end (spec de redesenho §10)

| # | Pergunta | Recomendação |
|---|---|---|
| F1 | Corpo da mensagem: 15 px ou 14 px? | **15 px.** 14 é régua de ferramenta densa; nosso usuário é visitante com pressa, no celular |
| F2 | Header colorido com a marca ou neutro? | **Colorido**, com cor de texto calculada por luminância (resolve B2 na raiz) |
| F3 | Textura de fundo da conversa | **Manter** — é assinatura de produto e a direção já foi aprovada |
| F4 | Launcher: bolha silenciosa ou que fala? | **Experimento** em 2–3 contas, não default |
| F5 | Teaser proativo entra nesta onda? | **Sim** — com ressalva honesta: não há teste A/B público comparando teaser vs auto-open |
| F6 | Dark mode default `auto` em vez de `light`? | **Sim.** É uma linha (`sdk.js:74`) e só 1 de 4 concorrentes testados suporta dark |
| F7 | Som e piscar do título da aba | **Sim**, com parâmetros já documentados |
| F8 | Rótulo persistente de identidade de IA | **Sim.** Custo é um rótulo; o risco de não ter é regulatório |

---

## Parte 3 — Integração (spec §7)

| # | Pergunta | Recomendação |
|---|---|---|
| I1 | Os dois furos de HMAC entram no fluxo de fase ou saem antes? | **Antes de tudo.** São duas correções pequenas de superfície grande |
| I3 | Atributo que o site manda e não existe: o que o produto faz? | **Auto-provisionar** como `text` marcado "não confiável" + seção "Dados recebidos do site (N)" |
| I5 | Contexto externo: ao lado da conversa ou aba? | **Ao lado primeiro**, app embutido depois |
| I6 | Publicar contrato de integração público? | **Sim, escrito junto com a Fase 1** — é onde a Leadster é fraca e onde agência decide |

---

## Parte 4 — Negócio (gap analysis §7)

| # | Pergunta | Recomendação |
|---|---|---|
| N3 | Motor do fluxo de captura: novo ou reusar Flows? | **Híbrido, Flows como fonte de verdade** — servidor decide o fluxo, sem deploy de front |
| N4 | Onde hashear PII para CAPI? | **No servidor.** O dado já é nosso |
| N5 | Instalar tag faltante no site do cliente? | **Não** — e nunca instalar um GA4 nosso, como a Leadster faz |
| N6 | Identidade verificada ligada por padrão? | **Opcional agora, padrão depois** do debugger de token |
| N7 | IA por assinatura ou por resolução? | **Assinatura.** A Ada criou a métrica e abandonou a cobrança |
| N8 | Contribuir tracking upstream? | **Seletivamente** — o patch de `targetOrigin` é candidato natural |
| N9 | Publicar um "Panorama" próprio? | **Sim, em paralelo.** Bloqueio: consentimento contratual da frota (jurídico) |
| N10 | Tools verticais de um cliente só no `tools.yml` global | **Extrair.** Dívida barata que encarece a cada vertical nova |

---

## Verificações pendentes antes de começar

Quatro itens marcados **não verificados** que mudam o plano se a resposta for negativa:

1. O webhook do WhatsApp Cloud/WAHA entrega hoje o objeto `referral` com `ctwa_clid`?
2. Existe DPA cobrindo envio de PII hasheada a Meta e Google?
3. Quantas conversas da frota já têm `utm_`/`gclid`/`fbclid` no `referer`? (dimensiona o valor do C0)
4. Quais headers de cache o nginx devolve para `/packs/`? (o `sdk.js` não tem fingerprint)
