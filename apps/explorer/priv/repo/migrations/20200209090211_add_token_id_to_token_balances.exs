defmodule Explorer.Repo.Migrations.AddTokenIdToTokenBalances do
  use Ecto.Migration

  def change do
    alter table(:address_token_balances) do
      add(:token_id, :numeric, precision: 78, scale: 0, null: true)
      add(:token_type, :string, null: true)
    end

    create(index(:address_token_balances, [:token_id]))

    drop(unique_index(:address_token_balances, ~w(address_hash token_contract_address_hash block_number)a))

    drop(
      unique_index(
        :address_token_balances,
        ~w(address_hash token_contract_address_hash block_number)a,
        name: :unfetched_token_balances,
        where: "value_fetched_at IS NULL"
      )
    )

    create(unique_index(:address_token_balances, ~w(address_hash token_contract_address_hash block_number token_id)a))

    create(
      unique_index(
        :address_token_balances,
        ~w(address_hash token_contract_address_hash block_number token_id)a,
        name: :unfetched_token_balances,
        where: "value_fetched_at IS NULL"
      )
    )
  end
end
