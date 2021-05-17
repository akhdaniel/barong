# frozen_string_literal: true

describe API::V2::Commercial::Accounts, type: :request do
  include_context 'bearer authentication'

  let!(:create_member_permission) do
    create :permission,
           role: 'member'
  end
  let!(:create_admin_permission) do
    create :permission,
           role: 'admin'
  end
  let!(:create_superadmin_permission) do
    create :permission,
           role: 'superadmin'
  end

  let!(:create_users) do
    create(:user, id: 1, uid: 'IDFE09F81060', email: 'admin@barong.io', role: 'admin')
  end

  let!(:create_organizations) do
    create(:organization, id: 1, oid: 'OID001', organization_id: nil, name: 'Company A')
    create(:organization, id: 2, oid: 'OID002', organization_id: nil, name: 'Company B')
    create(:organization, id: 3, oid: 'OID001AID001', organization_id: 1, name: 'Group A1')
    create(:organization, id: 4, oid: 'OID001AID002', organization_id: 1, name: 'Group A2')
    create(:organization, id: 5, oid: 'OID002AID001', organization_id: 2, name: 'Group B1')
    create(:organization, id: 6, oid: 'OID002AID002', organization_id: 2, name: 'Group B2')
  end

  describe 'GET /api/v2/commercial/accounts' do
    let(:test_user) { User.find(1) }

    it 'error when account not found' do
      get '/api/v2/commercial/accounts', headers: auth_header

      expect(response.status).to eq 404
    end

    context 'user is organization admin' do
      let!(:create_memberships) do
        # Assign user as organization admin
        create(:membership, id: 1, user_id: 1, organization_id: 1)
      end

      it 'get all accounts in the organization' do
        get '/api/v2/commercial/accounts', headers: auth_header
        result = JSON.parse(response.body)
        expect(response).to be_successful
        expect(result.length).to eq 3
      end

      it 'return list of accounts filtered account by organization name' do
        get '/api/v2/commercial/accounts',
            headers: auth_header,
            params: { keyword: 'Company A' }
        result = JSON.parse(response.body)
        expect(response).to be_successful
        expect(result.length).to eq 1
        expect(result[0]['name']).to eq 'Company A'
      end

      it 'return list of accounts filtered account by organization account name' do
        get '/api/v2/commercial/accounts',
            headers: auth_header,
            params: { keyword: 'Group A1' }
        result = JSON.parse(response.body)
        expect(response).to be_successful
        expect(result.length).to eq 1
        expect(result[0]['name']).to eq 'Group A1'
      end

      it 'return list of accounts filtered account by uid' do
        get '/api/v2/commercial/accounts',
            headers: auth_header,
            params: { keyword: 'IDFE09F81060' }
        result = JSON.parse(response.body)
        expect(response).to be_successful
        expect(result.length).to eq 1
        expect(result[0]['uids']).to eq ['IDFE09F81060']
      end
    end

    context 'user is organization member' do
      let!(:create_memberships) do
        # Assign user as organization member
        create(:membership, id: 1, user_id: 1, organization_id: 3)
      end

      it 'get account of the organization' do
        get '/api/v2/commercial/accounts', headers: auth_header
        result = JSON.parse(response.body)
        expect(response).to be_successful
        expect(result.length).to eq 1
      end

      it 'get multiple accounts of the organization' do
        # Assign user as organization member
        create(:membership, id: 2, user_id: 1, organization_id: 4)

        get '/api/v2/commercial/accounts', headers: auth_header
        result = JSON.parse(response.body)
        expect(response).to be_successful
        expect(result.length).to eq 2
      end

      it 'return list of accounts filtered account by organization account name' do
        # Assign user as organization member
        create(:membership, id: 2, user_id: 1, organization_id: 4)

        get '/api/v2/commercial/accounts',
            headers: auth_header,
            params: { keyword: 'Group A1' }
        result = JSON.parse(response.body)
        expect(response).to be_successful
        expect(result.length).to eq 1
        expect(result[0]['name']).to eq 'Group A1'
      end
    end
  end
end
