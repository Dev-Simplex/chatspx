# CHAT-155 — Caixa de entrada "somente leitura" com redirecionamento de resposta

**Origem:** https://gestao.spx.ia.br/workbench/spx/tracker/CHAT-155 (texto colado pelo Nicolas em 25/09/2026)
**Responsável:** Nicolas · **Repo:** chatspx · **Branch:** `feat/caixa-somente-leitura` a partir de `producao`

Este documento é para a IA implementar sem perguntar. Todas as decisões abaixo já foram tomadas
pelo Walisson. Onde surgir dúvida não prevista, siga a opção mais simples que cumpra o aceite e
registre a escolha no PR.

## 1. O problema do cliente

O cliente quer parar de atender por um número (uma caixa de entrada), mas os clientes dele ainda
mandam mensagem para esse número. Ele quer continuar recebendo, e nada pode sair por ele:
hoje o time responde pelo número antigo sem perceber.

## 2. O que construir

- Opção na caixa de entrada: **"Somente leitura"** (`read_only`). Ligada: a caixa recebe
  normalmente, e nenhuma mensagem sai por ela, nem de pessoa nem automática.
- Opção dependente: **"Redirecionar respostas para"** (`read_only_redirect_inbox_id`). Escolhe
  outra caixa de entrada.
- Na conversa de uma caixa somente leitura:
  - Sem redirecionamento: só leitura + nota interna.
  - Com redirecionamento: aparece o botão **"Responder pela caixa <nome>"**. O atendente escreve,
    envia, a mensagem sai pela caixa de destino para o mesmo cliente, e o atendente é levado
    para a conversa nova.

## 3. Decisões já tomadas (não reabrir)

| Tema | Decisão |
|---|---|
| Envio automático | Bloqueado também. IA (Captain), flows, automações, NPS/CSAT, saudação, ausência: nada sai pela caixa somente leitura. |
| Nota privada | Liberada. Não sai para o cliente. |
| Transferir / atribuir / trocar time | Bloqueado na interface para conversas dessa caixa. |
| Resolver conversa | Liberado (não envia nada e evita fila pendurada). |
| Destino fora da janela de 24h (WhatsApp oficial) | O botão pede template aprovado da caixa de destino. Dentro da janela, ou destino WAHA: texto livre. |
| Conversa original após redirecionar | Recebe nota privada "Respondido pela caixa <nome>, conversa #<id>" e é resolvida. |
| Quem liga a opção | Só administrador (mesma permissão das demais configurações de caixa). |
| Destinos permitidos | Caixa da mesma conta, diferente da origem, não somente leitura, e de WhatsApp (oficial `Channel::Whatsapp` ou WAHA). |

## 4. Mapa do código (conferido em producao, 25/09/2026)

- Toda mensagem de saída nasce como `Message` (`app/models/message.rb`). O envio acontece em
  `after_create_commit` → `send_reply` → `SendReplyJob`.
- **WAHA não passa pelo `SendReplyJob`.** Caixa WAHA é `Channel::Api`, e o `SendReplyJob`
  (`app/jobs/send_reply_job.rb`) mapeia `Channel::Api` para notificação por e-mail. O texto chega
  à WAHA pelo webhook da caixa API (`app/listeners/webhook_listener.rb:153`,
  `deliver_api_inbox_webhooks`) e mensagens especiais por `app/services/waha/outbound_special_message_service.rb`.
  Por isso o bloqueio NÃO pode ficar só no `SendReplyJob`: tem que impedir a `Message` de ser criada.
- Campanhas enviam sem criar `Message` antes: `app/services/whatsapp/oneoff_campaign_service.rb:83`
  (`channel.send_template`) e `app/services/campaigns/whatsapp/recipient_dispatch_service.rb`
  (usa `campaign.inbox`). Precisam de guarda própria (§5.3).
- Padrão de flag booleana na caixa a copiar: `team_message_isolation` (coluna em `inboxes`,
  permitida em `inbox_attributes` do `app/controllers/api/v1/accounts/inboxes_controller.rb:254`).

## 5. Backend

### 5.1 Migration

Timestamp com segundos reais (`date +%Y%m%d%H%M%S`), conferindo antes
`git ls-tree -r --name-only origin/producao db/migrate | sort | tail`. Nunca hora redonda.

```ruby
add_column :inboxes, :read_only, :boolean, default: false, null: false
add_reference :inboxes, :read_only_redirect_inbox, foreign_key: { to_table: :inboxes, on_delete: :nullify }, null: true
```

### 5.2 Model Inbox

- `belongs_to :read_only_redirect_inbox, class_name: 'Inbox', optional: true`
- Validação (só quando `read_only_redirect_inbox_id` presente): mesma `account_id`; diferente de
  `id`; destino não `read_only`; destino é WhatsApp (oficial ou WAHA). Para detectar WAHA,
  procure o helper já existente no projeto e reutilize; não crie um novo.
- Ao desligar `read_only`, limpar `read_only_redirect_inbox_id`.

### 5.3 O bloqueio (a parte que não pode falhar)

- **Rede de segurança no `Message`:** validação que recusa criar mensagem quando
  `inbox.read_only?` e `outgoing? || template?` e `!private?`. Mensagens `incoming` e `activity`
  passam sempre. Erro com chave i18n (en e pt_BR): "Esta caixa de entrada está em modo somente leitura."
- **Saídas explícitas nos automáticos**, para não virar erro no GlitchTip a cada tentativa. Em cada
  ponto que cria mensagem de saída, retornar cedo se a caixa for somente leitura. Levante a lista
  com `rg -n "messages.create|Message.create|messages.build" app enterprise` e cubra no mínimo:
  Captain (resposta da IA), flows (ações de envio), automações (ação enviar mensagem), NPS, CSAT,
  saudação e ausência. Procure nas duas árvores (app e enterprise): o Captain mora no overlay.
- **Campanhas:** validação em `Campaign` recusando caixa somente leitura, e retorno cedo no
  `recipient_dispatch_service.rb` e no `oneoff_campaign_service.rb` se a caixa virar somente
  leitura com campanha em andamento.
- **Strong params:** acrescentar `:read_only` e `:read_only_redirect_inbox_id` ao `inbox_attributes`.
  A tela de caixa usa multipart/FormData; campo de lista se perde em silêncio nesse caminho, mas
  estes dois são escalares. Confirme gravando e relendo pela API.

### 5.4 Endpoint de redirecionamento

`POST /api/v1/accounts/:account_id/conversations/:conversation_id/redirect_reply`

Corpo: `{ "content": "..." }` ou `{ "template_params": { ... } }` (mesmo formato que o composer
já usa para template de WhatsApp; reutilize, não invente).

Fluxo, numa transação:

1. Recusar (422) se a caixa da conversa não é `read_only` ou não tem destino.
2. Autorização: o usuário precisa ter acesso às duas caixas.
3. Contato: usar o `phone_number` do contato; sem telefone, 422 "Contato sem telefone".
4. Achar ou criar o `ContactInbox` do contato na caixa de destino.
5. Achar conversa aberta do contato na caixa de destino; se não houver, criar. Busca explícita
   antes (o `ConversationBuilder` pelo caminho da API não verifica conversa aberta e duplicaria).
6. Janela de 24h (destino WhatsApp oficial): se a conversa de destino não pode receber texto livre
   e veio `content`, responder 422 com `{ "requires_template": true }`. Ao checar a janela, use
   `all_messages` e não `messages` (este é filtrado por time e fecha a janela errado).
7. Criar a mensagem de saída na conversa de destino (texto ou template).
8. Na conversa original: nota privada "Respondido pela caixa <nome>, conversa #<display_id>" e resolver.
9. Responder `{ "conversation_id": <display_id da conversa de destino> }`.

## 6. Frontend

Vue 3 `<script setup>`, `components-next/`, Tailwind puro, tema escuro, textos em en e pt_BR,
nunca hardcodar nome de marca.

- **Configurações da caixa** (ao lado das opções de isolamento): interruptor "Somente leitura" com
  ajuda "A caixa continua recebendo, mas nenhuma mensagem sai por ela, nem automática." Ligado,
  aparece o seletor "Redirecionar respostas para" listando só caixas válidas (§3), com "Nenhuma".
- **Conversa de caixa somente leitura:**
  - Faixa no topo: "Caixa somente leitura: respostas não saem por este número."
  - Composer só no modo nota privada; aba de resposta desabilitada.
  - Esconder atribuir agente, trocar time e transferir. Manter resolver e etiquetas.
  - Com destino: botão "Responder pela caixa <nome>" abre modal com campo de texto. Se o backend
    devolver `requires_template`, o modal troca para o seletor de template da caixa de destino
    (reutilizar o componente de template que o composer já usa).
  - Enviado: navegar para a conversa devolvida.
- **Campanhas:** não oferecer caixa somente leitura como origem de campanha.

## 7. Critérios de aceite (testar na homologação)

1. Ligar "Somente leitura" numa caixa: mensagem do cliente continua chegando.
2. Tentar responder: não há como pela tela; pela API (`POST .../messages` com `message_type: outgoing`) volta 422.
3. Nota privada funciona.
4. Com IA ligada na caixa, cliente manda mensagem: a IA não responde e nada aparece no GlitchTip.
5. Flow que envia mensagem, NPS e saudação: nada sai.
6. Com destino configurado (WAHA): botão envia pela caixa de destino, cliente recebe do número novo,
   conversa original fica resolvida com a nota.
7. Destino oficial fora das 24h: o modal pede template; enviar template funciona.
8. Desligar "Somente leitura": tudo volta ao normal e o destino é limpo.
9. Mandar de novo pelo redirecionamento para o mesmo cliente: reaproveita a conversa aberta no destino.

## 8. Testes automatizados

Spec só para: a validação do `Message` (bloqueia outgoing/template, libera incoming, activity e
nota privada) e o endpoint `redirect_reply` (caminho feliz, sem destino, sem telefone, reaproveita
conversa aberta). Não rode dois rspec ao mesmo tempo: compartilham o banco de teste.

## 9. Fora de escopo

Bloquear recebimento · redirecionamento automático sem ação do atendente · outros canais que não
WhatsApp · mudar comportamento de caixas que não estão em somente leitura.
