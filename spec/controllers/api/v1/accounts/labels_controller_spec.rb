require 'rails_helper'

RSpec.describe 'Label API', type: :request do
  let!(:account) { create(:account) }
  let!(:label) { create(:label, account: account) }
  let!(:conversation) { create(:conversation, account: account) }

  describe 'GET /api/v1/accounts/{account.id}/labels' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/labels"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :administrator) }

      it 'returns all the labels in account' do
        get "/api/v1/accounts/#{account.id}/labels",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include(label.title)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/labels/:id' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/labels/#{label.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'shows the contact' do
        get "/api/v1/accounts/#{account.id}/labels/#{label.id}",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.body).to include(label.title)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/labels' do
    let(:valid_params) { { label: { title: 'test' } } }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        expect { post "/api/v1/accounts/#{account.id}/labels", params: valid_params }.not_to change(Label, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'creates the contact' do
        expect do
          post "/api/v1/accounts/#{account.id}/labels", headers: admin.create_new_auth_token,
                                                        params: valid_params
        end.to change(Label, :count).by(1)

        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/labels/:id' do
    let(:valid_params) { { title: 'Test_2' }  }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        put "/api/v1/accounts/#{account.id}/labels/#{label.id}",
            params: valid_params

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'updates the label' do
        patch "/api/v1/accounts/#{account.id}/labels/#{label.id}",
              headers: admin.create_new_auth_token,
              params: valid_params,
              as: :json

        expect(response).to have_http_status(:success)
        expect(label.reload.title).to eq('test_2')
      end
    end
  end

  describe 'visibility' do
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:agent_1) { create(:user, account: account, role: :agent) }
    let(:agent_2) { create(:user, account: account, role: :agent) }
    let(:team_1) { create(:team, account: account) }
    let(:team_2) { create(:team, account: account) }

    before do
      create(:team_member, user: agent_1, team: team_1)
      create(:team_member, user: agent_2, team: team_2)
    end

    describe 'GET index filtered by visibility' do
      let!(:public_label) { create(:label, account: account, visibility: :everyone, created_by: admin) }
      let!(:agent_1_private) { create(:label, account: account, visibility: :personal, created_by: agent_1) }
      let!(:agent_2_private) { create(:label, account: account, visibility: :personal, created_by: agent_2) }
      let!(:team_1_label) { create(:label, account: account, visibility: :team, team: team_1, created_by: admin) }
      let!(:team_2_label) { create(:label, account: account, visibility: :team, team: team_2, created_by: admin) }

      def label_ids_for(user)
        get "/api/v1/accounts/#{account.id}/labels", headers: user.create_new_auth_token, as: :json
        response.parsed_body['payload'].map { |l| l['id'] }
      end

      it 'returns everything for an administrator' do
        ids = label_ids_for(admin)
        expect(ids).to include(public_label.id, agent_1_private.id, agent_2_private.id, team_1_label.id, team_2_label.id)
      end

      it 'returns public + own private + own team for agent_1' do
        ids = label_ids_for(agent_1)
        expect(ids).to include(public_label.id, agent_1_private.id, team_1_label.id)
        expect(ids).not_to include(agent_2_private.id, team_2_label.id)
      end

      it 'returns public + own private + own team for agent_2' do
        ids = label_ids_for(agent_2)
        expect(ids).to include(public_label.id, agent_2_private.id, team_2_label.id)
        expect(ids).not_to include(agent_1_private.id, team_1_label.id)
      end
    end

    describe 'POST create by an agent' do
      it 'creates a public label by default' do
        post "/api/v1/accounts/#{account.id}/labels",
             headers: agent_1.create_new_auth_token,
             params: { label: { title: 'public_one' } }, as: :json

        expect(response).to have_http_status(:success)
        created = account.labels.find_by(title: 'public_one')
        expect(created.visibility).to eq('everyone')
        expect(created.created_by_id).to eq(agent_1.id)
      end

      it 'creates a private label' do
        post "/api/v1/accounts/#{account.id}/labels",
             headers: agent_1.create_new_auth_token,
             params: { label: { title: 'private_one', visibility: 'personal' } }, as: :json

        expect(response).to have_http_status(:success)
        expect(account.labels.find_by(title: 'private_one').visibility).to eq('personal')
      end

      it 'creates a team label when the agent is a member of the team' do
        post "/api/v1/accounts/#{account.id}/labels",
             headers: agent_1.create_new_auth_token,
             params: { label: { title: 'team_one', visibility: 'team', team_id: team_1.id } }, as: :json

        expect(response).to have_http_status(:success)
        created = account.labels.find_by(title: 'team_one')
        expect(created.visibility).to eq('team')
        expect(created.team_id).to eq(team_1.id)
      end

      it 'forbids creating a team label for a team the agent is not a member of' do
        expect do
          post "/api/v1/accounts/#{account.id}/labels",
               headers: agent_1.create_new_auth_token,
               params: { label: { title: 'team_two', visibility: 'team', team_id: team_2.id } }, as: :json
        end.not_to change(Label, :count)

        expect(response).to have_http_status(:forbidden)
      end

      it 'allows an admin to create a team label for any team' do
        post "/api/v1/accounts/#{account.id}/labels",
             headers: admin.create_new_auth_token,
             params: { label: { title: 'team_admin', visibility: 'team', team_id: team_2.id } }, as: :json

        expect(response).to have_http_status(:success)
      end
    end

    describe 'PUT update authorization' do
      it 'lets the author update their own label' do
        own = create(:label, account: account, visibility: :personal, created_by: agent_1)

        put "/api/v1/accounts/#{account.id}/labels/#{own.id}",
            headers: agent_1.create_new_auth_token,
            params: { label: { description: 'mine' } }, as: :json

        expect(response).to have_http_status(:success)
        expect(own.reload.description).to eq('mine')
      end

      it 'lets a team member update a team label' do
        team_label = create(:label, account: account, visibility: :team, team: team_1, created_by: admin)

        put "/api/v1/accounts/#{account.id}/labels/#{team_label.id}",
            headers: agent_1.create_new_auth_token,
            params: { label: { description: 'team edit' } }, as: :json

        expect(response).to have_http_status(:success)
        expect(team_label.reload.description).to eq('team edit')
      end

      it 'forbids a non-author from updating a public label' do
        public_label = create(:label, account: account, visibility: :everyone, created_by: admin)

        put "/api/v1/accounts/#{account.id}/labels/#{public_label.id}",
            headers: agent_1.create_new_auth_token,
            params: { label: { description: 'nope' } }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it "forbids an agent from updating another agent's private label" do
        others_private = create(:label, account: account, visibility: :personal, created_by: agent_2)

        put "/api/v1/accounts/#{account.id}/labels/#{others_private.id}",
            headers: agent_1.create_new_auth_token,
            params: { label: { description: 'nope' } }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

  describe 'DELETE /api/v1/accounts/{account.id}/labels/:id' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/labels/#{label.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    describe 'DELETE authorization' do
      it 'lets the author delete their own label' do
        own = create(:label, account: account, visibility: :personal, created_by: agent_1)

        delete "/api/v1/accounts/#{account.id}/labels/#{own.id}",
               headers: agent_1.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
      end

      it "forbids an agent from deleting another agent's private label" do
        others_private = create(:label, account: account, visibility: :personal, created_by: agent_2)

        delete "/api/v1/accounts/#{account.id}/labels/#{others_private.id}",
               headers: agent_1.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    describe 'regression: agent access to previously admin-only routes' do
      it 'lets an agent list labels' do
        get "/api/v1/accounts/#{account.id}/labels", headers: agent_1.create_new_auth_token, as: :json
        expect(response).to have_http_status(:success)
      end

      it 'lets an agent create a label' do
        expect do
          post "/api/v1/accounts/#{account.id}/labels",
               headers: agent_1.create_new_auth_token,
               params: { label: { title: 'agent_made' } }, as: :json
        end.to change(Label, :count).by(1)

        expect(response).to have_http_status(:success)
      end
    end

    context 'when it is an authenticated user' do
      let(:admin) { create(:user, account: account, role: :administrator) }

      it 'deletes the label and enqueues label cleanup' do
        label_deleted_at = Time.zone.parse('2026-05-07 10:00:00 UTC')
        conversation.label_list.add(label.title)
        conversation.save!

        clear_enqueued_jobs

        travel_to(label_deleted_at) do
          expect do
            delete "/api/v1/accounts/#{account.id}/labels/#{label.id}", headers: admin.create_new_auth_token, as: :json
          end.to have_enqueued_job(Labels::RemoveAssociationsJob).with(
            label_title: label.title,
            account_id: account.id,
            label_deleted_at: label_deleted_at
          )
        end

        expect(response).to have_http_status(:ok)
        expect(Label.exists?(label.id)).to be(false)
      end
    end
  end
  end
end
