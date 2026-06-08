# Backlog — Reconciliador de incoming: preferir a conversa certa em ficha duplicada (9º dígito)

> **Status:** proposto (defensivo). **Prioridade:** baixa — o problema já está mitigado por outras 2 frentes; isto é cinto-e-suspensório.
> **Origem:** investigação do "reply órfão" dos disparos Tozi (2026-06-08).

## Contexto

Números brasileiros têm duas formas no WhatsApp: **12 dígitos** (55+DDD+8, legado) e **13 dígitos** (55+DDD+9+8, atual). Quando o mesmo contato tem **2 fichas** (`ContactInbox`) — uma em cada forma — o incoming pode cair na ficha errada.

O serviço `Whatsapp::PhoneNumberNormalizationService#normalize_and_find_contact_by_provider` já tenta todas as variantes (`BrazilPhoneNormalizer#variants` → `[waid, with_nine, without_nine]`), **mas retorna a PRIMEIRA ficha que existir na ordem das variantes**. Se houver 2 fichas, ele pega a primeira que casar — que pode ser a "errada" (a antiga/sem a conversa ativa), e o reply do lead vai parar lá.

```ruby
# app/services/whatsapp/phone_number_normalization_service.rb (atual)
normalizer.variants(clean_number).each do |variant|
  existing = find_existing_contact_inbox(format_for_provider(variant, provider))
  return existing.source_id if existing   # <- primeira que casar
end
```

## Por que NÃO é urgente

O cenário só ocorre se um contato tiver 2 fichas. Hoje isso está coberto por:
1. **Consolidação 2026-06-08** — os 275 contatos que tinham ficha duplicada foram fundidos em 1 ficha cada (`scripts/spx/tozi/consolida_conversas_duplicadas.rb`).
2. **Frente-1 do `DisparoLeadJob`** (`resolved_source_id` + `find_or_create_conversation`) — o disparo agora reusa a ficha/conversa existente, **não cria mais duplicata**.

Ou seja, a fonte de novas duplicatas foi fechada. Este item só importa se uma duplicata surgir por **outro** caminho (outra integração criando ficha, import, etc.).

## Proposta

Quando **mais de uma** ficha casar as variantes, **escolher a da conversa mais recente** (a "thread viva"), em vez da primeira variante.

```ruby
def normalize_and_find_contact_by_provider(raw_number, provider)
  clean_number = extract_clean_number(raw_number, provider)
  normalizer = find_normalizer_for_country(clean_number)
  return raw_number unless normalizer

  matches = normalizer.variants(clean_number).filter_map do |variant|
    find_existing_contact_inbox(format_for_provider(variant, provider))
  end.uniq

  return raw_number if matches.empty?
  return matches.first.source_id if matches.one?   # caso comum: 1 ficha, comportamento idêntico ao atual

  # 2+ fichas: roteia pra ficha da conversa mais recente (thread viva)
  best = matches.max_by do |ci|
    ci.conversations.maximum(:created_at) || ci.created_at
  end
  best.source_id
end
```

- **Caso comum (1 ficha, 99%+):** `matches.one?` → idêntico ao atual. **Zero risco** no fluxo normal.
- **2+ fichas:** prefere a conversa mais nova → o reply cai na thread certa.

## Considerações
- Camada **OSS** (`app/services/whatsapp/`), **sem override no Enterprise** — editar direto.
- Tem specs: `spec/services/whatsapp/phone_number_normalization_service_spec.rb` — adicionar caso "2 fichas → conversa mais recente" e rodar a suite.
- É **hot-path** (todo incoming WhatsApp passa aqui) → testar bem; o early-return em `matches.one?` preserva o caminho quente.

## Esforço
~1 método + 1 spec. Pequeno. Só não é prioridade porque as 2 frentes acima já seguram o caso real.
