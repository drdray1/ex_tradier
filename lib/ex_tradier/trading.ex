defmodule ExTradier.Trading do
  @moduledoc """
  Tradier Trading API - Order placement, modification, and management.
  """

  alias ExTradier.Client

  # Valid order parameters
  @valid_equity_sides ~w(buy sell buy_to_cover sell_short)
  @valid_option_sides ~w(buy_to_open buy_to_close sell_to_open sell_to_close)
  @valid_order_types ~w(market limit stop stop_limit)
  @valid_durations ~w(day gtc pre post)
  @valid_order_classes ~w(equity option multileg combo oto oco otoco)

  # OCC option symbol pattern: ROOT + YYMMDD + C/P + STRIKE (8 digits)
  @option_symbol_pattern ~r/^[A-Z]{1,6}\d{6}[CP]\d{8}$/

  @doc """
  Place an equity order.

  ## Parameters

  All standard order params, plus:
    - `:tag` - Optional user-defined order tag (max 255 chars)

  ## Examples

      iex> place_equity_order(client, "VA000001", %{
      ...>   class: "equity", symbol: "AAPL", side: "buy",
      ...>   quantity: 100, type: "market", duration: "day"
      ...> })
      {:ok, %{"order" => %{"id" => 123456, "status" => "ok"}}}
  """
  def place_equity_order(client, account_id, params) do
    form_params =
      params
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)

    Req.post(client, url: "/accounts/#{account_id}/orders", form: form_params)
    |> Client.handle_response()
  end

  @doc """
  Place an option order.
  """
  def place_option_order(client, account_id, params) do
    place_equity_order(client, account_id, Map.put(params, :class, "option"))
  end

  @doc """
  Place a multi-leg option order (spreads, combos).
  """
  def place_multileg_order(client, account_id, params) do
    formatted_params =
      params
      |> Map.put(:class, "multileg")
      |> format_multileg_params()

    form_params =
      formatted_params
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)

    Req.post(client, url: "/accounts/#{account_id}/orders", form: form_params)
    |> Client.handle_response()
  end

  defp format_multileg_params(%{legs: legs} = params) do
    legs_params =
      legs
      |> Enum.with_index()
      |> Enum.flat_map(fn {leg, index} ->
        [
          {"option_symbol[#{index}]", leg.option_symbol},
          {"side[#{index}]", leg.side},
          {"quantity[#{index}]", leg.quantity}
        ]
      end)
      |> Map.new()

    params
    |> Map.delete(:legs)
    |> Map.merge(legs_params)
  end

  @doc """
  Place a combo order.
  """
  def place_combo_order(client, account_id, params) do
    form_params =
      params
      |> Map.put(:class, "combo")
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)

    Req.post(client, url: "/accounts/#{account_id}/orders", form: form_params)
    |> Client.handle_response()
  end

  @doc """
  Modify an existing order.
  """
  def modify_order(client, account_id, order_id, params) do
    form_params =
      params
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)

    Req.put(client, url: "/accounts/#{account_id}/orders/#{order_id}", form: form_params)
    |> Client.handle_response()
  end

  @doc """
  Cancel an order.
  """
  def cancel_order(client, account_id, order_id) do
    Req.delete(client, url: "/accounts/#{account_id}/orders/#{order_id}")
    |> Client.handle_response()
  end

  @doc """
  Get list of orders.
  """
  def get_orders(client, account_id, params \\ %{}) do
    Req.get(client, url: "/accounts/#{account_id}/orders", params: Map.to_list(params))
    |> Client.handle_response()
  end

  @doc """
  Get a specific order by ID.
  """
  def get_order(client, account_id, order_id) do
    Req.get(client, url: "/accounts/#{account_id}/orders/#{order_id}")
    |> Client.handle_response()
  end

  @doc """
  Preview an order before placing it.
  """
  def preview_order(client, account_id, params) do
    params = Map.put(params, :preview, true)

    form_params =
      params
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)

    Req.post(client, url: "/accounts/#{account_id}/orders", form: form_params)
    |> Client.handle_response()
  end

  @doc """
  Place an OTO (One-Triggers-Other) order.
  """
  def place_oto_order(client, account_id, params) do
    form_params =
      params
      |> Map.put(:class, "oto")
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)

    Req.post(client, url: "/accounts/#{account_id}/orders", form: form_params)
    |> Client.handle_response()
  end

  @doc """
  Place an OCO (One-Cancels-Other) order.
  """
  def place_oco_order(client, account_id, params) do
    form_params =
      params
      |> Map.put(:class, "oco")
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)

    Req.post(client, url: "/accounts/#{account_id}/orders", form: form_params)
    |> Client.handle_response()
  end

  @doc """
  Place an OTOCO (One-Triggers-OCO) order.
  """
  def place_otoco_order(client, account_id, params) do
    form_params =
      params
      |> Map.put(:class, "otoco")
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)

    Req.post(client, url: "/accounts/#{account_id}/orders", form: form_params)
    |> Client.handle_response()
  end

  # ============================================================================
  # Order Validation Functions
  # ============================================================================

  @doc """
  Validates order parameters before submission.

  Returns `{:ok, params}` if valid, or `{:error, errors}` with a list of validation errors.
  """
  def validate_order_params(params) when is_map(params) do
    errors =
      []
      |> validate_required_field(params, :symbol, "symbol is required")
      |> validate_required_field(params, :side, "side is required")
      |> validate_required_field(params, :quantity, "quantity is required")
      |> validate_required_field(params, :type, "type is required")
      |> validate_required_field(params, :duration, "duration is required")
      |> validate_positive_quantity(params)
      |> validate_order_type(params)
      |> validate_duration(params)
      |> validate_price_for_limit_orders(params)
      |> validate_stop_for_stop_orders(params)
      |> validate_tag(params)

    if Enum.empty?(errors) do
      {:ok, params}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  def validate_order_params(_), do: {:error, ["params must be a map"]}

  @doc """
  Validates equity order parameters.
  """
  def validate_equity_order(params) when is_map(params) do
    errors =
      []
      |> validate_required_field(params, :symbol, "symbol is required")
      |> validate_required_field(params, :side, "side is required")
      |> validate_required_field(params, :quantity, "quantity is required")
      |> validate_required_field(params, :type, "type is required")
      |> validate_required_field(params, :duration, "duration is required")
      |> validate_equity_side(params)
      |> validate_positive_quantity(params)
      |> validate_order_type(params)
      |> validate_duration(params)
      |> validate_price_for_limit_orders(params)
      |> validate_stop_for_stop_orders(params)
      |> validate_tag(params)

    if Enum.empty?(errors) do
      {:ok, params}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  def validate_equity_order(_), do: {:error, ["params must be a map"]}

  @doc """
  Validates option order parameters.
  """
  def validate_option_order(params) when is_map(params) do
    errors =
      []
      |> validate_required_field(params, :symbol, "symbol is required")
      |> validate_required_field(params, :option_symbol, "option_symbol is required")
      |> validate_required_field(params, :side, "side is required")
      |> validate_required_field(params, :quantity, "quantity is required")
      |> validate_required_field(params, :type, "type is required")
      |> validate_required_field(params, :duration, "duration is required")
      |> validate_option_side(params)
      |> validate_option_symbol_format(params)
      |> validate_positive_quantity(params)
      |> validate_order_type(params)
      |> validate_duration(params)
      |> validate_price_for_limit_orders(params)
      |> validate_stop_for_stop_orders(params)
      |> validate_tag(params)

    if Enum.empty?(errors) do
      {:ok, params}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  def validate_option_order(_), do: {:error, ["params must be a map"]}

  @doc """
  Validates multi-leg order parameters.
  """
  def validate_multileg_order(params) when is_map(params) do
    errors =
      []
      |> validate_required_field(params, :symbol, "symbol is required")
      |> validate_required_field(params, :type, "type is required")
      |> validate_required_field(params, :duration, "duration is required")
      |> validate_required_field(params, :legs, "legs are required")
      |> validate_legs(params)
      |> validate_order_type(params)
      |> validate_duration(params)
      |> validate_price_for_limit_orders(params)
      |> validate_tag(params)

    if Enum.empty?(errors) do
      {:ok, params}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  def validate_multileg_order(_), do: {:error, ["params must be a map"]}

  @doc """
  Validates OCO (One-Cancels-Other) order parameters.

  OCO orders require two legs with different order types.
  """
  def validate_oco_order(params) when is_map(params) do
    errors = validate_oco_different_types([], params)

    if Enum.empty?(errors) do
      {:ok, params}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  def validate_oco_order(_), do: {:error, ["params must be a map"]}

  @doc """
  Validates OTOCO (One-Triggers-OCO) order parameters.

  OTOCO orders require legs 2 and 3 to share the same symbol
  and have different order types.
  """
  def validate_otoco_order(params) when is_map(params) do
    errors =
      []
      |> validate_otoco_matching_symbols(params)
      |> validate_otoco_different_types(params)

    if Enum.empty?(errors) do
      {:ok, params}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  def validate_otoco_order(_), do: {:error, ["params must be a map"]}

  # ============================================================================
  # Validation Helpers
  # ============================================================================

  defp validate_required_field(errors, params, field, message) do
    value = get_field(params, field)

    if is_nil(value) || value == "" do
      [message | errors]
    else
      errors
    end
  end

  defp validate_positive_quantity(errors, params) do
    quantity = get_field(params, :quantity)

    cond do
      is_nil(quantity) -> errors
      is_number(quantity) and quantity > 0 -> errors
      true -> ["quantity must be a positive number" | errors]
    end
  end

  defp validate_equity_side(errors, params) do
    side = get_field(params, :side) |> to_string()

    if side in @valid_equity_sides do
      errors
    else
      ["side must be one of: #{Enum.join(@valid_equity_sides, ", ")}" | errors]
    end
  end

  defp validate_option_side(errors, params) do
    side = get_field(params, :side) |> to_string()

    if side in @valid_option_sides do
      errors
    else
      ["side must be one of: #{Enum.join(@valid_option_sides, ", ")}" | errors]
    end
  end

  defp validate_order_type(errors, params) do
    type = get_field(params, :type) |> to_string()

    if type in @valid_order_types do
      errors
    else
      ["type must be one of: #{Enum.join(@valid_order_types, ", ")}" | errors]
    end
  end

  defp validate_duration(errors, params) do
    duration = get_field(params, :duration) |> to_string()

    if duration in @valid_durations do
      errors
    else
      ["duration must be one of: #{Enum.join(@valid_durations, ", ")}" | errors]
    end
  end

  defp validate_price_for_limit_orders(errors, params) do
    type = get_field(params, :type) |> to_string()
    price = get_field(params, :price)

    if type in ["limit", "stop_limit"] do
      cond do
        is_nil(price) -> ["price is required for #{type} orders" | errors]
        is_number(price) and price > 0 -> errors
        true -> ["price must be a positive number" | errors]
      end
    else
      errors
    end
  end

  defp validate_stop_for_stop_orders(errors, params) do
    type = get_field(params, :type) |> to_string()
    stop = get_field(params, :stop)

    if type in ["stop", "stop_limit"] do
      cond do
        is_nil(stop) -> ["stop is required for #{type} orders" | errors]
        is_number(stop) and stop > 0 -> errors
        true -> ["stop must be a positive number" | errors]
      end
    else
      errors
    end
  end

  defp validate_tag(errors, params) do
    tag = get_field(params, :tag)

    cond do
      is_nil(tag) -> errors
      not is_binary(tag) -> ["tag must be a string" | errors]
      String.length(tag) > 255 -> ["tag must be 255 characters or fewer" | errors]
      true -> errors
    end
  end

  defp validate_option_symbol_format(errors, params) do
    option_symbol = get_field(params, :option_symbol) |> to_string()

    if String.match?(option_symbol, @option_symbol_pattern) do
      errors
    else
      ["option_symbol must be in OCC format (e.g., AAPL240119C00150000)" | errors]
    end
  end

  defp validate_legs(errors, params) do
    legs = get_field(params, :legs)

    cond do
      is_nil(legs) ->
        errors

      not is_list(legs) ->
        ["legs must be a list" | errors]

      length(legs) < 2 ->
        ["multi-leg orders require at least 2 legs" | errors]

      length(legs) > 4 ->
        ["multi-leg orders cannot exceed 4 legs" | errors]

      true ->
        validate_each_leg(errors, legs)
    end
  end

  defp validate_each_leg(errors, legs) do
    Enum.with_index(legs)
    |> Enum.reduce(errors, fn {leg, index}, acc ->
      leg_errors = validate_leg(leg, index)
      leg_errors ++ acc
    end)
  end

  defp validate_leg(leg, index) when is_map(leg) do
    errors = []

    errors =
      if is_nil(get_field(leg, :option_symbol)) do
        ["leg #{index + 1}: option_symbol is required" | errors]
      else
        errors
      end

    errors =
      if is_nil(get_field(leg, :side)) do
        ["leg #{index + 1}: side is required" | errors]
      else
        side = get_field(leg, :side) |> to_string()

        if side in @valid_option_sides do
          errors
        else
          [
            "leg #{index + 1}: side must be one of: #{Enum.join(@valid_option_sides, ", ")}"
            | errors
          ]
        end
      end

    errors =
      if is_nil(get_field(leg, :quantity)) do
        ["leg #{index + 1}: quantity is required" | errors]
      else
        quantity = get_field(leg, :quantity)

        if is_number(quantity) and quantity > 0 do
          errors
        else
          ["leg #{index + 1}: quantity must be a positive number" | errors]
        end
      end

    errors
  end

  defp validate_leg(_, index) do
    ["leg #{index + 1}: must be a map"]
  end

  defp get_field(params, field) when is_atom(field) do
    Map.get(params, field) || Map.get(params, Atom.to_string(field))
  end

  defp get_indexed_field(params, field, index) do
    key_str = "#{field}[#{index}]"
    key_atom = String.to_atom(key_str)
    Map.get(params, key_str) || Map.get(params, key_atom)
  end

  defp validate_oco_different_types(errors, params) do
    type_0 = get_indexed_field(params, "type", 0)
    type_1 = get_indexed_field(params, "type", 1)

    if type_0 && type_1 && to_string(type_0) == to_string(type_1) do
      ["OCO legs must have different order types" | errors]
    else
      errors
    end
  end

  defp validate_otoco_matching_symbols(errors, params) do
    symbol_1 = get_indexed_field(params, "symbol", 1)
    symbol_2 = get_indexed_field(params, "symbol", 2)

    if symbol_1 && symbol_2 && to_string(symbol_1) != to_string(symbol_2) do
      ["OTOCO legs 2 and 3 must have the same symbol" | errors]
    else
      errors
    end
  end

  defp validate_otoco_different_types(errors, params) do
    type_1 = get_indexed_field(params, "type", 1)
    type_2 = get_indexed_field(params, "type", 2)

    if type_1 && type_2 && to_string(type_1) == to_string(type_2) do
      ["OTOCO legs 2 and 3 must have different order types" | errors]
    else
      errors
    end
  end

  # ============================================================================
  # Accessor functions for valid values
  # ============================================================================

  @doc "Returns list of valid equity order sides"
  def valid_equity_sides, do: @valid_equity_sides

  @doc "Returns list of valid option order sides"
  def valid_option_sides, do: @valid_option_sides

  @doc "Returns list of valid order types"
  def valid_order_types, do: @valid_order_types

  @doc "Returns list of valid order durations"
  def valid_durations, do: @valid_durations

  @doc "Returns list of valid order classes"
  def valid_order_classes, do: @valid_order_classes
end
