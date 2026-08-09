defmodule ExTradier.Watchlist do
  @moduledoc """
  Tradier Watchlist API - Manage watchlists on the Tradier platform.
  """

  alias ExTradier.Client

  @type params :: map() | keyword()

  @doc """
  Get all watchlists for the user.
  """
  @spec get_watchlists(Client.client()) :: Client.response()
  def get_watchlists(client) do
    Req.get(client, url: "/watchlists")
    |> Client.handle_response()
  end

  @doc """
  Get a specific watchlist by ID.
  """
  @spec get_watchlist(Client.client(), String.t()) :: Client.response()
  def get_watchlist(client, watchlist_id) do
    Req.get(client, url: "/watchlists/#{watchlist_id}")
    |> Client.handle_response()
  end

  @doc """
  Create a new watchlist.

  ## Parameters

    - `:name` - Required. Watchlist name
    - `:symbols` - Optional comma-separated list of symbols to seed it with
  """
  @spec create_watchlist(Client.client(), params()) :: Client.response()
  def create_watchlist(client, params) do
    Req.post(client, url: "/watchlists", form: Client.to_form(params))
    |> Client.handle_response()
  end

  @doc """
  Update a watchlist.
  """
  @spec update_watchlist(Client.client(), String.t(), params()) :: Client.response()
  def update_watchlist(client, watchlist_id, params) do
    Req.put(client, url: "/watchlists/#{watchlist_id}", form: Client.to_form(params))
    |> Client.handle_response()
  end

  @doc """
  Delete a watchlist.
  """
  @spec delete_watchlist(Client.client(), String.t()) :: Client.response()
  def delete_watchlist(client, watchlist_id) do
    Req.delete(client, url: "/watchlists/#{watchlist_id}")
    |> Client.handle_response()
  end

  @doc """
  Add symbols to a watchlist.
  """
  @spec add_symbols(Client.client(), String.t(), String.t() | [String.t()]) :: Client.response()
  def add_symbols(client, watchlist_id, symbols) when is_list(symbols) do
    add_symbols(client, watchlist_id, Enum.join(symbols, ","))
  end

  def add_symbols(client, watchlist_id, symbols) when is_binary(symbols) do
    Req.post(client, url: "/watchlists/#{watchlist_id}/symbols", form: [symbols: symbols])
    |> Client.handle_response()
  end

  @doc """
  Remove a symbol from a watchlist.
  """
  @spec remove_symbol(Client.client(), String.t(), String.t()) :: Client.response()
  def remove_symbol(client, watchlist_id, symbol) do
    Req.delete(client, url: "/watchlists/#{watchlist_id}/symbols/#{symbol}")
    |> Client.handle_response()
  end
end
