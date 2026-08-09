defmodule ExTradier.OAuth do
  @moduledoc """
  Tradier OAuth 2.0 authorization code flow.

  Use this when your application acts on behalf of *other* Tradier users. If you
  only ever call the API as yourself, a personal access token passed to
  `ExTradier.Client.new/2` is simpler and this module is unnecessary.

  ## Flow

  1. Send the user to `authorize_url/2`. They approve the requested scopes and
     Tradier redirects back to your application's configured callback with a
     `code` (valid for 10 minutes) and the `state` you supplied.
  2. Exchange that code for an access token with `create_access_token/4`. Access
     tokens are valid for 24 hours.
  3. Approved partners can mint a new access token from a non-expiring refresh
     token with `refresh_access_token/4`.

  ## Example

      url = ExTradier.OAuth.authorize_url("my-client-id",
        scope: [:read, :trade, :market],
        state: state_token
      )
      # ...redirect the user to `url`, then in your callback controller:

      {:ok, token} =
        ExTradier.OAuth.create_access_token("my-client-id", "my-secret", params["code"])

      client = ExTradier.Client.new(token["access_token"], sandbox: false)

  ## Security

  Always generate `:state` per authorization attempt and verify it on the
  callback — it is what protects the exchange from CSRF. The client secret is
  only ever sent from your server via HTTP Basic auth; it must never reach the
  browser.

  > #### Sandbox {: .info}
  >
  > Tradier only documents OAuth against production (`api.tradier.com`).
  > Sandbox accounts use personal access tokens instead.
  """

  @authorize_url "https://api.tradier.com/v1/oauth/authorize"
  @token_base_url "https://api.tradier.com/v1"

  @scopes ~w(read write market trade stream)a

  @type token :: %{String.t() => term()}

  @doc """
  Returns the list of scopes Tradier accepts.

    - `:read` - Account information, positions, and market data
    - `:write` - Modify account data, excluding trades
    - `:market` - Market data
    - `:trade` - Place and manage trades
    - `:stream` - Real-time streaming
  """
  @spec scopes() :: [atom()]
  def scopes, do: @scopes

  @doc """
  Builds the URL to redirect a user to for authorization.

  ## Options

    - `:scope` - Scope atom/string, or list of them (see `scopes/0`)
    - `:state` - Opaque CSRF token echoed back to your callback. Strongly recommended.
    - `:base_url` - Override the authorize endpoint (default: `#{@authorize_url}`)

  ## Examples

      iex> ExTradier.OAuth.authorize_url("abc123", scope: [:read, :trade], state: "xyz")
      "https://api.tradier.com/v1/oauth/authorize?client_id=abc123&scope=read%2Ctrade&state=xyz"

      iex> ExTradier.OAuth.authorize_url("abc123")
      "https://api.tradier.com/v1/oauth/authorize?client_id=abc123"
  """
  @spec authorize_url(String.t(), keyword()) :: String.t()
  def authorize_url(client_id, opts \\ []) when is_binary(client_id) do
    query =
      [
        client_id: client_id,
        scope: encode_scope(Keyword.get(opts, :scope)),
        state: Keyword.get(opts, :state)
      ]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> URI.encode_query()

    Keyword.get(opts, :base_url, @authorize_url) <> "?" <> query
  end

  @doc """
  Exchanges an authorization code for an access token.

  Authenticates with HTTP Basic auth using your client ID and secret, per
  Tradier's OAuth documentation. Returns the decoded token body, which includes
  an `"access_token"` along with its scope and expiry.

  ## Options

    - `:base_url` - Override the API base URL (default: `#{@token_base_url}`)
    - `:plug` - Test plug for `Req.Test`
    - `:req_options` - Extra options merged into the underlying `Req.Request`

  ## Examples

      {:ok, token} = create_access_token("client-id", "client-secret", "auth-code")
      #=> {:ok, %{"access_token" => "...", "expires_in" => 86_399, "scope" => "read trade"}}
  """
  @spec create_access_token(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, token()} | {:error, term()}
  def create_access_token(client_id, client_secret, code, opts \\ []) do
    post_token(client_id, client_secret, "/oauth/accesstoken", opts,
      grant_type: "authorization_code",
      code: code
    )
  end

  @doc """
  Exchanges a refresh token for a new access token.

  Refresh tokens are only issued to approved Tradier partners; other
  integrations must send the user back through `authorize_url/2` when the
  24 hour access token expires.

  Accepts the same options as `create_access_token/4`.
  """
  @spec refresh_access_token(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, token()} | {:error, term()}
  def refresh_access_token(client_id, client_secret, refresh_token, opts \\ []) do
    post_token(client_id, client_secret, "/oauth/refreshtoken", opts,
      grant_type: "refresh_token",
      refresh_token: refresh_token
    )
  end

  @doc """
  Returns the absolute expiry of a token response as a `DateTime`.

  Uses the `"expires_in"` field (seconds) relative to `now`, which defaults to
  the current UTC time. Returns `nil` when the token carries no expiry.

  ## Examples

      iex> now = ~U[2026-08-09 12:00:00Z]
      iex> ExTradier.OAuth.expires_at(%{"expires_in" => 3600}, now)
      ~U[2026-08-09 13:00:00Z]

      iex> ExTradier.OAuth.expires_at(%{"access_token" => "abc"})
      nil
  """
  @spec expires_at(token(), DateTime.t()) :: DateTime.t() | nil
  def expires_at(token, now \\ DateTime.utc_now())

  def expires_at(%{"expires_in" => expires_in}, now) when is_integer(expires_in) do
    DateTime.add(now, expires_in, :second)
  end

  def expires_at(_token, _now), do: nil

  defp post_token(client_id, client_secret, path, opts, form) do
    req_opts =
      [
        base_url: Keyword.get(opts, :base_url, @token_base_url),
        auth: {:basic, "#{client_id}:#{client_secret}"},
        headers: [
          {"accept", "application/json"},
          {"user-agent", ExTradier.Client.user_agent()}
        ],
        retry: :transient,
        retry_delay: &ExTradier.Client.retry_delay/1
      ]
      |> maybe_put(:plug, Keyword.get(opts, :plug))
      |> Keyword.merge(Keyword.get(opts, :req_options, []))

    Req.new(req_opts)
    |> ExTradier.Telemetry.attach()
    |> Req.post(url: path, form: form)
    |> ExTradier.Client.handle_response()
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp encode_scope(nil), do: nil
  defp encode_scope(scope) when is_atom(scope), do: to_string(scope)
  defp encode_scope(scope) when is_binary(scope), do: scope

  defp encode_scope(scopes) when is_list(scopes) do
    scopes |> Enum.map_join(",", &to_string/1) |> nil_if_empty()
  end

  defp nil_if_empty(""), do: nil
  defp nil_if_empty(scope), do: scope
end
