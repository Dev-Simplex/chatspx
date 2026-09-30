# Suporte — "Falha ao enviar" num template

A janela de 24 h fechou, o atendente mandou um template e a mensagem voltou em
vermelho. Quase sempre é a mesma coisa.

Página: https://nicolas.chatspx.app/suporte-template-falha-ao-enviar.html

---

## 1. Confirme que é o caso comum

Olhe o **texto da mensagem vermelha**:

- Como deveria sair: `Olá João, Boa tarde! como vai?`
- Como apareceu: `Olá * *, Boa tarde! como vai?`

Dois asteriscos com um espaço no meio = a variável do template foi preenchida
com espaço. É isso.

Se o texto estiver normal, é outro erro: peça um print com **o mouse parado em
cima do triângulo ⚠** e veja a tabela no fim.

## 2. Resolva agora

O atendente abre a conversa, clica em **Enviar Template**, escolhe o mesmo
template e preenche a variável com **o primeiro nome do contato**. Entrega na hora.

O botão ↻ da mensagem vermelha **não resolve** — reenvia o mesmo conteúdo quebrado.

Passo a passo com as telas, para mandar direto ao cliente:
https://nicolas.chatspx.app/enviar-template-passo-a-passo.html

## 3. Evite que volte a acontecer

Mensagem pronta para o cliente:

> Oi! Achamos o motivo: no template, o campo do nome foi preenchido com um espaço
> em branco, e o WhatsApp recusa a mensagem quando isso acontece. É só reenviar o
> template com o nome do contato preenchido que ela vai normalmente.
>
> Para quando vocês não souberem o nome da pessoa, vale aprovar no WhatsApp
> Manager uma segunda versão da saudação **sem nenhum campo de nome** — por
> exemplo "Olá! Boa tarde, como vai?". Aí é só escolher essa e não precisa
> preencher nada.

---

# Detalhes técnicos

## Se o erro for outro

O triângulo ⚠ tem balão de hover com o erro cru da Meta.

| Erro | O que fazer |
|---|---|
| `132000` | Contagem de parâmetros — é o caso acima. |
| `Template not found or invalid template name` | Erro **nosso**, nem chegou na Meta. Ressincronizar os templates da inbox. |
| `132001` | Nome ou idioma não batem com o aprovado. Ressincronizar. |
| `132015` | Template pausado por qualidade. Usar outro. |
| `131047` | Template não elegível fora da janela. |
| `190` | Access token da inbox expirado. Renovar credencial. |

O botão ↻ some 24 h depois da mensagem.

## Por que quebra

O painel valida a variável por verdade simples
(`app/javascript/dashboard/helper/templateHelper.js:18`), e `" "` passa. O backend
trata espaço como vazio — `" ".blank?` é `true` no Rails — e **descarta o parâmetro
em silêncio** (`app/services/whatsapp/template_processor_service.rb:83`). A Meta
recebe um template que espera 1 parâmetro e chega 0, e rejeita com 132000.

**Defeito irmão, mais grave:** com duas variáveis e só a primeira em branco, o
descarte **desloca a posição** — a Meta aceita e o cliente recebe o texto trocado,
sem erro nenhum. Procure por isso quando disserem "chegou a mensagem errada".

## Se precisar do banco

Suporte não entra em máquina de cliente. Mande o comando e peça a saída colada.

```ruby
# bundle exec rails runner
Message.uncached do
  Conversation.find_by(display_id: <nº>, account_id: <conta>)
    .messages.where(status: :failed).last(5).each do |m|
      puts "#{m.id} #{m.created_at} #{m.external_error.inspect}"
      pp m.additional_attributes&.dig('template_params')
    end
end
```

`uncached` é obrigatório — o query cache do `rails runner` devolve dado velho.

## Correções pendentes de PR

1. Validar com `trim` no painel, para barrar o espaço na hora.
2. Parar de descartar parâmetro em branco no backend — resolve também o
   deslocamento silencioso de posição.
3. Pré-preencher a variável com o primeiro nome do contato.

Arquivos: `templateHelper.js:18` · `WhatsAppTemplateParser.vue` ·
`MessageError.vue` · `template_processor_service.rb:83` ·
`send_on_whatsapp_service.rb` · `providers/base_service.rb`
