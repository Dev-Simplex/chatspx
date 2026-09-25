# S-03: para cada contato da busca, a OUTRA ficha que responde pelo mesmo numero -- o mesmo telefone
# (com ou sem o 9o digito) ou o vinculo WhatsApp de uma ficha cujo telefone foi digitado errado,
# como as duas "Juliana" da S-02. Devolve { contact_id => id_da_outra_ficha }.
class Contacts::DuplicateFinder
  pattr_initialize [:account!, :contacts!]

  def perform
    keys = contacts.index_with { |contact| numbers_of(contact) }
    all = keys.values.flatten.uniq
    return {} if all.empty?

    holders = holders_by_number(all)
    keys.each_with_object({}) do |(contact, numbers), duplicates|
      other = numbers.flat_map { |number| holders[number] }.compact.find { |id| id != contact.id }
      duplicates[contact.id] = other if other
    end
  end

  private

  def numbers_of(contact)
    own = source_ids[contact.id] || []
    phone = contact.phone_number&.delete('+')
    phone.present? ? (normalizer.variants(phone) + own).uniq : own
  end

  # Vinculos WhatsApp (so digitos) das fichas da busca.
  def source_ids
    @source_ids ||= ContactInbox.where(contact_id: contacts.map(&:id)).where("source_id ~ '^[0-9]+$'")
                                .pluck(:contact_id, :source_id)
                                .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
  end

  def holders_by_number(numbers)
    by_phone = account.contacts.where(phone_number: numbers.map { |n| "+#{n}" })
                      .pluck(:phone_number, :id).map { |phone, id| [phone.delete('+'), id] }
    by_source = ContactInbox.joins(:inbox).where(inboxes: { account_id: account.id }, source_id: numbers)
                            .pluck(:source_id, :contact_id)
    (by_phone + by_source).group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
  end

  def normalizer
    @normalizer ||= Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new
  end
end
