require 'rails_helper'

RSpec.describe Avatar::AvatarFromFaviconJob do
  let(:company) { create(:company, domain: 'wikipedia.org') }
  let(:favicon_url) { 'https://www.google.com/s2/favicons?domain=wikipedia.org&sz=256' }
  let(:file) { fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png') }

  # AvatarFromUrlJob passou a receber (type, id, url) em 87095e111b; este callsite ficou
  # com a assinatura antiga e estourava ArgumentError em produção.
  it 'calls AvatarFromUrlJob with the avatarable type, id and the Google Favicon URL' do
    expect(Avatar::AvatarFromUrlJob).to receive(:perform_now).with('Company', company.id, favicon_url)
    described_class.perform_now(company)
  end

  # Verificar o ANEXO, não só a chamada: com a aridade certa mas 'Company' fora de
  # ALLOWED_AVATARABLE_TYPES, o job daria return na 1ª linha e a falha ficaria silenciosa.
  it 'actually attaches the downloaded favicon to the company' do
    expect(Down).to receive(:download).with(favicon_url, max_size: Avatar::AvatarFromUrlJob::MAX_DOWNLOAD_SIZE).and_return(file)

    described_class.perform_now(company)

    expect(company.reload.avatar).to be_attached
  end

  it 'does not call AvatarFromUrlJob when domain is blank' do
    company.update(domain: '')
    expect(Avatar::AvatarFromUrlJob).not_to receive(:perform_now)
    described_class.perform_now(company)
  end

  it 'does not call AvatarFromUrlJob when avatar is already attached' do
    company.avatar.attach(
      io: Rails.root.join('spec/assets/avatar.png').open,
      filename: 'avatar.png',
      content_type: 'image/png'
    )
    expect(Avatar::AvatarFromUrlJob).not_to receive(:perform_now)
    described_class.perform_now(company)
  end
end
