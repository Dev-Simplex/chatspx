# Runbook — Validação E2E (sandbox SimplexIA) e verificação da regra #53 na virada

> **Fase E/E1** (`plano/fase-d-design.md` §10.1, design @architect 2026-06-11). Complementa o roteiro
> E2E do `plano/ia-consolidado.md` §5.3 (17 testes) e o checklist da virada (§6 item 3) — **não**
> duplica nem edita o consolidado; referencia.
>
> **Nada deste runbook é executado na implementação.** Os passos abaixo rodam apenas na **janela de
> validação E2E** (homolog) e na **janela da virada** (PROD Tozi).

---

## 1. Fatos verificados (estado em 2026-06-11)

| Fato | Detalhe |
|---|---|
| Regra **#53 NÃO existe em homolog** | Vive só na **Tozi PROD**; a account 6 de homolog tem **zero** automation rules |
| Equivalente funcional na sandbox: **regra #29 "opa" da account 1** (SimplexIA) | `event_name: conversation_opened`, inbox **16**, ação `assign_agent → ['nil']`, **ATIVA** |
| Efeito da #29 | Zera o assignee humano a cada **reopen** — quebra diretamente o teste E2E **§5.3 #11** ("Resolver + lead volta → reabre SEM dono → triagem re-atribui") |
| Account 3 tem **6 regras** com `assign_agent nil` | ids **3, 5, 6, 7, 11, 12** — relevantes SÓ se o `reply_assignment_gate` for ligado naquela conta; registrado para não esquecer |

### Nota técnica (do dossiê — por que uma #53-like não cala a IA no modelo novo)

`assign_agent('nil')` só zera `assignee_id` (`app/services/automation_rules/action_service.rb:43-44`)
e **NÃO limpa o espelho captain** — o callback `reset_agent_bot_when_assignee_present`
(`app/models/conversation.rb`) exige assignee **presente** para resetar o bot. Ou seja: uma regra
`conversation_opened → assign_agent nil` **não** desatribui a IA; o dano real é **desatribuir
HUMANOS** a cada reopen e **brigar com a triagem** (re-atribuição em loop).

---

## 2. Procedimento na janela de validação E2E (homolog, account 1 / inbox 16)

Executar **ANTES** de rodar o roteiro §5.3 (em especial o teste #11):

```bash
# 1) Desativar a #29 (NÃO deletar — reversível):
bundle exec rails runner "AutomationRule.find(29).update!(active: false)"

# 2) Conferir:
bundle exec rails runner "puts AutomationRule.find(29).active"   # => false
```

Ao **final** da janela:

```bash
# Reativar (ou substituir pela regra de triagem definitiva, se já existir):
bundle exec rails runner "AutomationRule.find(29).update!(active: true)"
```

- [ ] Registrar a desativação E a reativação no **log da validação** (data/hora + quem rodou).
- [ ] Teste **#14** (reatribuição em massa via script): pré-requisito é o E2 aplicado —
  `scripts/spx/tozi/consolida_conversas_duplicadas.rb` atribui via `Conversations::AssignmentService`
  (o script não tem harness de spec; a validação da invariante humano×espelho sob re-execução é
  **manual**, neste teste).

---

## 3. Checklist da virada (PROD Tozi — §6 item 3 do consolidado)

Verificação **READONLY** da #53 em PROD antes de ligar a triagem (impossível validar de homolog):

```bash
# Em PROD, somente leitura — NÃO alterar nada neste passo:
bundle exec rails runner "
  r = AutomationRule.find_by(id: 53)
  puts r ? [r.id, r.name, r.event_name, r.active, r.actions].inspect : 'regra 53 ausente'
  AutomationRule.where(account_id: <ACCOUNT_TOZI>).where('actions::text LIKE ?', '%assign_agent%').find_each do |a|
    puts [a.id, a.name, a.event_name, a.active, a.actions].inspect
  end
"
```

- [ ] Confirmar o estado da #53 (e de QUALQUER outra regra `conversation_opened → assign_agent nil`)
  antes de ligar a triagem.
- [ ] Na virada (sequência do §6 item 3): registrar elegibilidade (CaptainInbox) → criar automação de
  triagem (`conversation_created`: intenção → team + agente IA) → **desativar a #53** → ligar
  `reply_assignment_gate` na conta.
- [ ] A substituta da #53 (E1) re-triagem **apenas órfãs REAIS**: a regra nova de triagem
  (`conversation_created`) + o vigia de órfãs (C10) cobrem o caso de uso original. **Nenhuma regra
  `conversation_opened → assign_agent nil` sobrevive à virada.**
- [ ] Rollback documentado: desativar a automação de triagem + desligar a flag do gate (conversas já
  atribuídas a humanos não mudam).

---

## 4. Auditoria pós-validação (telemetria E4)

Após o roteiro §5.3, conferir a trilha no `captain_assistant_logs` (eventos da Fase E/E4):

| Evento | Quando deve aparecer |
|---|---|
| `mirror_assigned` | triagem/admin/transferência IA→IA atribui o espelho (testes #2, #10) |
| `mirror_released` (`reason: resolve`) | resolve limpa o espelho (teste #11, A2e) |
| `mirror_released` (`reason: unassigned`) | automação/None solta o espelho sem novo dono |
| `human_takeover` (`reason: assignment`) | humano assume via dialog/atribuição (testes #8, #9) |
| `human_takeover` (`reason: reply`) | humano responde sem se atribuir — A2c (echo do celular incluso) |

```bash
bundle exec rails runner "
  Captain::AssistantLog.where(event_type: %w[mirror_assigned mirror_released human_takeover])
                       .ordered.limit(30).each { |l| puts [l.created_at, l.event_type, l.conversation_id, l.payload].inspect }
"
```
