# frozen_string_literal: true

# rake spx:contact_inbox_colisoes       # todas as contas
# rake spx:contact_inbox_colisoes[6]    # so a conta 6
#
# SO LEITURA. Lista as fichas que nao conseguem mais receber mensagem numa caixa WhatsApp Cloud porque
# o numero delas (telefone sem '+') ja e o source_id do vinculo de OUTRA ficha na mesma caixa (S-02).
# O "Nova conversa" para a ficha travada responde 422 contact_inbox_conflict; destrava mesclando as duas.
namespace :spx do
  desc 'Lista fichas travadas por vinculo WhatsApp Cloud de outra ficha (so leitura)'
  task :contact_inbox_colisoes, %i[account_id] => :environment do |_t, args|
    pares = ContactInbox.joins(:inbox).where(inboxes: { channel_type: 'Channel::Whatsapp' })
                        .joins("JOIN contacts travada ON travada.account_id = inboxes.account_id
                                AND replace(travada.phone_number, '+', '') = contact_inboxes.source_id
                                AND travada.id <> contact_inboxes.contact_id")
    pares = pares.where(inboxes: { account_id: args[:account_id].to_i }) if args[:account_id].present?
    linhas = pares.pluck('inboxes.account_id', 'inboxes.id', 'contact_inboxes.source_id', 'contact_inboxes.contact_id', 'travada.id')

    linhas.each do |conta, caixa, numero, dona, travada|
      puts "conta #{conta} caixa #{caixa} numero #{numero}: ficha #{travada} travada, vinculo esta na ficha #{dona}"
    end
    puts "#{linhas.size} colisao(oes)"
  end
end
