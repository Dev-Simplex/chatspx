# BRIEFING DE IMPLEMENTAÇÃO — Grupos de WhatsApp (F0 + F1 + Integrantes)

> **Todo worker deve ler este arquivo antes da primeira linha de código.**
> Data: 2026-07-27 · VM: 192.168.8.232 (homologação) · Branch: `homologacao`
> Aprovado por Walisson a partir do mockup em `chatspx.app/mockups/grupos-waha.html`

---

## 1. O que estamos construindo

Conversas de grupo de WhatsApp (inbox WAHA) hoje mostram
`👥 *Rogerio José Da Silva (229480102662169@lid)*` **dentro do texto da mensagem**, e não existe
lista de integrantes. A causa está diagnosticada: a app `chatwoot` que roda dentro da WAHA
concatena o identificador ao nome e injeta no corpo. Ver `SINTESE.md` nesta pasta.

**Escopo desta rodada — tudo SEM migration, tudo reversível:**

| | Entrega |
|---|---|
| **F0** | Extrair o autor do texto na ingestão e limpar o `content` |
| **F1** | Autor estruturado na bolha (nome + avatar + cor) e freios que faltam (CSAT/NPS/IA) |
| **Integrantes** | Sync dos participantes via WAHA → snapshot na conversa → painel lateral e cabeçalho |

**FORA de escopo (não faça):** qualquer migration; coluna nova; tabela nova; consolidação das
conversas duplicadas do mesmo grupo; participante virando `Contact`. Isso é F2/F3 e depende de
decisão de produto ainda não tomada.

---

## 2. Contratos travados — NÃO invente formato

O coordenador já implementou e validou os dois itens compartilhados abaixo. **Consuma, não
reescreva, não duplique.**

### C1 — `Conversation#group?` (PRONTO)

`app/models/conversation.rb` — ponto único de verdade sobre "isto é um grupo?".
Validado contra dado real (conversa 12 = `true`, conversa 8 = `false`).

```ruby
conversation.group?  # => true | false
```

**Todo guard novo pergunta aqui.** Nunca reimplemente a heurística de `@g.us`.

### C2 — `content_attributes['group_sender']` (a criar por W1, consumido por W4/W5)

Gravado na ingestão de mensagem de grupo. Shape exato:

```ruby
{
  'group_sender' => {
    'name'  => 'Rogerio José Da Silva',  # String | nil
    'lid'   => '229480102662169',        # String | nil — SÓ DÍGITOS, sem "@lid"
    'phone' => '5566999991234'           # String | nil — E.164 sem "+", nil se não resolveu
  }
}
```

Regras: chaves sempre presentes (valor `nil` quando desconhecido); `content` fica **só com o texto
da mensagem**, sem o prefixo `👥 *…*`.

### C3 — `conversation.additional_attributes['waha_group']` (a criar por W3, consumido por W5)

Snapshot dos integrantes. **Não é migration** — a coluna jsonb já existe.

```ruby
{
  'waha_group' => {
    'participants' => [
      { 'lid' => '229480102662169', 'phone' => '5566999991234',
        'name' => 'Rogerio José Da Silva', 'admin' => true }
    ],
    'count'     => 12,
    'synced_at' => '2026-07-27T14:00:00Z'   # iso8601
  }
}
```

`name` pode ser `nil` (o engine GOWS devolve `DisplayName` vazio). `phone` sem `+`.

### C4 — `whatsappGroupHelper.js` (PRONTO)

`app/javascript/dashboard/helper/whatsappGroupHelper.js` — helper de front já criado, com ESLint
limpo e comportamento verificado contra os dados reais. **W4 e W5 importam daqui.** Exporta:

```js
authorColor(sender, isDark)      // cor determinística por identidade estável (lid > phone > name)
authorInitials(name)             // "Rogerio José Da Silva" -> "RS"
stripGroupSuffix(name)           // "TI TOZI - Inovação (GROUP)" -> "TI TOZI - Inovação"
parseLegacyGroupContent(content) // { content, sender } — saneia o histórico já gravado
participantLabel(sender)         // { label, isUnknown } — nunca devolve o LID
formatPhone(phone)               // "5566999991234" -> "+55 66 9 9999-1234"
AUTHOR_PALETTE, UNKNOWN_AUTHOR_COLOR
```

Se precisar de algo novo nesse arquivo, **avise o coordenador por `ask`** em vez de editar — os
dois workers de front dependem dele e uma edição concorrente quebra o outro.

---

## 3. Regras invioláveis

1. **O identificador técnico (LID) NUNCA aparece na interface.** Nem no corpo, nem em tooltip, nem
   em `title`, nem em `alt`. Se precisar dele para debug, use `data-*` no DOM.
2. **Conversa 1:1 não pode mudar em nada.** Tudo é condicionado a `conversation.group?`. Uma
   regressão em 1:1 é muito pior que o bug que estamos consertando.
3. **Sem migration, sem coluna nova, sem tabela nova.** Se você concluir que é impossível sem
   migration, **pare e use `ask`** — não crie a migration por conta própria.
4. **Não commite.** Deixe tudo no working tree. O coordenador revisa, testa e commita no fim.
5. **Não rode build de produção** (`assets:precompile`) nem reinicie serviço. O coordenador cuida.
6. **Blindagem de produção:** trabalhe só nesta VM. Zero SSH para outras VMs (.109 Tozi PROD, .229,
   fábrica). Contra a WAHA, **somente GET** — nunca enviar mensagem, nunca alterar sessão/grupo.
7. **Não altere os arquivos de outro worker.** A tabela de propriedade está na sua task. Se precisar
   de mudança em arquivo alheio, use `ask` ao coordenador.
8. **Idioma:** pt-BR é a prioridade do produto; `en` também deve ser preenchido. Comentários de
   código em pt-BR, seguindo o padrão do arquivo que você está editando.

---

## 4. Qualidade — o que será cobrado no fim

- **Ruby:** `bundle exec rubocop <arquivos>` limpo. Specs em `spec/` para o que você criou,
  rodando verde com `bundle exec rspec <arquivo>`.
- **JS/Vue:** `npx eslint <arquivos>` limpo. Se houver spec de front no padrão do repo
  (`*.spec.js` com vitest), acrescente.
- **Teste com o dado REAL, não só com fixture inventada.** A base local tem 548 mensagens no
  formato antigo e conversas de grupo de verdade — use `RAILS_ENV=production bundle exec rails
  runner` (somente leitura) para conferir que seu código lida com elas.
- **Honestidade no relatório:** se algo ficou pela metade ou você não conseguiu testar, diga.
  Relatório otimista que não bate com o código custa muito mais caro depois.

---

## 5. Dados reais para testar

```
Conversa de grupo: id 12 — contato "Sentinela Monitoramento (GROUP)"
Grupo do dump:     "TI TOZI - Inovação (GROUP)", contato id 24, account_id 3,
                   identifier 5566*****1379-1634750731@g.us
Inboxes WAHA:      17 (spx, 420 msgs), 43 (simplexteste, 98), 42 (16), 41 (8)
WAHA:              WAHA_API_URL / WAHA_API_KEY no .env — v2026.4.2, engine GOWS, tier PLUS
                   Sessão WORKING: "Simplex". Mapa LID->PN com 2757 entradas.
Exemplo de content legado:
  "👥 *‎Rogerio José Da Silva (229480102662169@lid)*\n\nQual Wi-Fi está?"
  (atenção ao U+200E invisível antes do nome — o helper já trata)
```

---

## 6. Ao terminar

Escreva um relatório curto em `plano/pesquisa-grupos-waha/relatos/<seu-id>.md` com: o que mudou
(arquivo:linha), como testou, o que ficou de fora, e riscos que o coordenador precisa saber.
Depois envie `worker_done` conforme o preâmbulo do seu dispatch, com `filesModified` correto.
