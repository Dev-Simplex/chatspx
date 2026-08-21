# Triagem da suíte — 21/08

Recorte do redesenho do chat de site, branch `homologacao`. Tudo local: **nada foi pushado**.

## Números (medidos, não estimados)

| momento | exemplos | falhas |
|---|---|---|
| `origin/homologacao` (base) | 8.928 | 399 |
| início da triagem | 10.067 | 382 |
| meio (checkpoint) | 10.068 | 285 |
| **fim** | **10.070** | **102** |

O recorte acrescenta **+1.142 exemplos** à suíte e a deixa com **um quarto das falhas da
base**. Medição por 6 grupos em paralelo, cada um com banco dedicado.

Duas ressalvas de método, porque elas mudam a leitura dos números:

- rodar specs *enquanto* a medição corre a contamina. Um checkpoint chegou a marcar 16 falhas
  num grupo que, medido limpo, tem 6 — as 10 extras eram artefato da minha própria carga
  concorrente (specs de Flow, sensíveis a tempo). Passam 64/64 isolados;
- o número que decide deploy é o da medição **limpa**, com nada mais rodando.

## O que motivou

A suíte tinha 382 falhas. Falha em massa não distingue "defeito nosso" de "spec herdado
desatualizado", e enquanto não distingue, ninguém confia no vermelho — que é justamente
quando ele para de servir para alguma coisa.

## Defeitos de produção encontrados

Nenhum destes foi procurado. Todos apareceram porque um spec vermelho foi lido até o fim em
vez de ser adaptado até ficar verde.

| # | Defeito | Efeito | Origem |
|---|---------|--------|--------|
| 1 | `resource :star` roteava para `stars#` (plural), classe é `StarController` | endpoint de favoritar mensagem **404 para todo mundo**, desde sempre | recorte |
| 2 | `push_diagnostics` e `platform_banners` nas rotas sem controller | **painel super_admin inteiro em 500** — a barra do Administrate vive no layout | recorte |
| 3 | `jsonb_set` sem criar o nó pai | configuração por usuário da conversa **nunca persistia** (pin/arquivar/silenciar/tema) | base |
| 4 | `ActionController::Parameters` contra `is_a?(Hash)` | mesmo endpoint respondia **422 para toda requisição válida** | base |
| 5 | `valid_token?(nil)` == `nil` | **verificação do webhook do Instagram passava sem token** | base |
| 6 | `redirect_to` sem `allow_other_host` | `GET /auth/sign_in` respondia **500** quando o domínio de acesso ≠ FRONTEND_URL | base |
| 7 | `conversation_faq_generator` perdido no merge | geração de FAQ a partir de conversas **quebrada** | recorte |
| 8 | `captain_false_promise_harness_enabled` sem `store_accessor` | recurso **inligável** + uma exceção por resposta da IA indo pro GlitchTip | recorte |
| 9 | `AssistantActionClassifierService` passava `feature:` a um construtor que não aceita | classificador **não instanciava**; a resposta não chegava ao cliente | recorte |
| 10 | `Captain::Document#to_llm_metadata` nunca existiu | `NoMethodError` em toda geração de FAQ paginada (PDF) | recorte |
| 11 | `MESSAGE_UPDATED` disparado em duplicata | assinantes (ActionCable, webhooks) recebiam tudo duas vezes | recorte |

Os itens 3 e 4 estavam na **mesma feature**, em camadas diferentes — por isso cada spec
falhava por um motivo distinto e consertar um não acendia o outro.

## O padrão que mais apareceu

**Verde por ausência de sujeito.** Um teste que afirma ausência ("404", "não chamou", "não
gravou") passa tanto quando o código acertou quanto quando o sujeito nunca existiu.

- Dois specs do Instagram batiam numa rota inexistente, esperavam 404, recebiam o 404 da rota
  ausente e **nunca chegaram ao controller** — cobrindo exatamente o caminho com o furo de
  segurança.
- `it 'does not run the false promise harness when disabled'` passava porque o método
  **explodia** antes de instanciar o detector.

Registrado no vault como lição permanente.

## Categorias das falhas herdadas

Não são defeitos — são divergências deliberadas nossas que ninguém propagou para os specs:

- **tradução** (a maior): conta nasce em pt-BR por decisão nossa; specs cravam o inglês.
  Conserto: ler a mesma chave i18n com `locale:` explícito;
- **spec que mede o ambiente**: cravava o valor de *fallback* de `FRONTEND_URL`, ou presumia
  que `MAILER_INBOUND_EMAIL_DOMAIN` não existe. Passavam só em máquina desconfigurada;
- **contrato desatualizado**: código passa `id`, spec espera o objeto; webhook ganhou
  assinatura, spec ficou com 2 argumentos;
- **feature não adotada**: spec do upstream trazido sem a implementação que o acompanha.

## Travas criadas

- `spec/routing/super_admin_routes_spec.rb` — toda rota do namespace tem controller.
  Provado que acusa: rota falsa inserida → falhou nomeando-a → removida → verde.
- `spec/support/mock_redis_eval.rb` — MockRedis não tem Lua; o dublê executa **só** scripts
  conhecidos e levanta em qualquer outro, para nunca aprovar Lua não implementado.

## O que fica pendente (não é meu para decidir)

- **`change_set_applier` (14 falhas)** — feature de change-sets do Paulo. Código e spec
  idênticos à base; o spec exercita operações que `SUPPORTED_OPERATIONS` nunca teve.
- **16 grupos de rota sem controller** — inertes (nenhuma é chamada pelo front), mas podem
  ser lugar reservado para trabalho de outra pessoa. Apagar rota alheia não é minha decisão.
- **`toggle_status` não solta o dono-robô** — nosso próprio spec diz que deveria; a regra de
  quem pode ser solto é desenho documentado (espelho captain, gate D1). Decisão do dono.
- **`update_last_seen` não marca notificação como lida** — `update_columns` pula callbacks
  na base e na nossa árvore; o comportamento não existe em lado nenhum.
