defmodule ExTradier.User do
  @moduledoc """
  Tradier User API - Account and profile management.
  """

  alias ExTradier.Client

  @doc """
  Get user profile information.

  ## Examples

      iex> get_profile(client)
      {:ok, %{"profile" => %{"id" => "id-gcostanza", "name" => "George Costanza", ...}}}
  """
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
  def get_historical_balances(client, account_id, params \\ %{}) do
    Req.get(client,
      url: "/accounts/#{account_id}/balances/historical",
      params: Map.to_list(params)
    )
    |> Client.handle_response()
  end

  @doc """
  Get account positions.

  ## Examples

      iex> get_positions(client, "VA000001")
      {:ok, %{"positions" => %{"position" => [...]}}}
  """
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
  def get_history(client, account_id, params \\ %{}) do
    Req.get(client, url: "/accounts/#{account_id}/history", params: Map.to_list(params))
    |> Client.handle_response()
  end

  @doc """
  Get gain/loss information.

  ## Examples

      iex> get_gainloss(client, "VA000001")
      {:ok, %{"gainloss" => %{"closed_position" => [...]}}}
  """
  def get_gainloss(client, account_id, params \\ %{}) do
    Req.get(client, url: "/accounts/#{account_id}/gainloss", params: Map.to_list(params))
    |> Client.handle_response()
  end

  @doc """
  Get account cost basis.

  ## Examples

      iex> get_cost_basis(client, "VA000001", "AAPL")
      {:ok, %{"costbasis" => [...]}}
  """
  def get_cost_basis(client, account_id, symbol) do
    Req.get(client, url: "/accounts/#{account_id}/costbasis", params: [symbol: symbol])
    |> Client.handle_response()
  end
end
