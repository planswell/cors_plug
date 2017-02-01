defmodule CORSPlug do
  import Plug.Conn

  def defaults do
    [
      origin:      "*",
      credentials: true,
      max_age:     1728000,
      headers:     ["Authorization", "Content-Type", "Accept", "Origin",
                    "User-Agent", "DNT","Cache-Control", "X-Mx-ReqToken",
                    "Keep-Alive", "X-Requested-With", "If-Modified-Since",
                    "X-CSRF-Token"],
      expose:      [],
      methods:     ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    ]
  end

  def init(options) do
    Keyword.merge(defaults(), options)
  end

  def call(conn, options) do
    parsed_options = resolve_runtime_options(options)

    conn = put_in(
      conn.resp_headers,
      conn.resp_headers ++ headers(conn, parsed_options))

    case conn.method do
      "OPTIONS" -> conn |> send_resp(204, "") |> halt
      _method   -> conn
    end
  end

  defp resolve_runtime_options(options) do
    options
    |> Keyword.update!(:origin, &resolve_config/1)
    |> Keyword.update!(:max_age, fn max_age ->
      case resolve_config(max_age) do
        number when is_number(number) -> number
        string when is_binary(string) -> String.to_integer(string)
      end
    end)
  end

  # headers specific to OPTIONS request
  defp headers(conn = %Plug.Conn{method: "OPTIONS"}, options) do
    headers(%{conn | method: nil}, options) ++ [
      {"access-control-max-age", "#{options[:max_age]}"},
      {"access-control-allow-headers", allowed_headers(options[:headers], conn)},
      {"access-control-allow-methods", Enum.join(options[:methods], ",")}
    ]
  end

  # universal headers
  defp headers(conn, options) do
    [
      {"access-control-allow-origin", origin(options[:origin], conn)},
      {"access-control-expose-headers", Enum.join(options[:expose], ",")},
      {"access-control-allow-credentials", "#{options[:credentials]}"}
    ]
  end

  # Allow all requested headers
  defp allowed_headers(["*"], conn) do
    get_req_header(conn, "access-control-request-headers")
    |> List.first
  end

  defp allowed_headers(key, _conn) do
    Enum.join(key, ",")
  end

  # return origin if it matches regex, otherwise "null" string
  defp origin(%Regex{} = regex, conn) do
    req_origin = conn |> request_origin |> to_string
    if req_origin =~ regex, do: req_origin, else: "null"
  end

  # normalize non-list to list
  defp origin(key, conn) when not is_list(key) do
    origin(List.wrap(key), conn)
  end

  # whitelist internal requests
  defp origin([:self], conn) do
    request_origin(conn) || "*"
  end

  # return "*" if origin list is ["*"]
  defp origin(["*"], _conn) do
    "*"
  end

  # return request origin if in origin list, otherwise "null" string
  # see: https://www.w3.org/TR/cors/#access-control-allow-origin-response-header
  defp origin(origins, conn) when is_list(origins) do
    req_origin = request_origin(conn)
    if req_origin in origins, do: req_origin, else: "null"
  end

  defp request_origin(%Plug.Conn{req_headers: headers}) do
    Enum.find_value(headers, fn({k, v}) -> k =~ ~r/origin/i && v end)
  end

  # allow config options to be resolved dynamically
  defp resolve_config({:system, var}) do
    System.get_env(var)
  end
  defp resolve_config({module, function}) do
    resolve_config({module, function, []})
  end
  defp resolve_config({module, function, args}) do
    apply(module, function, args)
  end
  defp resolve_config(config) do
    config
  end
end
