# SUG-02: Formulário público de sugestões (`/sugestoes`)

**Responsável:** Nicolas Silva
**Origem:** pedido do dono em 28/09/2026. Mockup aprovado: https://nicolas.chatspx.app/caixa-de-sugestoes.html (aba **B**; cópia em `task-chat spx/SUG-01-mockup-caixa-de-sugestoes.html`).
**Parte 2 de 2. Pré-requisito: a SUG-01 mergeada na `producao`.** Essa parte traz a tabela `suggestions`, o modelo `Suggestion` e o painel do Super Admin.
**Branch:** sair de `producao` **depois** do merge da SUG-01. **Não** empilhe sobre a branch da SUG-01: PR empilhado acaba mergeado na base errada. Antes de abrir o PR, confira o `baseRefName`.
1 PR, Conventional Commits. Rodar `bundle exec rubocop -a` e `pnpm eslint`.
**Fluxo:** staging nicolas → validar → PR. Não deployar na frota.

---

| | |
|---|---|
| Tipo | FEATURE |
| Valor | Um link estilo Google Forms para mandar por WhatsApp ou e-mail. Qualquer pessoa, mesmo sem login, manda nome, empresa, sugestão e foto/vídeo. A sugestão cai no mesmo painel do Super Admin, marcada como **Link**. |
| Já existe? | A tabela, o modelo, a validação do anexo e o painel vêm da SUG-01. Esta parte é só a página pública e a sua API. |
| Esforço | pequeno/médio: 2 controllers, 1 view, 1 app Vue enxuto e 1 regra de throttle. **Sem migration.** |
| Obrigatório | **Responsivo, no celular (~375px) e no notebook (1366px).** É o caso principal, porque o link é aberto pelo WhatsApp. |

---

## Requisitos aprovados

1. Página `/sugestoes`, **sem login**.
   - Campos: **nome\***, **empresa\***, **sugestão\*** e **foto ou vídeo** (opcional, até 100 MB).
   - Depois do envio mostra a tela **"Obrigado!"** com o botão "Enviar outra".
   - **Celular:** ocupa a largura toda. **Notebook:** um cartão central com `max-w-xl`.
   - Cabeçalho com o logo e o nome da instalação (`globalConfig`).
2. A sugestão é gravada com `source: :public_link` e **sem conta nem usuário**. Aparece no Super Admin com a origem **Link**, e o filtro "Do link" passa a mostrar resultados.
3. Anti-spam sem captcha: um campo honeypot e um limite de envios por IP.
4. A página não pode expor nenhum dado de conta ou de usuário.

---

## Implementação

Use o molde do CSAT: `app/controllers/survey/responses_controller.rb`, `app/views/survey/responses/show.html.erb` e `app/javascript/entrypoints/survey.js`.

### 1. Página HTML
- **Rota:** `get 'sugestoes', to: 'suggestions#new'` → `app/controllers/suggestions_controller.rb` (`< ActionController::Base`, com `set_global_config` igual ao do survey).
- **View** `app/views/suggestions/new.html.erb`:
  - Copie o `survey/responses/show.html.erb`, trocando para `vite_javascript_tag 'suggestions'`.
  - Mantenha `<meta name="viewport" content="width=device-width, initial-scale=1">`.
  - Acrescente `<meta name="robots" content="noindex">`.

### 2. App Vue
A entry `app/javascript/entrypoints/suggestions.js` monta o `app/javascript/suggestions/App.vue`. É um app enxuto: `<script setup>`, Tailwind, vue-i18n, **sem store**, e o POST sai por `axios` com `FormData`.
- Campos: nome (`autocomplete="name"`), empresa (`autocomplete="organization"`), sugestão e arquivo com `accept="image/*,video/*"`.
- Honeypot `website`: escondido com `class="hidden"`, `tabindex="-1"` e `autocomplete="off"`.
- Faça a validação no cliente antes do envio: os 3 obrigatórios e o anexo com até 100 MB.
- Mostre o progresso do upload no botão (`onUploadProgress`), porque vídeo no 4G demora. Desabilite o botão enquanto o envio estiver em andamento.
- Estado de sucesso: "Obrigado!" + "Enviar outra" (limpa o form).
- Em caso de erro, mostre a mensagem do 422, ou "Muitos envios, tente daqui a alguns minutos" no 429.
- Responsivo: `min-h-screen`, e o form com `w-full max-w-xl mx-auto px-4`. No notebook o cartão ganha borda e sombra; no celular fica sem cartão. Em 375px não pode haver rolagem lateral.

### 3. API pública
- **Rota:** em `namespace :public` (routes.rb ~l.520), crie `resources :suggestions, only: [:create]` → `app/controllers/public/api/v1/suggestions_controller.rb` (`< PublicController`).
- **Honeypot:** se `params[:website].present?`, responda `head :ok` sem gravar.
- Grava com `Suggestion.create(source: :public_link, name:, company:, content:, media:)` e sem conta.
- Em caso de erro, `422` com as mensagens do modelo. A validação do anexo vem da SUG-01.

### 4. Throttle
- Em `config/initializers/rack_attack.rb`, acrescente `throttle('suggestions/ip', limit: 5, period: 10.minutes)` para `POST /public/api/v1/suggestions`.
- Confira se o rack-attack está ligado nas VMs (`ENABLE_RACK_ATTACK`). Se não estiver, anote no PR; **não** crie um limitador próprio.

### 5. i18n
- As chaves do app público ficam num arquivo próprio em `app/javascript/suggestions/i18n/`, no molde de `app/javascript/survey/i18n/`, em `en` e `pt_BR`. **Nenhuma string solta.**

---

## Como validar (staging nicolas)

1. Abra `https://nicolas.chatspx.app/sugestoes` em **aba anônima** no **notebook (1366px)**. O cartão fica centralizado, com o logo no topo.
2. Enviar vazio mostra o erro nos 3 campos obrigatórios. Um `.pdf` é recusado.
3. Faça um envio completo com um **vídeo de ~30 MB**: aparece o progresso e depois o "Obrigado!". "Enviar outra" limpa o form.
4. **Celular de verdade**: abra o link a partir de uma mensagem no WhatsApp. Confira que não há rolagem lateral, que o teclado não esconde o botão e que o anexo pela galeria funciona.
5. Honeypot: `curl -F website=x -F name=a -F company=b -F content=c https://nicolas.chatspx.app/public/api/v1/suggestions` devolve 200 e **não** grava.
6. Throttle: o 6º POST em 10 min pelo mesmo IP leva 429 (se o rack-attack estiver ligado).
7. **Super Admin → Sugestões:** os envios do passo 3 aparecem com a origem **Link**, sem conta, e o anexo abre. O filtro "Do link" funciona.
8. Rode `bundle exec rspec` nos specs novos e confira `rubocop` e `eslint` limpos.

## Specs (mínimos)
- `spec/controllers/public/api/v1/suggestions_controller_spec.rb`: `create` ok, honeypot sem gravar e 422 sem os obrigatórios.
- Use `POSTGRES_DATABASE=chatwoot_test_promover`, porque o banco de teste é compartilhado com outras sessões.

## Cuidados
- `/sugestoes` é público: não exponha nada de conta nem de usuário. Não crie nenhum endpoint de leitura público.
- Sem migration: dá para subir sem esperar a janela das 20:00, **desde que** a SUG-01 já esteja no ar na VM. Isso não é para esta task (o ciclo para no PR).
- Frontend novo na frota: a entry `suggestions` precisa entrar no build. Siga a regra de construir na .229 e provar por HTTP.
