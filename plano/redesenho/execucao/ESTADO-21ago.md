# Estado da execução — 21/08/2026

Continuação do `ESTADO-18ago.md`. Aquele documento descreve a branch `redesenho-integra`
na data dele. **Este descreve outra coisa:** o recorte já pousado em `homologacao` e a
triagem da suíte que veio junto.

## 1. Onde o código está

| item | valor |
|---|---|
| branch | `homologacao` |
| base | `origin/homologacao` = `ce3adb2be9` — **intocado** |
| commits locais | **74** |
| pushado | **nada** |
| árvore de trabalho | limpa |

## 2. A régua

| momento | exemplos | falhas |
|---|---|---|
| `origin/homologacao` (base) | 8.928 | 399 |
| início da triagem | 10.067 | 382 |
| **agora** | **10.070** | **17** |

O recorte acrescenta **+1.142 exemplos** e a suíte sai de 399 falhas na base para 19.

As 17 são **todas escaladas** — decisão de outra pessoa (§5). Nenhuma falha restante é
defeito nosso por consertar.

Duas outras eu havia rotulado de instáveis. Não eram: uma vinha de `Current` vazando entre
exemplos, outra do `Faker` voltar a pt-BR dentro de thread. A segunda levou ao achado de que
o dublê de Redis **não era compartilhado entre as conexões do pool** — `SET NX` devolvia
`true` para duas conexões concorrentes, ou seja, toda invariante de exclusão mútua via Redis
estava passando no vácuo. Corrigido e provado por contraprova.

### Suíte JS

| momento | arquivos | testes | falhas |
|---|---:|---:|---:|
| antes | 565 | 6.286 | **26** |
| **agora** | **565** | **6.292** | **0** |

As 26 eram **todas herdadas**: rodei os 11 arquivos numa worktree de `origin/homologacao` e ela
falha exatamente os mesmos 26. Nem os specs nem os sujeitos deles tinham sido tocados pelo
recorte. Também some uma **rejeição não tratada** que o próprio Vitest sinalizava como capaz de
produzir falso positivo.

Detalhamento completo em **`plano/triagem-suite-21ago.md`**.

## 3. O que a triagem achou

**34 defeitos de produção**, nenhum procurado — todos apareceram porque um spec vermelho foi
lido até o fim em vez de ser adaptado até ficar verde. A tabela nominal está no relatório da
triagem; os de maior alcance:

- **credencial de integração vazava na API** — `visible_properties` era declarado em três
  pontas do contrato e não existia na quarta;
- **verificação do webhook do Instagram passava sem token**;
- **painel super_admin inteiro em 500** — uma rota órfã derruba o layout do Administrate;
- **um job diário desligava o Captain em todas as contas**;
- **12 recursos entregues eram ingraváveis** — `features.yml` de duas colunas contra
  `featurable.rb` de uma; levantava `RangeError`, não ficava "desligado";
- **gravar rótulo ou prioridade quebrava** — callback incondicional chamando classe ausente;
- **toda resposta da IA caía em handoff** — três defeitos empilhados, cada um bastava sozinho;
- **apagar time e apagar conversa eram impossíveis**;
- **`utm`/`gclid` descartados em silêncio** na primeira mensagem do widget.

**Quatorze** são da base (`origin/homologacao`) — ou seja, **estão em produção hoje**. Os
outros **vinte** entraram com o recorte e foram consertados antes de sair daqui.

## 4. Deploy — o que está pronto e o que não está

- **Front:** o bundle do vite servido (manifest de 21/08 06:28) **continua válido**. Os
  únicos arquivos de `app/javascript` tocados desde então são de teste. Não precisa
  `assets:precompile`.
- **Ruby:** **23 commits** em `app/`, `enterprise/`, `lib/` e `config/` são posteriores ao
  boot do Puma da porta 3000 (no ar há ~14,5 h). O servidor de homologação **ainda roda o
  código pré-conserto** — quem testar em `hmlchat` agora vê o comportamento antigo. Carregar
  os consertos exige `sudo systemctl restart chatwoot.target`, que **não foi pedido**,
  conforme a instrução permanente.
- **Migrations: SÃO necessárias.** O recorte traz **12 migrations novas** e o `schema.rb`
  cresce 345 linhas. Sem colisão de timestamp (conferido com `uniq -d`). Três merecem leitura
  antes de rodar na frota:
  - `20260714123000_purge_pending_captain_assistant_responses` — **transforma dado de
    cliente**: transfere FAQ pendente de revisão para o fluxo novo e só então apaga a linha
    velha. O purge do upstream apagava sem substituto; este não. `down` é vazio.
  - `20260723000000_cascade_conversation_deletion_for_orphan_blockers` — troca 5 FKs para
    `SET NULL`/`CASCADE`, o que faz `conversation.destroy!` voltar a funcionar. Os dois
    caminhos que chegam em `flow_step_logs` são ambos `SET NULL`, então não há o conflito de
    cascade multi-caminho que passa no `schema.rb` e quebra na frota.
  - `20260819120000_scope_webhook_url_uniqueness_to_inbox` — **relaxa** um índice único, que
    é a direção segura sobre dado existente (apertar é que falha em produção e passa em banco
    de teste vazio). Usa `NULLS NOT DISTINCT` para não abrir brecha.

  A `20260515000000_enqueue_validate_openai_hooks_job` é deliberadamente **inerte**: enfileirar
  o job apagaria a integração de IA de VMs cujo gateway responde 401 em `/models` — com chave
  boa. O housekeeping ficou manual, com `dry_run: true`.

## 5. O que precisa de decisão humana

Herdado do 18/08 e ainda aberto:

1. **Blocos 0.4 e 0.10** — infraestrutura, exigem sudo, não foram pedidos. Seguem travando
   `5.02 → 5.11 → 5.14` e `5.21`.
2. **`POST /api/v1/widget/conversations` sem HMAC** — decisão de produto: fechar a porta
   afeta integração de cliente existente.
3. **`button-name` em 11 nós** — caminho interativo do widget mudo para leitor de tela.
4. **Contraste abaixo de AA em três telas**, uma com razão 1,0 (invisível).
5. **`logo < 5 KB`** — decisão de marca.

Novo, vindo da triagem:

6. **`change_set_applier` (14 falhas)** — feature de change-sets do Paulo. Código e spec
   idênticos à base; o spec exercita operações que `SUPPORTED_OPERATIONS` nunca teve.
7. **`Integrations::Cloudflare::RealtimeKitCredentialsValidator`** — classe inexistente,
   chaves i18n presentes. Precisa de chamada a API externa e decisão de produto.
8. **16 grupos de rota sem controller** — inertes, mas podem ser lugar reservado de outra
   pessoa. Apagar rota alheia não é decisão minha.
9. **`toggle_status` não solta o dono-robô** e **`update_last_seen` não marca notificação
   como lida** — nossos próprios specs discordam do desenho documentado. Decisão do dono.

## 6. O que **não** foi feito, de propósito

- Nada pushado, nada deployado, nenhuma migration rodada.
- Nenhuma operação destrutiva de banco.
- A matriz de snapshots continua em **20** — não foi reduzida.
- Nenhum critério numérico foi afrouxado para fechar item.
- Nada do upstream fora do que o planejamento produziu.
