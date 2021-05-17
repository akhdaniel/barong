# frozen_string_literal: true

module API
  module V2
    module Commercial
      # Admin functionality over abilities
      class Accounts < Grape::API
        resource :accounts do
          helpers ::API::V2::NamedParams
          helpers do
            def permitted_search_params(params)
              params.slice(:keyword)
            end
          end

          desc 'Returns array of accounts which user have access as paginated collection',
               failure: [
                 { code: 404, message: 'Account not found' }
               ],
               success: API::V2::Commercial::Entities::Organization
          params do
            use :pagination_filters
          end

          get do
            # Check account in the organization that user belong to
            members = Membership.joins(:organization)
                                .where(user_id: current_user.id)
                                .select('memberships.*,organizations.name, organizations.organization_id')
                                .pluck(:organization_id, :'organizations.name', :'organizations.organization_id')
                                .map { |oid, name, pid| { oid: oid, name: name, pid: pid } }
            error!({ errors: ['identity.member.not_found'] }, 404) if members.nil? || members.length.zero?

            oids = Organization.where(id: members.pluck(:oid)).pluck(:id)
            members.select { |m| m[:pid].nil? }.each do |m|
              oids.concat(Organization.where(organization_id: m[:oid]).pluck(:id))
            end

            # Get all accounts for organization admin even if no membership belong to
            accounts = API::V2::Queries::AccountFilter
                       .new(Organization.joins('LEFT JOIN memberships ON organizations.id = memberships.organization_id')
                                        .where(id: oids))
                       .call(permitted_search_params(params))
                       .distinct

            present paginate(accounts), with: API::V2::Commercial::Entities::Organization
          end
        end
      end
    end
  end
end
