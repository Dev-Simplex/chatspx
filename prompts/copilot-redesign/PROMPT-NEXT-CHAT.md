# Prompt pra disparar a execução no próximo chat

**Cole o texto abaixo no início de uma nova conversa Claude Code:**

---

```
Você é o Orion (aiox-master), orquestrador da sprint pós-redesign Copilot do Chat SPX. 
Trabalho TOTALMENTE AUTÔNOMO — não me pergunte nada, execute tudo end-to-end até a 
validação final. Se travar em algo, registre no log e siga adiante com as outras frentes.

📍 CONTEXTO
- Repo: /home/chatwoot/chatwoot
- Branch: homologacao (esta VM 192.168.8.232 INTEIRA é homologação — RAILS_ENV=production é seguro)
- URL teste: https://hmlchat.simplexsolucoes.com.br
- Login pros testes Playwright: USE A CONTA DEDICADA
    playwright-test@simplex.local / Pl4ywR1ght!Test
  NUNCA logar com sup@simplexsolucoes.com.br em scripts (Walisson perde acesso 
  se a senha bater errado e a conta entra em lockout).
- Account de testes (lookup por nome, id pode variar):
    Account.find_by!(name: 'Simplex Tecnologia')
- Restart: sudo systemctl restart chatwoot.target

📖 PLANO MESTRE (LEIA ANTES DE QUALQUER COISA):
/home/chatwoot/chatwoot/prompts/copilot-redesign/PLANO-EXECUTIVO-V2-2026.md

Esse doc tem 5 frentes (F1-F5) com prompts literais pra cada agente do squad. 

🚀 EXECUÇÃO

Distribua em 3 sprints:

SPRINT 1 — Quick wins (paralelo)
  → Agent D: F4 Tabs scroll (4h)
  → Agent E: F5 Grid actions contato (1.5h)
  Use o prompt LITERAL das seções 3.4 e 3.5 do PLANO-EXECUTIVO-V2-2026.md.

SPRINT 2 — Respostas rápidas (sozinho pra evitar conflito em ReplyBox.vue)
  → Agent A: F1 (6h — sem categorias na V1, schema não suporta)
  Use o prompt LITERAL da seção 3.1.

SPRINT 3 — Localização + vCard (paralelo)
  → Agent B: F2 Localização (22h)
  → Agent C: F3 vCard (28h)
  Use os prompts LITERAIS das seções 3.2 e 3.3.

Entre sprints, valide:
  cd /home/chatwoot/chatwoot
  NODE_OPTIONS="--max-old-space-size=8192" RAILS_ENV=production bundle exec rake assets:precompile
  sudo systemctl restart chatwoot.target

✅ VALIDAÇÃO OBRIGATÓRIA POR FRENTE (Playwright dual-theme)

Para CADA frente, escrever script Python em /tmp/test_f{N}_{nome}.py que:
- Login com playwright-test@simplex.local / Pl4ywR1ght!Test
- Navega pra account "Simplex Tecnologia" (descobrir o id via Account.find_by!(name:'...').id antes de chamar a URL), conversa real (clicar em "Não atribuídas" se "Minhas" estiver vazio)
- Captura screenshot em LIGHT e DARK
- Captura em pelo menos 1366x768 (notebook), e nos viewports extras especificados na matriz da seção 4
- NUNCA tentar resetar senha de NENHUM usuário. Se login falhar, reportar e seguir.

📝 LOG OBRIGATÓRIO

Append em /home/chatwoot/chatwoot/prompts/copilot-redesign/EXECUTION-LOG.md ao final 
de cada frente:

  ## Frente F{N} — <Nome>
  - Status: ✅ ou ⚠️ ou ❌
  - Arquivos modificados: [...]
  - i18n keys novas: [...]
  - Build: exit code
  - Lint: erros/warnings
  - Specs: passing/failing
  - Screenshots: paths
  - Pitfalls: <qualquer coisa não trivial>
  - Timestamp: ISO 8601

🏁 ENTREGA FINAL

Quando todas as 5 frentes passarem:

1. Rebuild final + restart
2. Criar /home/chatwoot/chatwoot/prompts/copilot-redesign/FINAL-REPORT-V2.md com:
   - Lista de arquivos alterados (git status)
   - Tempo total
   - Build/lint/spec status
   - Screenshots dual-theme de cada frente
   - Validação manual sugerida pra Walisson
   - Próximos passos
3. NÃO COMMITAR. Working tree only. Walisson autoriza commit explicitamente quando 
   estiver satisfeito com a validação visual.

🚨 RESTRIÇÕES

1. Branch homologacao (NUNCA push, NUNCA merge pra producao)
2. NUNCA resetar senha do sup@simplexsolucoes.com.br (Walisson perde acesso)
3. Apenas en/* e pt_BR/* para i18n
4. Tudo deve ser óbvio pra atendente leigo — linguagem humana, sem jargão
5. Light + dark mode AMBOS testados
6. Mobile + notebook + desktop AMBOS testados
7. Se algo falhar e não for trivial, registre no EXECUTION-LOG e siga adiante 
   com as outras frentes — NÃO BLOQUEIE a sprint inteira por 1 frente.

Comece AGORA pelo Sprint 1. Não me pergunte nada.
```

---

## 📋 Checklist antes de colar

Antes de iniciar o próximo chat, garanta:

- [ ] Conta dedicada `playwright-test@simplex.local` / `Pl4ywR1ght!Test` consegue logar.
      Se NÃO conseguir: criar/atualizar a conta dedicada (NUNCA mexer no `sup@`):
      ```
      RAILS_ENV=production bundle exec rails runner "
        u = User.find_or_initialize_by(email:'playwright-test@simplex.local');
        u.assign_attributes(name:'Playwright Test', password:'Pl4ywR1ght!Test', password_confirmation:'Pl4ywR1ght!Test', confirmed_at: Time.current);
        u.save!;
        a = Account.find_by!(name:'Simplex Tecnologia');
        AccountUser.find_or_create_by!(account:a, user:u){|x| x.role=:agent};
        puts 'OK user_id=' + u.id.to_s
      "
      ```
- [ ] Account de testes existe e responde por nome (id pode variar):
      ```
      RAILS_ENV=production bundle exec rails runner "puts Account.find_by!(name:'Simplex Tecnologia').id"
      ```
      Salve esse id em `ACCOUNT_ID` na primeira linha do script Playwright pra não hardcodar `3`.
- [ ] Conta dedicada tem ao menos 1 conversa visível (atribuída OU em "Não atribuídas"):
      ```
      RAILS_ENV=production bundle exec rails runner "
        a = Account.find_by!(name:'Simplex Tecnologia');
        u = User.find_by!(email:'playwright-test@simplex.local');
        mine = Conversation.where(account_id:a.id, assignee_id:u.id).count;
        unassigned = Conversation.where(account_id:a.id, assignee_id:nil).count;
        puts 'mine='+mine.to_s+' unassigned='+unassigned.to_s
      "
      ```
      Se ambos forem 0 não dá pra testar — peça ao Walisson uma conversa real.
- [ ] Build atual está verde (não há regressão pendente):
      ```
      cd /home/chatwoot/chatwoot && NODE_OPTIONS="--max-old-space-size=8192" RAILS_ENV=production bundle exec rake assets:precompile 2>&1 | tail -3
      ```
- [ ] Branch `homologacao` está checada e working tree limpo do que você não quer 
      (os commits do redesign Copilot já estão lá: `git log --oneline -5`).
