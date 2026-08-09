defmodule ExTradier.ClientOptionsTest do
  use ExUnit.Case, async: true

  alias ExTradier.{Client, Fixtures}

  doctest ExTradier.Client, only: [to_params: 2, to_form: 2, extract_rate_limit: 1]

  describe "to_params/2" do
    test "accepts a keyword list as well as a map" do
      assert Client.to_params(interval: "daily") == [interval: "daily"]
    end

    test "drops nil values so optional params can be passed unconditionally" do
      assert Client.to_params(interval: "daily", start: nil, end: nil) ==
               [interval: "daily"]
    end

    test "keeps false values, which are meaningful to Tradier" do
      assert Client.to_params(greeks: false) == [greeks: false]
    end

    test "appends overrides last" do
      assert Client.to_params([interval: "daily"], symbol: "AAPL") ==
               [interval: "daily", symbol: "AAPL"]
    end

    test "overrides win over a caller entry with a string key" do
      assert Client.to_params(%{"symbol" => "MSFT"}, symbol: "AAPL") == [symbol: "AAPL"]
    end

    test "overrides win over a caller entry with an atom key" do
      assert Client.to_params(%{symbol: "MSFT"}, symbol: "AAPL") == [symbol: "AAPL"]
    end

    test "returns an empty list for empty params" do
      assert Client.to_params(%{}) == []
    end
  end

  describe "to_form/2" do
    test "stringifies keys and values" do
      assert Client.to_form(symbol: "AAPL", quantity: 100) ==
               [{"symbol", "AAPL"}, {"quantity", "100"}]
    end

    test "stringifies map params regardless of key order" do
      assert Client.to_form(%{symbol: "AAPL", quantity: 100}) |> Enum.sort() ==
               [{"quantity", "100"}, {"symbol", "AAPL"}]
    end

    test "drops nil values" do
      assert Client.to_form(%{symbol: "AAPL", price: nil}) == [{"symbol", "AAPL"}]
    end

    test "overrides win and are stringified" do
      assert Client.to_form(%{preview: false}, preview: true) == [{"preview", "true"}]
    end

    test "handles indexed multileg keys that are already strings" do
      assert Client.to_form(%{"option_symbol[0]" => "AAPL240119C00150000"}) ==
               [{"option_symbol[0]", "AAPL240119C00150000"}]
    end
  end

  describe "retry_delay/1" do
    test "grows exponentially and stays within the jitter window" do
      for {attempt, lower, upper} <- [{0, 250, 500}, {1, 500, 1000}, {2, 1000, 2000}] do
        delays = for _ <- 1..50, do: Client.retry_delay(attempt)

        assert Enum.min(delays) >= lower
        assert Enum.max(delays) <= upper
      end
    end

    test "caps the backoff so a long retry chain cannot stall for minutes" do
      delays = for _ <- 1..50, do: Client.retry_delay(10)

      assert Enum.max(delays) <= 8_000
      assert Enum.min(delays) >= 4_000
    end

    test "jitters rather than returning a fixed delay" do
      delays = for _ <- 1..50, do: Client.retry_delay(3)

      assert Enum.uniq(delays) |> length() > 1
    end
  end

  describe "user_agent/0" do
    test "identifies the library and Elixir version" do
      assert Client.user_agent() =~ ~r{^ex_tradier/[\w.\-]+ \(Elixir #{System.version()}\)$}
    end

    test "is sent on every request" do
      Req.Test.expect(ExTradier.ClientOptionsTest.UserAgent, fn conn ->
        assert Plug.Conn.get_req_header(conn, "user-agent") == [Client.user_agent()]
        Req.Test.json(conn, Fixtures.profile_response())
      end)

      client = Fixtures.test_client(ExTradier.ClientOptionsTest.UserAgent)
      assert {:ok, _} = ExTradier.User.get_profile(client)
    end
  end

  describe "new/2 options" do
    test "merges req_options into the request" do
      client = Client.new("token", req_options: [receive_timeout: 1_234])

      assert client.options[:receive_timeout] == 1_234
    end

    test "req_options take precedence over the defaults" do
      client = Client.new("token", req_options: [max_retries: 9])

      assert client.options[:max_retries] == 9
    end

    test "applies the documented defaults" do
      client = Client.new("token")

      assert client.options[:retry] == :transient
      assert client.options[:max_retries] == 3
      assert client.options[:retry_log_level] == :warning
      assert client.options[:receive_timeout] == 30_000
    end

    test "allows disabling retries and retry logging" do
      client = Client.new("token", retry: false, retry_log_level: false)

      assert client.options[:retry] == false
      assert client.options[:retry_log_level] == false
    end
  end

  describe "extract_rate_limit/1 with the allowed header" do
    test "parses all four documented headers" do
      headers = %{
        "x-ratelimit-allowed" => ["120"],
        "x-ratelimit-available" => ["119"],
        "x-ratelimit-used" => ["1"],
        "x-ratelimit-expiry" => ["1705084860000"]
      }

      assert Client.extract_rate_limit(headers) == %{
               allowed: 120,
               available: 119,
               used: 1,
               expiry: 1_705_084_860_000
             }
    end

    test "parses the allowed header from the legacy list format" do
      headers = [{"X-Ratelimit-Allowed", "120"}]

      assert %{allowed: 120} = Client.extract_rate_limit(headers)
    end
  end
end
