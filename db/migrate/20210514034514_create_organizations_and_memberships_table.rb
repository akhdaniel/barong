class CreateOrganizationsAndMembershipsTable < ActiveRecord::Migration[5.2]
  def change
    create_table :organizations do |t|
      t.string     :oid,          null: false
      t.belongs_to :organization, null: true
      t.string     :name,         null: false
      t.string     :status,       default: 'active', null: false
      t.timestamps
    end
    add_index :organizations, :oid, unique: true

    create_table :memberships do |t|
      t.belongs_to :user
      t.belongs_to :organization
      t.string     :role, default: 'member', null: false
      t.timestamps
    end
  end
end
