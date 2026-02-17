defmodule ExTradier.Client do
  @moduledoc """
  HTTP client for Tradier API.

  Handles authentication and request/response formatting using Req.

  ## Usage

      client = ExTradier.Client.new("your_api_token")
      {:ok, profile} = ExTradier.User.get_profile(client)

      # Sandbox mode (default)
      client = ExTradier.Client.new("token", sandbox: true)

      # Production mode
      client = ExTradier.Client.new("token", sandbox: false)

      # Testing with Req.Test
      client = ExTradier.Client.new("token", plug: {Req.Test, MyStub})
  """

  @type client :: Req.Request.t()
  @type response :: {:ok, map()} | {:error, term()}

  @type rate_limit :: %{
          available: non_neg_integer(),
          expiry: non_neg_integer(),
          used: non_neg_integer()
        }

  @doc """
  Creates a new Tradier API client with authentication token.

  ## Options

    - `:sandbox` - Use sandbox environment (default: true)
    - `:plug` - Test plug for `Req.Test` (default: nil)
  """
  @spec new(String.t(), keyword()) :: client()
  def new(api_token, opts \\ []) do
    sandbox = Keyword.get(opts, :sandbox, true)
    plug = Keyword.get(opts, :plug)

    req_opts =
      [
        base_url: base_url(sandbox),
        headers: [{"accept", "application/json"}],
        retry: :transient,
        max_retries: 3,
        retry_delay: fn attempt -> 500 * Integer.pow(2, attempt) end
      ]
      |> maybe_add_plug(plug)

    Req.new(req_opts)
    |> ExTradier.Auth.attach(api_token)
  end

  @doc """
  Returns the base URL based on environment configuration.
  """
  @spec base_url(boolean()) :: String.t()
  def base_url(sandbox \\ true) do
    config = Application.get_env(:ex_tradier, :config, [])

    if sandbox do
      Keyword.get(config, :sandbox_url, "https://sandbox.tradier.com/v1")
    else
      Keyword.get(config, :base_url, "https://api.tradier.com/v1")
    end
  end

  @doc """
  Returns the sandbox API URL.
  """
  @spec sandbox_url() :: String.t()
  def sandbox_url, do: "https://sandbox.tradier.com/v1"

  @doc """
  Returns the production API URL.
  """
  @spec production_url() :: String.t()
  def production_url, do: "https://api.tradier.com/v1"

  @doc """
  Returns the WebSocket base URL.
  """
  @spec websocket_url(boolean()) :: String.t()
  def websocket_url(sandbox \\ false) do
    config = Application.get_env(:ex_tradier, :config, [])

    if sandbox do
      Keyword.get(config, :sandbox_websocket_url, "wss://sandbox-ws.tradier.com/v1")
    else
      Keyword.get(config, :websocket_url, "wss://ws.tradier.com/v1")
    end
  end

  @doc """
  Returns the HTTP streaming base URL.
  """
  @spec stream_url(boolean()) :: String.t()
  def stream_url(sandbox \\ false) do
    config = Application.get_env(:ex_tradier, :config, [])

    if sandbox do
      Keyword.get(config, :sandbox_stream_url, "https://sandbox.tradier.com/v1")
    else
      Keyword.get(config, :stream_url, "https://stream.tradier.com/v1")
    end
  end

  @doc """
  Validates the API token by making a test request.
  """
  @spec validate_token(client()) :: {:ok, :valid} | {:error, term()}
  def validate_token(client) do
    case Req.get(client, url: "/user/profile") do
      {:ok, %Req.Response{status: 200}} -> {:ok, :valid}
      {:ok, %Req.Response{status: 401}} -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Verifies credentials by testing the API token and returns user profile on success.

  ## Parameters

    - `api_token` - The Tradier API access token
    - `sandbox_mode` - Boolean indicating if using sandbox environment (default: true)

  ## Returns

    - `{:ok, user_profile}` - On successful authentication
    - `{:error, reason}` - On failure
  """
  @spec verify_credentials(String.t(), boolean()) :: response()
  def verify_credentials(api_token, sandbox_mode \\ true) do
    client = new(api_token, sandbox: sandbox_mode)

    case Req.get(client, url: "/user/profile") do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: 401}} ->
        {:error, "Invalid API token - unauthorized"}

      {:ok, %Req.Response{status: status}} ->
        {:error, "API returned status #{status}"}

      {:error, reason} ->
        {:error, "Connection failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Fetches real-time quote for a single symbol.
  """
  @spec get_quote(client(), String.t()) :: response()
  def get_quote(client, symbol) when is_binary(symbol) do
    case get_quotes(client, symbol) do
      {:ok, [quote]} -> {:ok, quote}
      {:ok, quotes} when is_list(quotes) -> {:ok, List.first(quotes)}
      error -> error
    end
  end

  @doc """
  Fetches real-time quotes for one or more symbols.
  """
  @spec get_quotes(client(), String.t() | [String.t()]) :: {:ok, list()} | {:error, term()}
  def get_quotes(client, symbols) when is_list(symbols) do
    symbols_param = Enum.join(symbols, ",")
    get_quotes(client, symbols_param)
  end

  def get_quotes(client, symbols) when is_binary(symbols) do
    case Req.get(client, url: "/markets/quotes", params: [symbols: symbols]) do
      {:ok, %Req.Response{status: 200, body: %{"quotes" => %{"quote" => quotes}}}} ->
        {:ok, normalize_quotes(quotes)}

      {:ok, %Req.Response{status: status}} ->
        {:error, "API returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_quotes(quote) when is_map(quote), do: [quote]
  defp normalize_quotes(quotes) when is_list(quotes), do: quotes

  @doc """
  Handles API response and normalizes to standard format.
  """
  @spec handle_response({:ok, Req.Response.t()} | {:error, term()}) :: response()
  def handle_response({:ok, %Req.Response{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  def handle_response({:ok, %Req.Response{status: 401}}) do
    {:error, :unauthorized}
  end

  def handle_response({:ok, %Req.Response{status: 403}}) do
    {:error, :forbidden}
  end

  def handle_response({:ok, %Req.Response{status: 404}}) do
    {:error, :not_found}
  end

  def handle_response({:ok, %Req.Response{status: 429}}) do
    {:error, :rate_limited}
  end

  def handle_response({:ok, %Req.Response{status: status, body: body}}) when status >= 400 do
    error_message =
      cond do
        is_binary(body) -> body
        is_map(body) -> get_in(body, ["errors", "error"]) || "Unknown error"
        true -> "Unknown error"
      end

    {:error, {:api_error, status, error_message}}
  end

  def handle_response({:error, reason}) do
    {:error, {:connection_error, reason}}
  end

  @doc """
  Performs a health check by validating the API token.
  """
  @spec healthcheck(client()) :: :ok | {:error, term()}
  def healthcheck(client) do
    case Req.get(client, url: "/user/profile") do
      {:ok, %Req.Response{status: 200}} -> :ok
      {:ok, %Req.Response{status: 401}} -> {:error, :unauthorized}
      {:ok, %Req.Response{status: 403}} -> {:error, :forbidden}
      {:ok, %Req.Response{status: status}} -> {:error, {:unexpected_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Extracts rate limit information from response headers.

  Tradier includes the following rate limit headers:
  - X-Ratelimit-Available: Number of requests remaining
  - X-Ratelimit-Expiry: Unix timestamp when the limit resets
  - X-Ratelimit-Used: Number of requests used in current window
  """
  @spec extract_rate_limit(map() | list()) :: rate_limit() | nil
  def extract_rate_limit(headers) when is_map(headers) do
    available = get_header_int(headers, "x-ratelimit-available")
    expiry = get_header_int(headers, "x-ratelimit-expiry")
    used = get_header_int(headers, "x-ratelimit-used")

    if available && expiry && used do
      %{available: available, expiry: expiry, used: used}
    else
      nil
    end
  end

  def extract_rate_limit(headers) when is_list(headers) do
    headers
    |> Enum.map(fn {k, v} -> {String.downcase(k), v} end)
    |> Map.new()
    |> extract_rate_limit()
  end

  def extract_rate_limit(_), do: nil

  defp get_header_int(headers_map, key) do
    case Map.get(headers_map, key) do
      nil ->
        nil

      [value | _] when is_binary(value) ->
        String.to_integer(value)

      value when is_binary(value) ->
        String.to_integer(value)

      value when is_integer(value) ->
        value

      _ ->
        nil
    end
  end

  @doc """
  Handles API response and extracts rate limit information.
  """
  @spec handle_response_with_rate_limit({:ok, Req.Response.t()} | {:error, term()}) ::
          {:ok, map(), rate_limit() | nil} | {:error, term()}
  def handle_response_with_rate_limit(
        {:ok, %Req.Response{status: status, body: body, headers: headers}}
      )
      when status in 200..299 do
    rate_limit = extract_rate_limit(headers)
    {:ok, body, rate_limit}
  end

  def handle_response_with_rate_limit(response) do
    case handle_response(response) do
      {:ok, body} -> {:ok, body, nil}
      error -> error
    end
  end

  defp maybe_add_plug(opts, nil), do: opts
  defp maybe_add_plug(opts, plug), do: Keyword.put(opts, :plug, plug)
end
