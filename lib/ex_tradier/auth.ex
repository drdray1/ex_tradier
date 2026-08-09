defmodule ExTradier.Auth do
  @moduledoc """
  Req plugin for Tradier API Bearer token authentication.

  Automatically attaches the Bearer token to each request.

  ## Usage

  Typically used via `ExTradier.Client.new/2`, but can be attached manually:

      Req.new(base_url: "https://sandbox.tradier.com/v1")
      |> ExTradier.Auth.attach("your_api_token")
  """

  @doc """
  Attaches Bearer token authentication to a Req request.
  """
  @spec attach(Req.Request.t(), String.t()) :: Req.Request.t()
  def attach(%Req.Request{} = request, api_token) do
    request
    |> Req.Request.register_options([:tradier_api_token])
    |> Req.Request.merge_options(tradier_api_token: api_token)
    |> Req.Request.append_request_steps(tradier_auth: &sign_request/1)
  end

  defp sign_request(request) do
    api_token = request.options[:tradier_api_token]

    if api_token do
      Req.Request.put_header(request, "authorization", "Bearer #{api_token}")
    else
      request
    end
  end
end
