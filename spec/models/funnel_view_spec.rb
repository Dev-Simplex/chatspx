# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FunnelView do
  let(:account) { create(:account) }
  let(:funnel) { Funnel.create!(account: account, name: 'Vendas') }
  let(:user) { create(:user, account: account) }
  let(:other) { create(:user, account: account) }

  describe 'validations' do
    it 'requires a name and a valid view_mode' do
      view = account.funnel_views.build(funnel: funnel, name: '', view_mode: 'kanban')
      expect(view).not_to be_valid
      expect(view.errors[:name]).to be_present

      view.name = 'Minhas urgentes'
      view.view_mode = 'grid'
      expect(view).not_to be_valid
      expect(view.errors[:view_mode]).to be_present
    end
  end

  describe '.visible_to' do
    let!(:mine) { account.funnel_views.create!(funnel: funnel, user: user, name: 'Mine', view_mode: 'kanban') }
    let!(:shared) { account.funnel_views.create!(funnel: funnel, user: other, name: 'Shared', is_shared: true, view_mode: 'kanban') }
    let!(:others_private) { account.funnel_views.create!(funnel: funnel, user: other, name: 'Theirs', view_mode: 'kanban') }

    it 'returns the user\'s own views plus shared ones, not others\' private views' do
      result = account.funnel_views.visible_to(user)
      expect(result).to include(mine, shared)
      expect(result).not_to include(others_private)
    end
  end
end
