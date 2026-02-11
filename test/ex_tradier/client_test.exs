defmodule ExTradier.ClientTest do
  use ExUnit.Case, async: true

  alias ExTradier.{Client, Fixtures}

  describe "new/2" do
    test "creates a Req.Request client" do
      client = Client.new("test_token")
      assert %Req.Request{} = client
    end

    test "creates client with test plug" do
      client = Client.new("test_token", plug: {Req.Test, __MODULE__})
      assert %Req.Request{} = client
    end
  end

  describe "base_url/1" do
    test "returns sandbox URL by default" do
      assert Client.base_url() == "https://sandbox.tradier.com/v1"
      assert Client.base_url(true) == "https://sandbox.tradier.com/v1"
    end

    test "returns production URL when sandbox is false" do
      assert Client.base_url(false) == "https://api.tradier.com/v1"
    end
  end

  describe "sandbox_url/0" do
    test "returns sandbox URL constant" do
      assert Client.sandbox_url() == "https://sandbox.tradier.com/v1"
    end
  end

  describe "production_url/0" do
    test "returns production URL constant" do
      assert Client.production_url() == "https://api.tradier.com/v1"
    end
  end

  describe "websocket_url/1" do
    test "returns production WebSocket URL by default" do
      assert Client.websocket_url() == "wss://ws.tradier.com/v1"
      assert Client.websocket_url(false) == "wss://ws.tradier.com/v1"
    end

    test "returns sandbox WebSocket URL" do
      assert Client.websocket_url(true) == "wss://sandbox-ws.tradier.com/v1"
    end
  end

  describe "handle_response/1" do
    test "returns ok for 200 response" do
      response = {:ok, %Req.Response{status: 200, body: %{"data" => "test"}}}
      assert {:ok, %{"data" => "test"}} = Client.handle_response(response)
    end

    test "returns unauthorized for 401" do
      response = {:ok, %Req.Response{status: 401, body: %{}}}
      assert {:error, :unauthorized} = Client.handle_response(response)
    end

    test "returns forbidden for 403" do
      response = {:ok, %Req.Response{status: 403, body: %{}}}
      assert {:error, :forbidden} = Client.handle_response(response)
    end

    test "returns not_found for 404" do
      response = {:ok, %Req.Response{status: 404, body: %{}}}
      assert {:error, :not_found} = Client.handle_response(response)
    end

    test "returns rate_limited for 429" do
      response = {:ok, %Req.Response{status: 429, body: %{}}}
      assert {:error, :rate_limited} = Client.handle_response(response)
    end

    test "returns api_error for other 4xx/5xx" do
      response =
        {:ok,
         %Req.Response{
           status: 500,
           body: %{"errors" => %{"error" => "Internal server error"}}
         }}

      assert {:error, {:api_error, 500, "Internal server error"}} =
               Client.handle_response(response)
    end

    test "returns connection_error for transport errors" do
      response = {:error, %Mint.TransportError{reason: :timeout}}
      assert {:error, {:connection_error, _}} = Client.handle_response(response)
    end
  end

  describe "handle_response_with_rate_limit/1" do
    test "returns body and rate limit for 200 with headers" do
      response =
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"data" => "test"},
           headers: %{
             "x-ratelimit-available" => ["119"],
             "x-ratelimit-expiry" => ["1705084860"],
             "x-ratelimit-used" => ["1"]
           }
         }}

      assert {:ok, %{"data" => "test"}, %{available: 119, expiry: 1_705_084_860, used: 1}} =
               Client.handle_response_with_rate_limit(response)
    end

    test "returns nil rate limit when headers missing" do
      response =
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"data" => "test"},
           headers: %{}
         }}

      assert {:ok, %{"data" => "test"}, nil} = Client.handle_response_with_rate_limit(response)
    end

    test "passes through errors" do
      response = {:ok, %Req.Response{status: 401, body: %{}}}
      assert {:error, :unauthorized} = Client.handle_response_with_rate_limit(response)
    end
  end

  describe "extract_rate_limit/1" do
    test "extracts rate limit from map headers" do
      headers = %{
        "x-ratelimit-available" => ["119"],
        "x-ratelimit-expiry" => ["1705084860"],
        "x-ratelimit-used" => ["1"]
      }

      assert %{available: 119, expiry: 1_705_084_860, used: 1} =
               Client.extract_rate_limit(headers)
    end

    test "returns nil when headers are missing" do
      assert Client.extract_rate_limit(%{}) == nil
    end

    test "extracts from list headers (legacy format)" do
      headers = [
        {"X-Ratelimit-Available", "119"},
        {"X-Ratelimit-Expiry", "1705084860"},
        {"X-Ratelimit-Used", "1"}
      ]

      assert %{available: 119, expiry: 1_705_084_860, used: 1} =
               Client.extract_rate_limit(headers)
    end
  end

  describe "validate_token/1" do
    test "returns ok for valid token" do
      Req.Test.expect(ExTradier.ClientTest.ValidateToken, fn conn ->
        assert conn.request_path == "/v1/user/profile"
        Req.Test.json(conn, Fixtures.profile_response())
      end)

      client = Fixtures.test_client(ExTradier.ClientTest.ValidateToken)
      assert {:ok, :valid} = Client.validate_token(client)
    end

    test "returns unauthorized for invalid token" do
      Req.Test.expect(ExTradier.ClientTest.ValidateTokenUnauth, fn conn ->
        conn
        |> Plug.Conn.put_status(401)
        |> Req.Test.json(%{"error" => "unauthorized"})
      end)

      client = Fixtures.test_client(ExTradier.ClientTest.ValidateTokenUnauth)
      assert {:error, :unauthorized} = Client.validate_token(client)
    end
  end

  describe "verify_credentials/2" do
    test "returns profile on success" do
      Req.Test.expect(ExTradier.ClientTest.VerifySuccess, fn conn ->
        assert conn.request_path == "/v1/user/profile"
        Req.Test.json(conn, Fixtures.profile_response())
      end)

      # Use plug option to inject test stub
      client = Fixtures.test_client(ExTradier.ClientTest.VerifySuccess)

      case Req.get(client, url: "/user/profile") do
        {:ok, %Req.Response{status: 200, body: body}} ->
          assert body["profile"]["name"] == "George Costanza"

        other ->
          flunk("Expected success, got #{inspect(other)}")
      end
    end
  end

  describe "get_quotes/2" do
    test "fetches quotes for a symbol" do
      Req.Test.expect(ExTradier.ClientTest.Quotes, fn conn ->
        assert conn.request_path == "/v1/markets/quotes"
        Req.Test.json(conn, Fixtures.quote_response())
      end)

      client = Fixtures.test_client(ExTradier.ClientTest.Quotes)
      assert {:ok, [quote]} = Client.get_quotes(client, "AAPL")
      assert quote["symbol"] == "AAPL"
    end

    test "fetches quotes for multiple symbols" do
      Req.Test.expect(ExTradier.ClientTest.MultiQuotes, fn conn ->
        Req.Test.json(conn, Fixtures.quotes_response())
      end)

      client = Fixtures.test_client(ExTradier.ClientTest.MultiQuotes)
      assert {:ok, quotes} = Client.get_quotes(client, ["AAPL", "MSFT"])
      assert length(quotes) == 2
    end
  end

  describe "get_quote/2" do
    test "fetches single quote" do
      Req.Test.expect(ExTradier.ClientTest.SingleQuote, fn conn ->
        Req.Test.json(conn, Fixtures.quote_response())
      end)

      client = Fixtures.test_client(ExTradier.ClientTest.SingleQuote)
      assert {:ok, quote} = Client.get_quote(client, "AAPL")
      assert quote["symbol"] == "AAPL"
    end
  end

  describe "healthcheck/1" do
    test "returns ok for healthy API" do
      Req.Test.expect(ExTradier.ClientTest.Health, fn conn ->
        Req.Test.json(conn, Fixtures.profile_response())
      end)

      client = Fixtures.test_client(ExTradier.ClientTest.Health)
      assert :ok = Client.healthcheck(client)
    end

    test "returns unauthorized error" do
      Req.Test.expect(ExTradier.ClientTest.HealthUnauth, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{})
      end)

      client = Fixtures.test_client(ExTradier.ClientTest.HealthUnauth)
      assert {:error, :unauthorized} = Client.healthcheck(client)
    end

    test "returns forbidden error" do
      Req.Test.expect(ExTradier.ClientTest.HealthForbid, fn conn ->
        conn |> Plug.Conn.put_status(403) |> Req.Test.json(%{})
      end)

      client = Fixtures.test_client(ExTradier.ClientTest.HealthForbid)
      assert {:error, :forbidden} = Client.healthcheck(client)
    end

    test "returns unexpected status error" do
      Req.Test.expect(ExTradier.ClientTest.Health418, fn conn ->
        conn |> Plug.Conn.put_status(418) |> Req.Test.json(%{})
      end)

      client = Fixtures.test_client(ExTradier.ClientTest.Health418)
      assert {:error, {:unexpected_status, 418}} = Client.healthcheck(client)
    end
  end

  describe "get_quotes/2 error paths" do
    test "returns error for non-200 status" do
      Req.Test.expect(ExTradier.ClientTest.QuotesError, fn conn ->
        conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{})
      end)

      client = Fixtures.test_client(ExTradier.ClientTest.QuotesError)
      assert {:error, _} = Client.get_quotes(client, "AAPL")
    end

    test "handles list of symbols" do
      Req.Test.expect(ExTradier.ClientTest.QuotesList, fn conn ->
        Req.Test.json(conn, Fixtures.quotes_response())
      end)

      client = Fixtures.test_client(ExTradier.ClientTest.QuotesList)
      assert {:ok, quotes} = Client.get_quotes(client, ["AAPL", "MSFT"])
      assert length(quotes) == 2
    end
  end

  describe "get_quote/2 edge cases" do
    test "returns single quote from response" do
      Req.Test.expect(ExTradier.ClientTest.SingleQuoteWrap, fn conn ->
        Req.Test.json(conn, Fixtures.quote_response())
      end)

      client = Fixtures.test_client(ExTradier.ClientTest.SingleQuoteWrap)
      assert {:ok, quote} = Client.get_quote(client, "AAPL")
      assert quote["symbol"] == "AAPL"
    end

    test "returns first quote when multiple returned" do
      Req.Test.expect(ExTradier.ClientTest.MultiQuoteWrap, fn conn ->
        Req.Test.json(conn, Fixtures.quotes_response())
      end)

      client = Fixtures.test_client(ExTradier.ClientTest.MultiQuoteWrap)
      assert {:ok, quote} = Client.get_quote(client, "AAPL,MSFT")
      assert is_map(quote)
    end
  end

  describe "handle_response/1 edge cases" do
    test "handles binary error body" do
      response =
        {:ok,
         %Req.Response{
           status: 500,
           body: "Internal server error"
         }}

      assert {:error, {:api_error, 500, "Internal server error"}} =
               Client.handle_response(response)
    end

    test "handles non-map non-binary body" do
      response =
        {:ok,
         %Req.Response{
           status: 500,
           body: nil
         }}

      assert {:error, {:api_error, 500, "Unknown error"}} =
               Client.handle_response(response)
    end

    test "handles map body without errors key" do
      response =
        {:ok,
         %Req.Response{
           status: 500,
           body: %{"something" => "else"}
         }}

      assert {:error, {:api_error, 500, "Unknown error"}} =
               Client.handle_response(response)
    end
  end

  describe "extract_rate_limit/1 edge cases" do
    test "returns nil for non-map non-list" do
      assert Client.extract_rate_limit("invalid") == nil
    end

    test "returns nil for partial headers" do
      headers = %{
        "x-ratelimit-available" => ["119"]
      }

      assert Client.extract_rate_limit(headers) == nil
    end
  end

  describe "handle_response/1 2xx range" do
    test "returns ok for 201 response" do
      response = {:ok, %Req.Response{status: 201, body: %{"data" => "created"}}}
      assert {:ok, %{"data" => "created"}} = Client.handle_response(response)
    end
  end

  describe "new/2 options" do
    test "creates client with production mode" do
      client = Client.new("test_token", sandbox: false)
      assert %Req.Request{} = client
    end
  end

  describe "extract_rate_limit/1 with string values" do
    test "handles direct string values (not wrapped in list)" do
      headers = %{
        "x-ratelimit-available" => "119",
        "x-ratelimit-expiry" => "1705084860",
        "x-ratelimit-used" => "1"
      }

      assert %{available: 119, expiry: 1_705_084_860, used: 1} =
               Client.extract_rate_limit(headers)
    end

    test "handles integer values" do
      headers = %{
        "x-ratelimit-available" => 119,
        "x-ratelimit-expiry" => 1_705_084_860,
        "x-ratelimit-used" => 1
      }

      assert %{available: 119, expiry: 1_705_084_860, used: 1} =
               Client.extract_rate_limit(headers)
    end

    test "returns nil for unsupported value types" do
      headers = %{
        "x-ratelimit-available" => {:tuple, "value"},
        "x-ratelimit-expiry" => [1_705_084_860],
        "x-ratelimit-used" => [1]
      }

      assert Client.extract_rate_limit(headers) == nil
    end
  end

  describe "handle_response/1 with nested body" do
    test "returns body as-is for successful response" do
      response = {:ok, %Req.Response{status: 200, body: %{"quotes" => %{"quote" => %{"symbol" => "AAPL"}}}}}
      assert {:ok, %{"quotes" => _}} = Client.handle_response(response)
    end
  end
end
