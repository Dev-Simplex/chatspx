class Captain::Tools::Copilot::AddNoteToContactService < Captain::Tools::BaseTool
  def self.name
    'add_note_to_contact'
  end
  description 'Add a note to a contact'

  param :contact_id, type: :integer, desc: 'ID of the contact', required: true
  param :content, type: :string, desc: 'Note content', required: true

  def execute(contact_id:, content:)
    contact = Contact.find_by(id: contact_id, account_id: @assistant.account_id)
    return 'Contact not found' if contact.nil?

    note = contact.notes.create!(content: content, account: @assistant.account, user: @user)
    "Note added to contact '#{contact.name}' (##{contact_id}), note id: #{note.id}"
  end

  def active?
    user_has_permission('contact_manage')
  end
end
