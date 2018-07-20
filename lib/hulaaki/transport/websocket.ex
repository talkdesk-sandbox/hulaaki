defmodule Hulaaki.Transport.WebSocket do
  use GenServer
  require Socket
  @behaviour Hulaaki.Transport

  def connect(host, port, opts, timeout) do
    secure = opts |> Keyword.get(:secure, false)
    path = opts |> Keyword.get(:path, "/")

    with conn <- self(),
         {:ok, ws} <-
           Socket.Web.connect(
             {to_string(host), port},
             secure: secure,
             path: path,
             timeout: timeout,
             protocol: ["mqtt"]
           ),
         socket <- %{ws: ws, conn: conn, pid: nil},
         {:ok, pid} <- start_link(socket) do
      Process.link(pid)
      {:ok, %{socket | pid: pid}}
    else
      {:error, "connection refused"} -> {:error, :econnrefused}
      err -> err
    end
  end

  def send(%{ws: ws} = _socket, packet) do
    :ok = Socket.Web.send(ws, {:binary, packet})
  end

  def close(%{ws: ws, pid: pid} = _socket) do
    :ok = GenServer.stop(pid, :normal)
    Socket.Web.close(ws)
  end

  def set_active_once(%{pid: pid} = _socket) do
    GenServer.cast(pid, {:set_active_once, self()})
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(state) do
    GenServer.cast(self(), :receive)
    {:ok, %{state | pid: self()}}
  end

  def handle_cast({:set_active_once, conn}, state) do
    {:noreply, %{state | conn: conn}}
  end

  def handle_cast(:receive, %{ws: ws, conn: conn} = state) do
    case Socket.Web.recv(ws) do
      {:ok, {:binary, bitstring}} ->
        Kernel.send(conn, {:websocket, state, bitstring})
        GenServer.cast(self(), :receive)
        {:noreply, state}

      {:ok, {:close, _, _}} ->
        Kernel.send(conn, {:websocket_closed, state})
        {:noreply, state}

      error ->
        {:stop, error, state}
    end
  end
end
