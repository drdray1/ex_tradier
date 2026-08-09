defmodule ExTradier.User do
  @moduledoc """
  Tradier User API - Account and profile management.
  """

  alias ExTradier.Client

  @type params :: map() | keyword()

  @doc """
  Get user profile information.

  ## Examples

      iex> get_profile(client)
      {:ok, %{"profile" => %{"id" => "id-gcostanza", "name" => "George Costanza", ...}}}
  """
  @spec get_profile(Client.client()) :: Client.response()
  def get_profile(client) do
    Req.get(client, url: "/user/profile")
    |> Client.handle_response()
  end

  @doc """
  Get account balances.

  ## Examples

      iex> get_balances(client, "VA000001")
      {:ok, %{"balances" => %{"total_equity" => 123456.78, ...}}}
  """
  @spec get_balances(Client.client(), String.t()) :: Client.response()
  def get_balances(client, account_id) do
    Req.get(client, url: "/accounts/#{account_id}/balances")
    |> Client.handle_response()
  end

  @doc """
  Get historical balance data for an account.

  ## Options

    - `:period` - Time period: "WEEK", "MONTH", "YTD", "YEAR", "YEAR_3", "YEAR_5", "ALL"

  ## Examples

      iex> get_historical_balances(client, "VA000001")
      {:ok, %{"balances" => [%{"date" => "2025-07-15", "value" => 113302.4}], ...}}

      iex> get_historical_balances(client, "VA000001", %{period: "MONTH"})
      {:ok, %{"balances" => [...]}}
  """
  @spec get_historical_balances(Client.client(), String.t(), params()) :: Client.response()
  def get_historical_balances(client, account_id, params \\ %{}) do
    Req.get(client,
      url: "/accounts/#{account_id}/balances/historical",
      params: Client.to_params(params)
    )
    |> Client.handle_response()
  end

  @doc """
  Get account positions.

  ## Examples

      iex> get_positions(client, "VA000001")
      {:ok, %{"positions" => %{"position" => [...]}}}
  """
  @spec get_positions(Client.client(), String.t()) :: Client.response()
  def get_positions(client, account_id) do
    Req.get(client, url: "/accounts/#{account_id}/positions")
    |> Client.handle_response()
  end

  @doc """
  Get account history/activity.

  ## Examples

      iex> get_history(client, "VA000001")
      {:ok, %{"history" => %{"event" => [...]}}}
  """
  @spec get_history(Client.client(), String.t(), params()) :: Client.response()
  def get_history(client, account_id, params \\ %{}) do
    Req.get(client, url: "/accounts/#{account_id}/history", params: Client.to_params(params))
    |> Client.handle_response()
  end

  @doc """
  Get gain/loss information.

  ## Examples

      iex> get_gainloss(client, "VA000001")
      {:ok, %{"gainloss" => %{"closed_position" => [...]}}}
  """
  @spec get_gainloss(Client.client(), String.t(), params()) :: Client.response()
  def get_gainloss(client, account_id, params \\ %{}) do
    Req.get(client, url: "/accounts/#{account_id}/gainloss", params: Client.to_params(params))
    |> Client.handle_response()
  end

  @doc """
  Get account cost basis.

  ## Examples

      iex> get_cost_basis(client, "VA000001", "AAPL")
      {:ok, %{"costbasis" => [...]}}
  """
  @spec get_cost_basis(Client.client(), String.t(), String.t()) :: Client.response()
  def get_cost_basis(client, account_id, symbol) do
    Req.get(client, url: "/accounts/#{account_id}/costbasis", params: [symbol: symbol])
    |> Client.handle_response()
  end
end
