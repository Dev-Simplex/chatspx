# Recorte do Supervisor — validação visual

**Mockup interativo:** https://claude.ai/code/artifact/32f78e7a-b3c2-4d05-bf6b-6d9d1a904462
**Commit:** `525f7f2ef` na branch `nicolas` (repo `/home/chatwoot/chatwoot`), sem push.
**Staging:** ✅ **no ar em `nicolas.chatspx.app`** desde 21/08/2026 — precompile OK, restart OK,
`version.json` = `525f7f2ef`. **Nada foi para a frota.**
**Migration:** nenhuma. **Flag:** nenhuma.

---

## A regra

**Supervisor = quem tem linha em `team_supervisors`.** Supervisiona time → não administra a
plataforma. Fonte única em `app/services/supervisor_settings_scope.rb`.

Seis itens saem do alcance dele: Console de Super Admin, Atributos Personalizados, Robôs,
Macros, Integrações e Fluxo de Conversa. Todo o resto continua igual.

## Ler não é administrar

| Item | Negado | Mantido — e por quê |
|---|---|---|
| Atributos personalizados | POST/PATCH/DELETE | `index`/`show` — alimentam os campos personalizados do painel do contato e da conversa |
| Robôs | create/update/destroy/avatar/reset_token | `index`/`show` — a tela da caixa de entrada lista os bots |
| Macros | create/update/destroy | `index`/`execute` — executar macro na conversa é uso legítimo |
| Integrações | hooks, webhooks, dashboard apps, Slack, OpenAI | `GET integrations/apps` — Dyte e sugestão de etiqueta consultam isso dentro da conversa |
| Fluxo de conversa | `auto_resolve_*`, `conversation_required_attributes` | resto do `PATCH /accounts` — nome, idioma e domínio seguem editáveis |
| Console de Super Admin | login + toda rota do console | sessão do dashboard não é afetada |

---

## Pré-voo — ✅ RODADO EM 21/08/2026, GATE LIVRE

```
11 | supervisor.teste@chatspx.app | tipo=nil        | conta 1=agent
14 | sup@simplexsolucoes.com.br   | tipo="SuperAdmin" | conta 1=administrator   ← único alvo da regra
17 | nicolasnatha8@gmail.com      | tipo=nil        | conta 1=agent
--- super admins: 1 (dev@simplexsolucoes.com.br) e 14 ---
```

**O id 1 não supervisiona nenhum time** → mantém o `/super_admin` intacto. Nenhum administrador
inesperado na lista. Bate exatamente com o que o `.md` original mediu.

Para reconferir depois:

```bash
cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rails runner '
  ids = TeamSupervisor.distinct.pluck(:user_id)
  User.where(id: ids).each do |u|
    papeis = u.account_users.map { |au| "conta #{au.account_id}=#{au.role}" }.join(", ")
    puts "#{u.id} | #{u.email} | tipo=#{u.type.inspect} | #{papeis}"
  end'
```

⚠️ **Se `dev@simplexsolucoes.com.br` (id 1) aparecer na saída, PARE.** A guarda do console recusa
qualquer super admin que supervisione time — o id 1 perderia o `/super_admin` e ninguém mais
administraria a instalação. Remova a supervisão dele antes de subir, ou me avise para trocar a regra.

Se aparecer **outro administrador que precise manter tudo**, também pare: a regra derivada da
supervisão vai pegá-lo.

---

## Passo a passo

1. ~~**Rode o pré-voo acima.**~~ ✅ feito — gate livre, id 1 fora da lista.

2. ~~**Publique no staging.**~~ ✅ feito. O heap padrão dá **OOM** — precisa de `NODE_OPTIONS`, e
   nunca canalize o precompile para `tail` (mascara o exit code):
   ```bash
   cd /home/chatwoot/chatwoot
   RAILS_ENV=production NODE_OPTIONS='--max-old-space-size=8192' \
     bundle exec rake assets:precompile > build.log 2>&1; echo $?
   sudo /bin/systemctl restart chatwoot.target
   ```
   Conferido: `EXIT=0`, o grafo do manifest atual carrega o marcador de negação, `http=200` e
   `version.json` = `525f7f2ef`.

3. **Entre como o supervisor** (`sup@simplexsolucoes.com.br`) e **recarregue a aba** — a aba aberta
   segue com o bundle velho.

4. **Abra Configurações.** Espera: Atributos Personalizados, Robôs, Macros, Integrações e Fluxo de
   Conversa ausentes; Etiquetas, Automação, Respostas Prontas, Auditoria, SLA e Conexões WhatsApp
   no lugar.

5. **Abra o menu do perfil.** Espera: sem "Console de Super Admin".

6. **Digite as URLs na mão** — é aqui que o front sozinho falharia:
   ```
   /app/accounts/1/settings/custom-attributes/list
   /app/accounts/1/settings/agent-bots
   /app/accounts/1/settings/macros
   /app/accounts/1/settings/integrations
   /app/accounts/1/settings/conversation-workflow
   ```
   Espera: as cinco redirecionam ao dashboard.

7. **Abra `/super_admin` numa aba anônima** com o e-mail e senha do supervisor. Espera: volta ao
   login com "Invalid credentials". Com `dev@simplexsolucoes.com.br`, entra normal.

8. **Ainda como supervisor, abra uma conversa.** Espera: campos personalizados aparecem, macro
   executa pelo ⚡, atribuição e times normais, mídias normais.

9. **Prove a API** (o Chatwoot devolve **401**, não 403 — `render_unauthorized` usa `:unauthorized`):
   ```bash
   TOKEN=$(curl -s -X POST http://127.0.0.1:3000/auth/sign_in \
     -H "Content-Type: application/json" \
     -d '{"email":"sup@simplexsolucoes.com.br","password":"SENHA"}' \
     | python3 -c "import json,sys;print(json.load(sys.stdin)['data']['access_token'])")

   curl -s -o /dev/null -w "%{http_code} atributos POST\n" -X POST \
     -H "api_access_token: $TOKEN" \
     http://127.0.0.1:3000/api/v1/accounts/1/custom_attribute_definitions
   curl -s -o /dev/null -w "%{http_code} atributos GET\n" \
     -H "api_access_token: $TOKEN" \
     http://127.0.0.1:3000/api/v1/accounts/1/custom_attribute_definitions
   curl -s -o /dev/null -w "%{http_code} apps GET\n" \
     -H "api_access_token: $TOKEN" \
     http://127.0.0.1:3000/api/v1/accounts/1/integrations/apps
   ```
   Espera: `401` no POST, `200` nos dois GET.

10. **Repita com administrador comum e com agente.** Espera: administrador comum com os seis itens
    funcionando; agente igual a antes (com a ressalva de Macros, abaixo).

---

## Quatro desvios do .md original

1. **"Fluxo de conversa" não é o `flows_controller`.** Aquele controller é o canvas de **Automação**,
   que o .md manda manter. A tela `settings/conversationWorkflow` (Auto-resolução + Atributos
   obrigatórios) não tem controller próprio: grava em `account.settings` pelo mesmo
   `PATCH /accounts/:id` de "Conta". Por isso a negação é **por chave**.

2. **`integrations/apps#index` teve de continuar aberto.** O .md pedia para confirmar o Dyte antes de
   fechar: `VideoCallButton.vue` e `useLabelSuggestions.js` chamam `integrations/get` de dentro da
   conversa. A negação foi para onde a tela escreve (`HookPolicy`, `WebhookPolicy`, dashboard apps,
   Slack, OpenAI).

3. **O supervisor *agente* também perde Macros.** O .md assumia "para supervisor agente nada muda" —
   vale para cinco dos seis, mas Macros era visível a agentes. Mantive coerente. Se quiser poupar os
   ids 11 e 17, é uma linha em `macros.routes.js`.

4. **Status é 401, não 403.** `Pundit::NotAuthorizedError` → `render_unauthorized` → `:unauthorized`.

---

## Fora do recorte (não mexi)

- **Ninguém foi rebaixado.** `users.type` do id 14 continua `'SuperAdmin'`; a guarda no console
  entrega o pedido sem tocar em dado de produção.
- **Dois furos antigos ficaram abertos** (fechá-los mudaria o que agente comum pode fazer):
  qualquer agente ainda cria/apaga definição de atributo personalizado; `integrations/notion#destroy`
  e `shopify` não têm autorização nenhuma. Diga se quer que eu feche em separado.
- Nada de papel personalizado, coluna nova ou migration.
- A supervisão em si (isolamento de mensagens/conversas, alcance às conversas do time) está intacta.
- Nada foi para a frota — commit só na branch `nicolas`, sem push.

---

## Verificação já feita

| | |
|---|---|
| `spec/controllers/api/v1/accounts/supervisor_platform_settings_spec.rb` | 17 exemplos, 0 falhas |
| specs dos 5 controllers tocados + integrações + accounts | 179 exemplos, 18 falhas — **idênticas ao baseline HEAD** (locale pt-BR e `pending` desabilitado, pré-existentes) |
| vitest (composables + helpers + sidebar) | 1182 testes, 0 falhas |
| `rubocop` nos 16 arquivos Ruby / `eslint` nos 8 do front | limpos |
| policies contra os dados **reais** do staging (rails runner) | supervisor id 14: robôs/macros/hooks/webhooks `create=false`, `index=true`; `dev@` id 1: tudo `true`, console livre |

**Passos que ainda são seus** (preciso da senha do supervisor / de olhar a tela): 3 a 10.
