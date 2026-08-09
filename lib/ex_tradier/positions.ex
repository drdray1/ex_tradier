defmodule ExTradier.Positions do
  @moduledoc """
  Tradier Position Groups API - Manage position groups for an account.

  Position groups allow organizing positions into logical groupings
  for tracking and analysis purposes.
  """

  alias ExTradier.Client

  @type params :: map() | keyword()

  @doc """
  Get all position groups for an account.

  ## Examples

      iex> get_position_groups(client, "VA000001")
      {:ok, %{"position_groups" => [...]}}
  """
  @spec get_position_groups(Client.client(), String.t()) :: Client.response()
  def get_position_groups(client, account_id) do
    Req.get(client, url: "/accounts/#{account_id}/position_groups")
    |> Client.handle_response()
  end

  @doc """
  Create a new position group.

  ## Parameters

    - `name` - Name for the position group
    - `symbols` - Comma-separated list of symbols

  ## Examples

      iex> create_position_group(client, "VA000001", %{name: "Tech Holdings", symbols: "AAPL,MSFT"})
      {:ok, %{"position_group" => %{"id" => "pg-123", ...}}}
  """
  @spec create_position_group(Client.client(), String.t(), params()) :: Client.response()
  def create_position_group(client, account_id, params) do
    Req.post(client,
      url: "/accounts/#{account_id}/position_groups",
      form: Client.to_form(params)
    )
    |> Client.handle_response()
  end

  @doc """
  Update a position group.

  ## Examples

      iex> update_position_group(client, "VA000001", "pg-123", %{name: "Updated Name"})
      {:ok, %{"position_group" => %{...}}}
  """
  @spec update_position_group(Client.client(), String.t(), String.t(), params()) ::
          Client.response()
  def update_position_group(client, account_id, group_id, params) do
    Req.put(client,
      url: "/accounts/#{account_id}/position_groups/#{group_id}",
      form: Client.to_form(params)
    )
    |> Client.handle_response()
  end

  @doc """
  Delete a position group.

  ## Examples

      iex> delete_position_group(client, "VA000001", "pg-123")
      {:ok, %{}}
  """
  @spec delete_position_group(Client.client(), String.t(), String.t()) :: Client.response()
  def delete_position_group(client, account_id, group_id) do
    Req.delete(client, url: "/accounts/#{account_id}/position_groups/#{group_id}")
    |> Client.handle_response()
  end
end
