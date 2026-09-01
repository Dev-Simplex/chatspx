# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

**Equipe mista de atendimento: agentes e gestores, na mesma ferramenta, com necessidades diferentes.**

- **Agente** — atende conversas de WhatsApp em volume, sob pressão de tempo, com o cliente
  esperando do outro lado. O painel é onde ele passa o expediente inteiro. Velocidade de leitura e
  de resposta valem mais que qualquer expressividade visual.
- **Gestor** — acompanha fila, produtividade e resultado. Consome o mesmo produto por outra porta
  (relatórios, funil, atribuição).

Confirmado pelo Walisson em 2026-07-29.

## Product Purpose

Plataforma de atendimento omnichannel (fork do Chatwoot) operada pela Simplex para si e para
empresas clientes. Centraliza conversas — majoritariamente WhatsApp — e agrega automação, IA e
funil comercial no mesmo lugar, para que o time atenda mais rápido e não perca negócio no meio do
caminho.

## Positioning

Quatro diferenciais, todos eleitos pelo Walisson como coisas que decisões futuras precisam
proteger:

1. **WhatsApp não-oficial de verdade.** Via WAHA: grupos com autor por mensagem e lista de
   integrantes, enquetes, botões, listas, reações, edição e exclusão de mensagem. É profundidade de
   WhatsApp que o Chatwoot padrão não tem.
2. **IA que atende e IA que ajuda.** Agentes de IA (Captain) atendendo o cliente com base de
   conhecimento por conta, mais um copiloto que assiste o agente humano dentro da conversa. São
   dois produtos distintos que compartilham a mesma base.
3. **Automações e funil próprios.** Plataforma Flow (automações visuais, `app/services/flows/`) e
   funil/CRM embutidos (`app/services/funnel_items/`), substituindo n8n e ferramentas externas.
4. **Feito para o Brasil.** pt-BR nativo (não tradução), nono dígito, fuso, e o jeito brasileiro de
   atender. Conta nova nasce em pt-BR por padrão.

## Operating Context

- **Uma VM por cliente.** Cada conta roda em sua própria máquina (frota). Homologação em
  `192.168.8.232` (`chatspx.app` e `hmlchat.simplexsolucoes.com.br` são o mesmo ambiente);
  produção em VMs separadas por cliente.
- **WhatsApp entra por API não-oficial.** 13 das 16 inboxes são `Channel::Api` alimentadas pela
  WAHA; há também WhatsApp oficial (1), widget web (1) e Instagram (1).
- **Escala real medida em 2026-07-29:** 4 contas — Realizare Imobiliária (1.908 conversas, 9
  usuários), Simplex Tecnologia (606 conversas, 15 usuários), Colégio Alternativo (17 usuários),
  SimplexIA (4 usuários). Verticais diferentes no mesmo produto: imobiliária, escola, tecnologia.
- **Observabilidade** por GlitchTip self-hosted, um projeto por cliente.

## Capabilities and Constraints

**Stack:** Rails 7.1 + Vue 3 (Vite) + PostgreSQL + Redis + Sidekiq. Fork do Chatwoot com
customizações próprias em `app/**/spx/`, `app/services/flows/`, `app/services/funnel_items/` e
`enterprise/**/captain/`.

**Multi-tenant real.** Uma conta não enxerga dado de outra; há isolamento de conversas por agente
(time + `PermissionFilterService`). Isto é fato técnico do produto — **não** foi eleito como
restrição durável na entrevista, mas continua sendo verdade do sistema.

**Feature flags por conta** (`config/features.yml`, 65 features): funcionalidade é ligada por
cliente, e o desligamento serve de kill-switch operacional.

**Divergência do upstream é aceita.** O Walisson **não** elegeu "conseguir mergear com o Chatwoot
original" como restrição durável. Registrado explicitamente para que trabalhos futuros não
assumam paridade com o upstream como requisito — quando alinhar for barato, alinhar é bom; quando
custar, o produto vem primeiro.

**Undecided:** se o ChatSPX é vendido como produto para o mercado ou opera só como plataforma da
Simplex para seus clientes. As duas leituras cabem nos dados atuais; não inventar posicionamento
comercial antes de decidir.

## Brand Commitments

**A interface é WhatsApp-fiel, e isso é compromisso, não estilo.** O redesign aprovado faz o agente
reconhecer a ferramenta de imediato, porque é a mesma linguagem visual do aplicativo em que ele já
trabalha o dia todo. Tokens em `app/javascript/dashboard/assets/scss/_wa-skin.scss`.

Consequência para trabalho futuro: superfícies novas herdam essa linguagem por padrão. Quando uma
superfície precisar de outra (o copiloto adotou o vocabulário monocromático da OpenAI, por
exemplo), a divergência é deliberada e fica contida naquela superfície — não vaza para a conversa.

Nome do produto: **ChatSPX**.

## Evidence on Hand

Dados reais desta base (homologação), medidos e não estimados:

- 4 contas ativas, 16 inboxes, ~2.500 conversas
- 542 mensagens de grupo no formato legado (com identificador técnico no texto) — corrigidas em
  2026-07-28
- 9 respostas prontas na base inteira (o acervo é pequeno; isso sustentou a decisão de aposentá-las
  em favor da IA)
- 90 conversas de grupo, 33 com integrantes sincronizados
- GlitchTip com histórico real de erros da frota

**Não fabricar:** depoimentos, número de clientes, faturamento, benchmarks de mercado, preço ou
promessa de SLA. Nada disso foi estabelecido.

## Product Principles

1. **O agente está com um cliente esperando.** Toda decisão de produto é medida em segundos até a
   resposta sair. Recurso que exige aprendizado, cliques ou leitura longa compete com o cliente do
   outro lado da tela.
2. **Reconhecível antes de bonito.** A interface toma emprestada a linguagem do WhatsApp de
   propósito. Originalidade que custa reconhecimento é prejuízo.
3. **Degradar com honestidade.** WhatsApp cai, IA fica sem crédito, integração expira. O produto
   diz o que houve e o que fazer — nunca some com a informação, nunca culpa a conexão do usuário,
   nunca deixa girando para sempre.
4. **Identificador técnico não é informação de atendimento.** LID, JID, UUID e chave interna nunca
   aparecem na tela. O agente vê pessoa, telefone e nome.
5. **Toda funcionalidade nasce desligável por conta.** A frota é heterogênea; o que entra precisa
   poder ser ligado num cliente e desligado em outro sem deploy.

## Accessibility & Inclusion

- **Paridade clara/escura é exigência**, não opção: toda superfície é validada nos dois temas antes
  de ser dada como pronta.
- **pt-BR é a língua do produto**, com `en` mantido em paridade. Chave de tradução crua na tela
  conta como defeito.
- Cor nunca é o único portador de significado (o nome do autor aparece escrito ao lado da cor que o
  identifica, por exemplo).
