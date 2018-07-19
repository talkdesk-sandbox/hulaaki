defmodule Hulaaki.Transport.WebSocket do
  use GenServer
  require Socket
  @behaviour Hulaaki.Transport

  def connect(host, port, opts, timeout) do
    secure = opts |> Keyword.get(:secure, false)
    path = opts |> Keyword.get(:path, "/")

    {:ok, sw} =
      Socket.Web.connect(
        {to_string(host), port},
        secure: secure,
        path: path,
        timeout: timeout,
        protocol: ["mqtt"]
        #protocol: ["mqttv3.1"]
      )
    conn = self()
    {:ok, pid} = start_link(%{sw: sw, conn: conn, pid: nil})
    {:ok, %{sw: sw, pid: pid, conn: conn}}
  end

  def send(%{sw: sw} = _socket, packet) do
    :ok = Socket.Web.send(sw, {:binary, packet})
  end

  def close(%{sw: sw, pid: pid} = _socket) do
    :ok = GenServer.stop(pid, :normal)
    Socket.Web.close(sw)
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

  def handle_cast(:receive, %{sw: sw, conn: conn} = state) do
    case Socket.Web.recv(sw) do
      {:ok, {:binary, bitstring}} ->
        Kernel.send(conn, {:tcp, state, bitstring})
        GenServer.cast(self(), :receive)
        {:noreply, state}

      {:ok, {:close, _, _}} ->
        Kernel.send(conn, {:tcp_closed, state})
        {:stop, :shutdown, state}

      other ->
        # TODO: error handling
        IO.inspect(other)
    end
  end
end
