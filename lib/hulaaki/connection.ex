defmodule Hulaaki.Connection do
  use GenServer
  alias Hulaaki.Message
  alias Hulaaki.Packet

  defmodule ConnectOptions do
    defstruct [:host, :port]

    def build(host \\ "localhost", port \\ 1883)
    when ( is_binary(host) or is_list(host) )
    and is_integer(port) do
      host = if is_binary(host), do: String.to_char_list(host), else: host
      %ConnectOptions{host: host, port: port}
    end
  end

  defmodule State do
    defstruct [:socket, :client]
  end

  def start_link(client_pid)
  when is_pid(client_pid) do
    GenServer.start_link(__MODULE__, %State{client: client_pid})
  end

  def connect(pid, %Message.Connect{} = message,
              %ConnectOptions{} = connect_opts \\ ConnectOptions.build) do
    GenServer.call(pid, {:connect, message, connect_opts})
  end

  def publish(pid, %Message.Publish{} = message) do
    GenServer.call(pid, {:publish, message})
  end

  def publish_release(pid, %Message.PubRel{} = message) do
    GenServer.call(pid, {:publish_release, message})
  end

  def subscribe(pid, %Message.Subscribe{} = message) do
    GenServer.call(pid, {:subscribe, message})
  end

  def unsubscribe(pid, %Message.Unsubscribe{} = message) do
    GenServer.call(pid, {:unsubscribe, message})
  end

  def ping(pid, %Message.PingReq{} = message \\ Message.ping_request) do
    GenServer.call(pid, {:ping, message})
  end

  def disconnect(pid, %Message.Disconnect{} = message \\ Message.disconnect ) do
    GenServer.call(pid, {:disconnect, message})
  end

  def stop(pid) do
    GenServer.call(pid, :stop)
  end

  ## GenServer callbacks

  def init(%State{} = state) do
    {:ok, %{state | socket: nil} }
  end

  def handle_call(:stop, _from, state) do
    close_tcp_socket(state.socket)
    {:stop, :normal, :ok, state}
  end

  def handle_call({:connect, message, opts}, _from, state) do
    %{socket: socket} = open_tcp_socket(opts)
    dispatch_message(socket, message)
    {:reply, :ok, %{state | socket: socket} }
  end

  def handle_call({_, message}, _from, state) do
    dispatch_message(state.socket, message)
    {:reply, :ok, state}
  end

  def handle_info({:tcp, socket, data}, state) do
    :inet.setopts(socket, active: :once)
    messages = decode_packets(data)
    messages |> Enum.each fn(message) -> Kernel.send state.client, message end
    {:noreply, state}
  end

  defp decode_packets(data) do
    decode_packets(data, [])
  end

  defp decode_packets(data, accumulator) do
    %{message: message, remainder: remainder} = Packet.decode(data)

    case remainder do
      "" -> Enum.reverse [ message | accumulator ]
      _  -> decode_packets(remainder, [ message | accumulator ])
    end
  end

  defp open_tcp_socket(opts) do
    timeout  = 100
    host     = opts.host
    port     = opts.port
    tcp_opts = [:binary, {:active, :once}, {:packet, :raw}]

    {:ok, socket} = :gen_tcp.connect(host, port, tcp_opts, timeout)

    %{socket: socket}
  end

  defp close_tcp_socket(socket) do
    socket |> :gen_tcp.close
  end

  defp dispatch_message(socket, message) do
    packet = Packet.encode(message)
    :inet.setopts(socket, active: :once)
    socket |> :gen_tcp.send packet
  end

end
