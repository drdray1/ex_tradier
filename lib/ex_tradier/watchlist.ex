defmodule ExTradier.Watchlist do
  @moduledoc """
  Tradier Watchlist API - Manage watchlists on the Tradier platform.
  """

  alias ExTradier.Client

  @doc """
  Get all watchlists for the user.
  """
  def get_watchlists(client) do
    Req.get(client, url: "/watchlists")
    |> Client.handle_response()
  end

  @doc """
  Get a specific watchlist by ID.
  """
  def get_watchlist(client, watchlist_id) do
    Req.get(client, url: "/watchlists/#{watchlist_id}")
    |> Client.handle_response()
  end

  @doc """
  Create a new watchlist.
  """
  def create_watchlist(client, params) do
    form_params =
      params
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)

    Req.post(client, url: "/watchlists", form: form_params)
    |> Client.handle_response()
  end

  @doc """
  Update a watchlist.
  """
  def update_watchlist(client, watchlist_id, params) do
    form_params =
      params
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)

    Req.put(client, url: "/watchlists/#{watchlist_id}", form: form_params)
    |> Client.handle_response()
  end

  @doc """
  Delete a watchlist.
  """
  def delete_watchlist(client, watchlist_id) do
    Req.delete(client, url: "/watchlists/#{watchlist_id}")
    |> Client.handle_response()
  end

  @doc """
  Add symbols to a watchlist.
  """
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
  def remove_symbol(client, watchlist_id, symbol) do
    Req.delete(client, url: "/watchlists/#{watchlist_id}/symbols/#{symbol}")
    |> Client.handle_response()
  end
end
