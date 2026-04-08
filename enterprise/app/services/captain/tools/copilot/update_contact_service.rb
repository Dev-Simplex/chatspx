class Captain::Tools::Copilot::UpdateContactService < Captain::Tools::BaseTool
  def self.name
    'update_contact'
  end
  description 'Update contact information (name, email, phone, company)'

  param :contact_id, type: :integer, desc: 'ID of the contact to update', required: true
  param :name, type: :string, desc: 'New name for the contact'
  param :email, type: :string, desc: 'New email for the contact'
  param :phone_number, type: :string, desc: 'New phone number for the contact'
  param :company_name, type: :string, desc: 'New company name for the contact'

  def execute(contact_id:, name: nil, email: nil, phone_number: nil, company_name: nil)
    contact = Contact.find_by(id: contact_id, account_id: @assistant.account_id)
    return 'Contact not found' if contact.nil?

    attrs = { name: name, email: email, phone_number: phone_number, company_name: company_name }.compact
    return 'No attributes provided to update' if attrs.empty?

    contact.update!(attrs)
    "Contact ##{contact_id} updated: #{attrs.keys.join(', ')}"
  end

  def active?
    user_has_permission('contact_manage')
  end
end
