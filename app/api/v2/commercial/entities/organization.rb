# frozen_string_literal: true

module API::V2::Commercial
  module Entities
    class Organization < API::V2::Entities::Base
      expose :id,
             documentation: {
               type: 'Integer',
               desc: 'Organization ID'
             }

      expose :oid,
             as: 'aid',
             documentation: {
               type: 'String',
               desc: 'Organization Account ID'
             }

      expose :name,
             documentation: {
               type: 'String',
               desc: 'Organization Account Name'
             }

      expose :uids do |member|
        member.memberships.map { |m| m.user.uid }
      end
    end
  end
end
