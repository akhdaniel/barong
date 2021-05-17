# frozen_string_literal: true

class Organization < ApplicationRecord
  has_one :organization
  has_many :memberships
end

# == Schema Information
# Schema version: 20210514034514
#
# Table name: organizations
#
#  id              :bigint           not null, primary key
#  oid             :string(255)      not null
#  organization_id :bigint
#  name            :string(255)      not null
#  status          :string(255)      default("active"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_organizations_on_oid              (oid) UNIQUE
#  index_organizations_on_organization_id  (organization_id)
#
