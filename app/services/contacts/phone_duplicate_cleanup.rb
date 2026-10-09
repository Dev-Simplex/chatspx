# frozen_string_literal: true

# SUP-1415: fichas com o MESMO telefone na mesma conta (duas gravacoes simultaneas criaram as duas no mesmo segundo).
# Precisam sumir antes do indice unico `uniq_phone_number_per_account_contact`, senao a migration falha.
#
# Em cada grupo fica UMA ficha (a base): a que tem mais conversas; no empate, a mais antiga.
#   - extra vazia (sem conversa, sem caixa, sem mensagem) -> apagada
#   - extra com historico -> mesclagem nativa (ContactMergeAction): conversas, mensagens, caixas, notas, NPS e CSAT
#     vao para a base; a base mantem os proprios dados e herda so o que nao tinha.
# Com `apply: false` (padrao) so descreve o que faria. Com `apply: true` grava um backup JSON por grupo antes.
class Contacts::PhoneDuplicateCleanup
  Group = Struct.new(:account_id, :phone, :base, :to_delete, :to_merge, keyword_init: true)

  def initialize(account_id: nil, apply: false, backup_dir: nil, io: $stdout)
    @account_id = account_id
    @apply = apply
    @backup_dir = backup_dir
    @io = io
  end

  def perform
    groups = duplicate_keys.map { |(account_id, phone)| build_group(account_id, phone) }
    @io.puts "#{@apply ? 'APLICANDO' : 'SIMULANDO (nada muda)'}: #{groups.size} grupo(s) com telefone repetido"
    groups.each do |group|
      describe(group)
      apply(group) if @apply
    end
    groups
  end

  private

  def duplicate_keys
    scope = Contact.where.not(phone_number: [nil, ''])
    scope = scope.where(account_id: @account_id) if @account_id.present?
    scope.group(:account_id, :phone_number).having('COUNT(*) > 1').count.keys
  end

  def build_group(account_id, phone)
    fichas = Contact.where(account_id: account_id, phone_number: phone).order(:id).to_a
    conversations = Conversation.where(contact_id: fichas.map(&:id)).group(:contact_id).count
    base = fichas.max_by { |contact| [conversations[contact.id].to_i, -contact.id] }
    extras = fichas - [base]
    to_delete, to_merge = extras.partition { |contact| empty?(contact) }
    Group.new(account_id: account_id, phone: phone, base: base, to_delete: to_delete, to_merge: to_merge)
  end

  def empty?(contact)
    !Conversation.exists?(contact_id: contact.id) && !ContactInbox.exists?(contact_id: contact.id) &&
      !Message.exists?(sender: contact)
  end

  def describe(group)
    @io.puts "conta #{group.account_id} #{group.phone}: fica ##{group.base.id} \"#{group.base.name}\""
    group.to_delete.each { |contact| @io.puts "  apagar (vazia) ##{contact.id} \"#{contact.name}\"" }
    group.to_merge.each { |contact| @io.puts "  mesclar na ##{group.base.id}: ##{contact.id} \"#{contact.name}\"" }
  end

  def apply(group)
    write_backup(group)
    group.to_delete.each(&:destroy!)
    account = Account.find(group.account_id)
    group.to_merge.each do |contact|
      ContactMergeAction.new(account: account, base_contact: group.base.reload, mergee_contact: contact).perform
    end
  end

  def write_backup(group)
    FileUtils.mkdir_p(@backup_dir)
    payload = { base: group.base.attributes, extras: (group.to_delete + group.to_merge).map { |c| backup_of(c) },
                gravado_em: Time.current.iso8601 }
    File.write(File.join(@backup_dir, "#{group.account_id}-#{group.base.id}.json"), JSON.pretty_generate(payload))
  end

  # Tudo que a mesclagem move ou apaga, para reconstruir a ficha a mao se preciso.
  def backup_of(contact)
    {
      contact: contact.attributes,
      conversation_ids: Conversation.where(contact_id: contact.id).pluck(:id),
      contact_inbox_ids: ContactInbox.where(contact_id: contact.id).pluck(:id),
      note_ids: Note.where(contact_id: contact.id).pluck(:id),
      nps_response_ids: NpsResponse.where(contact_id: contact.id).pluck(:id),
      csat_survey_response_ids: CsatSurveyResponse.where(contact_id: contact.id).pluck(:id),
      message_ids: Message.where(sender: contact).pluck(:id)
    }
  end
end
