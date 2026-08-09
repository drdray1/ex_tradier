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

  @typedoc """
  Rate limit state parsed from Tradier's `X-Ratelimit-*` response headers.

  Any field is `nil` when Tradier omitted the corresponding header. `:expiry` is
  a Unix timestamp **in milliseconds**, not seconds.
  """
  @type rate_limit :: %{
          allowed: non_neg_integer() | nil,
          available: non_neg_integer() | nil,
          expiry: non_neg_integer() | nil,
          used: non_neg_integer() | nil
        }

  # Retry backoff: doubles per attempt, capped, with jitter over the top half of
  # the window so that concurrent clients do not retry in lockstep.
  @retry_base_delay_ms 500
  @retry_max_delay_ms 8_000

  @default_receive_timeout 30_000

  @doc """
  Creates a client from application configuration.

      config :ex_tradier,
        api_token: System.get_env("TRADIER_API_TOKEN"),
        sandbox: System.get_env("TRADIER_SANDBOX", "true") == "true"

  Raises if `:api_token` is not configured. Pass the token explicitly to
  `new/2` when you hold tokens per user rather than per application — for
  example after an `ExTradier.OAuth` exchange.
  """
  @spec new() :: client()
  def new do
    case Application.get_env(:ex_tradier, :api_token) do
      token when is_binary(token) and token != "" ->
        new(token, sandbox: configured_sandbox())

      _ ->
        raise ArgumentError, """
        no Tradier API token configured.

        Set one in config:

            config :ex_tradier, api_token: System.get_env("TRADIER_API_TOKEN")

        or pass it explicitly with ExTradier.Client.new(token).
        """
    end
  end

  @doc """
  Creates a new Tradier API client with authentication token.

  ## Options

    - `:sandbox` - Use sandbox environment (default: the configured
      `:sandbox` value, or `true`)
    - `:plug` - Test plug for `Req.Test` (default: `nil`)
    - `:telemetry` - Emit `ExTradier.Telemetry` events (default: `true`)
    - `:retry` - Req retry mode (default: `:transient`)
    - `:max_retries` - Maximum retry attempts (default: `3`)
    - `:retry_log_level` - Level for Req's retry logs, or `false` (default: `:warning`)
    - `:receive_timeout` - Response receive timeout in ms (default: `30_000`)
    - `:req_options` - Extra options merged into the underlying `Req.Request`,
      as an escape hatch for anything not exposed above

  ## Examples

      # Longer timeout, no retries, custom Finch pool
      ExTradier.Client.new("token",
        retry: false,
        receive_timeout: 60_000,
        req_options: [finch: [name: MyApp.Finch]]
      )
  """
  @spec new(String.t(), keyword()) :: client()
  def new(api_token, opts \\ []) do
    sandbox = Keyword.get_lazy(opts, :sandbox, &configured_sandbox/0)

    req_opts =
      [
        base_url: base_url(sandbox),
        headers: [{"accept", "application/json"}, {"user-agent", user_agent()}],
        retry: Keyword.get(opts, :retry, :transient),
        max_retries: Keyword.get(opts, :max_retries, 3),
        retry_delay: &retry_delay/1,
        retry_log_level: Keyword.get(opts, :retry_log_level, :warning),
        receive_timeout: Keyword.get(opts, :receive_timeout, @default_receive_timeout)
      ]
      |> maybe_add_plug(Keyword.get(opts, :plug))
      |> Keyword.merge(Keyword.get(opts, :req_options, []))

    Req.new(req_opts)
    |> Req.Request.put_private(:ex_tradier_sandbox, sandbox)
    |> ExTradier.Auth.attach(api_token)
    |> maybe_attach_telemetry(Keyword.get(opts, :telemetry, true))
  end

  @doc """
  Returns the retry backoff in milliseconds for a zero-based retry attempt.

  Doubles per attempt up to #{@retry_max_delay_ms}ms, jittered across the top
  half of the window so retries from concurrent clients spread out.
  """
  @spec retry_delay(non_neg_integer()) :: non_neg_integer()
  def retry_delay(attempt) when is_integer(attempt) and attempt >= 0 do
    capped = min(@retry_base_delay_ms * Integer.pow(2, attempt), @retry_max_delay_ms)
    half = div(capped, 2)
    half + :rand.uniform(half + 1) - 1
  end

  @doc """
  Returns the `user-agent` header value sent with every request.
  """
  @spec user_agent() :: String.t()
  def user_agent do
    version =
      case :application.get_key(:ex_tradier, :vsn) do
        {:ok, vsn} -> List.to_string(vsn)
        _ -> "dev"
      end

    "ex_tradier/#{version} (Elixir #{System.version()})"
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
  Normalizes caller-supplied params into a list for `Req`'s `:params` option.

  Accepts a map or keyword list. Entries with `nil` values are dropped, so
  callers can pass optional params unconditionally. `overrides` are appended
  last and win over any caller entry with the same key, whether the caller used
  an atom or a string key.

  ## Examples

      iex> ExTradier.Client.to_params(interval: "daily", start: nil)
      [interval: "daily"]

      iex> ExTradier.Client.to_params(%{"symbol" => "MSFT"}, symbol: "AAPL")
      [symbol: "AAPL"]
  """
  @spec to_params(map() | keyword(), keyword()) :: [{atom() | String.t(), term()}]
  def to_params(params, overrides \\ []) do
    params
    |> drop_nils_and_overridden(overrides)
    |> Enum.concat(overrides)
  end

  @doc """
  Normalizes caller-supplied params into string tuples for `Req`'s `:form` option.

  Follows the same rules as `to_params/2`, additionally stringifying keys and
  values since form bodies are always URL-encoded text.

  ## Examples

      iex> ExTradier.Client.to_form(symbol: "AAPL", quantity: 100)
      [{"symbol", "AAPL"}, {"quantity", "100"}]

      iex> ExTradier.Client.to_form(%{preview: false}, preview: true)
      [{"preview", "true"}]
  """
  @spec to_form(map() | keyword(), keyword()) :: [{String.t(), String.t()}]
  def to_form(params, overrides \\ []) do
    params
    |> drop_nils_and_overridden(overrides)
    |> Enum.concat(overrides)
    |> Enum.map(fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  defp drop_nils_and_overridden(params, overrides) do
    overridden = MapSet.new(overrides, fn {key, _value} -> to_string(key) end)

    Enum.reject(params, fn {key, value} ->
      is_nil(value) or MapSet.member?(overridden, to_string(key))
    end)
  end

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

  Tradier includes the following rate limit headers on every response:

    - `X-Ratelimit-Allowed` - Maximum requests permitted per interval
    - `X-Ratelimit-Available` - Requests remaining before the limit is hit
    - `X-Ratelimit-Used` - Requests consumed in the current interval
    - `X-Ratelimit-Expiry` - Unix timestamp **in milliseconds** when the counter resets

  Returns a `t:rate_limit/0` map when at least one header is present, with `nil`
  for any header Tradier omitted, or `nil` when none are present.

  ## Examples

      iex> ExTradier.Client.extract_rate_limit(%{"x-ratelimit-available" => ["119"]})
      %{allowed: nil, available: 119, expiry: nil, used: nil}

      iex> ExTradier.Client.extract_rate_limit(%{})
      nil
  """
  @spec extract_rate_limit(map() | list() | term()) :: rate_limit() | nil
  def extract_rate_limit(headers) when is_map(headers) and not is_struct(headers) do
    rate_limit = %{
      allowed: get_header_int(headers, "x-ratelimit-allowed"),
      available: get_header_int(headers, "x-ratelimit-available"),
      expiry: get_header_int(headers, "x-ratelimit-expiry"),
      used: get_header_int(headers, "x-ratelimit-used")
    }

    if Enum.any?(rate_limit, fn {_key, value} -> value != nil end) do
      rate_limit
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

  defp configured_sandbox do
    case Application.get_env(:ex_tradier, :sandbox, true) do
      sandbox when is_boolean(sandbox) -> sandbox
      _ -> true
    end
  end

  defp maybe_add_plug(opts, nil), do: opts
  defp maybe_add_plug(opts, plug), do: Keyword.put(opts, :plug, plug)

  defp maybe_attach_telemetry(request, false), do: request
  defp maybe_attach_telemetry(request, _enabled), do: ExTradier.Telemetry.attach(request)
end
