# Métricas por número (Vendas × Locação) — como validar

**Proposta para o cliente:** https://nicolas.chatspx.app/dois-numeros-dois-relatorios.html
**Especificação:** `task/metricas-por-numero-vendas-locacao.md`
**O que foi feito:** Fase 1 — o recorte por número atravessando os relatórios históricos.
**Migration:** nenhuma. **Flag:** nenhuma. **Sem commit** (working tree da branch `nicolas`).
**Estado:** compilado e no ar em `nicolas.chatspx.app`.

---

## A regra

Um seletor **"Todos os números ▾"** entra na barra de filtros dos Relatórios, ao lado do
período. O que ele escolhe vale para a tela inteira — cards, gráficos, tabelas, CSV e PDF — e
**fica lembrado**: vai na URL (`?inbox_id=`) e no navegador, então sobrevive ao reload e à troca
de aba.

Por baixo é um filtro **ortogonal** ao relatório: o "agente X" continua sendo o assunto, o
número vira o recorte. É isso que permite pedir *"o Guilherme, só no número de vendas"* — que é
o coração do pedido do cliente.

## Onde o seletor aparece

| Aba | Tem o seletor | Observação |
|---|---|---|
| Conversas | ✅ | cards, todos os gráficos, CSV e PDF |
| Atendentes (visão geral) | ✅ | **a tabela do ranking** — o pedido do Guilherme |
| Times / Etiquetas (visão geral) | ✅ | mesma tabela, mesmo recorte |
| Atendente / Time / Etiqueta (individual) | ✅ | série temporal por entidade, recortada |
| Caixas (visão geral e individual) | — | escondido de propósito: ali o número **é** a linha |
| Atribuições | já tinha | filtro próprio de time + caixa, anterior a esta task |
| CSAT · NPS · SLA | já tinham | filtro próprio de caixa, anterior a esta task |
| Visão geral (ao vivo) · Em atendimento · Bot | ❌ **fora desta fase** | são painéis do "agora", sem barra de período; entram na próxima |

## Roteiro de validação na tela (10 minutos)

Entre em `nicolas.chatspx.app` → **Relatórios**.

1. **Aba Conversas.** O chip "Todos os números" aparece ao lado do período. Anote o total de
   conversas. Escolha um número → o total tem que cair e o gráfico redesenhar.
2. **A URL mudou.** Confira o `?inbox_id=` no endereço. Dê F5: a escolha continua lá.
3. **Trocou de aba, continua valendo.** Vá para **Atendentes** sem mexer em nada: o chip tem que
   estar no mesmo número (é a memória do navegador; é isso que impede o "voltou pro misturado").
4. **O ranking recortado.** Ainda em Atendentes, compare a tabela com "Todos os números" e com
   um número só: quem não atende naquele número tem que **sumir da contagem** (ficar em `--`).
5. **Fecha a conta.** Com "Todos os números", anote o total de conversas. Some o total de cada
   número, um a um: tem que dar o mesmo (a prova por baixo, abaixo, já mostra isso fechando).
6. **A exportação leva o recorte.** Com um número escolhido, baixe o **CSV** (números só daquela
   linha) e o **PDF** — o subtítulo do PDF tem que terminar com **"· Somente <nome do número>"**.
   Se o PDF sair sem esse carimbo, é bug: alguém vai circular um PDF "de vendas" com número da
   conta inteira.
7. **Aba Caixas.** O chip **não** deve aparecer — ali o recorte seria redundante.

## A prova por baixo (já rodada em 28/08/2026, conta 1 do staging)

```
  WhatsApp Vendas          builder=0     sql=0
  ...
  QA Tempo Real            builder=51    sql=51
TOTAL=54 SOMA=54 FECHA

recorte: QA Tempo Real
  QA Admin             todas=4    nesta caixa=4
  Realtime Test B      todas=12   nesta caixa=12
  Walisson             todas=1    nesta caixa=0     ← não atende neste número, sai do ranking
  soma todas=52 | soma recorte=51
  serie: pontos=31 soma=51                          ← o gráfico bate com a tabela
  eventos sem caixa (30d)=0                         ← nada se perde no corte
```

Para repetir na conta do cliente, troque o `Account.find(1)`:

```bash
cd /home/chatwoot/chatwoot && bundle exec rails runner -e production '
a = Account.find(1); r = 30.days.ago..Time.current
b = { since: 30.days.ago.to_i.to_s, until: Time.current.to_i.to_s, business_hours: false }
t = V2::Reports::Conversations::MetricBuilder.new(a, b.merge(type: :account)).summary[:conversations_count]
s = 0
a.inboxes.order(:id).each do |i|
  c = V2::Reports::Conversations::MetricBuilder.new(a, b.merge(type: :account, inbox_id: i.id)).summary[:conversations_count]
  s += c
  puts format("  %-24s builder=%-5d sql=%-5d", i.name.to_s[0, 24], c, a.conversations.where(inbox_id: i.id, created_at: r).count)
end
puts "TOTAL=#{t} SOMA=#{s} #{t == s ? "FECHA" : "NAO FECHA"}"
puts "eventos sem caixa: #{a.reporting_events.where(inbox_id: nil, created_at: r).count}"'
```

Três coisas têm que ser verdade: **builder == sql** em cada linha, **TOTAL == SOMA**, e
**eventos sem caixa = 0**. A última é a que diz se o corte perde alguma fatia do histórico.

## Armadilhas que já foram fechadas

1. **Dimensão única** — o `inbox_id` entra como filtro por cima do `scope`, não como mais um
   `type`. Sem isso, "agente X só em vendas" seria impossível
   (`timeseries/base_timeseries_builder.rb`).
2. **Números que não fecham** — o filtro foi aplicado nos **dois** lados de cada tabela: a
   contagem em `conversations` e as médias em `reporting_events` (`base_summary_builder.rb`).
   Só um dos dois produziria "40 conversas" com tempo médio da conta inteira.
3. **Mensagens têm caixa própria** — `incoming/outgoing_messages_count` filtra por
   `messages.inbox_id`, não pela conversa.
4. **Aba Caixas** — o seletor é escondido lá (`type !== 'inbox'`).
5. **PDF meio recortado** — os KPIs, a tabela **e as séries** do PDF passaram a usar o builder
   novo, que aceita o recorte; o legado (`V2::ReportBuilder`) não aceitava e deixaria a curva do
   PDF com a conta inteira embaixo de um KPI de uma linha só.
6. **Perder a escolha** — URL + memória do navegador (`helpers/inboxScope.js`).

## Specs

`bundle exec rspec spec/builders/v2 spec/controllers/api/v2/accounts/{reports,summary_reports}_controller_spec.rb`
→ **129 exemplos, 43 falhas — todas anteriores a esta task.** São specs do upstream que nunca
foram atualizadas quando o fork acrescentou campos aos relatórios:

- `avg_first_response_time_after_assignment` e os percentis — commit `1f58202e4` (09/02/2026)
- `team_id` nos params do summary — commit `def522d5b` (06/07/2026)

Nenhuma falha menciona `inbox_id`, `with_inbox_filter` ou erro de SQL. Frontend:
`npx vitest run app/javascript/dashboard/api/specs/reports.spec.js app/javascript/dashboard/store/modules/specs/reports`
→ **19 exemplos, 0 falhas.**

## O que falta (próxima fase)

- **Visão geral (ao vivo)**, **Em atendimento** e **Bot**: painéis do "agora", sem barra de
  período — precisam do seletor próprio.
- **Fase 2 do plano**: quem não é administrador abrir os relatórios já pré-filtrado nos números
  que atende. Muda o que as pessoas veem — depende do "ok" do cliente.
