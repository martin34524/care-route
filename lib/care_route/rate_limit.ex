defmodule CareRoute.RateLimit do
  @moduledoc """
  Fixed-window rate limits kept in ETS, for actions that cost money (AI calls),
  lean on a free service (place search), or guard a login.

  Counts live in memory on each node, which is enough for a single-instance
  deployment; they reset on restart.

  Limits are named in `config :care_route, :rate_limits` as
  `name: {max_count, window_seconds}`; a name that isn't configured is unlimited,
  and `false` turns all limits off.
  """

  use GenServer

  @table :care_route_rate_limit
  @sweep_every :timer.minutes(1)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc """
  Counts one hit of `name` for `key` (an IP, a conversation id…).
  Returns `:ok`, or `{:error, :rate_limited}` once the window's limit is used up.
  """
  def hit(name, key) do
    case limit(name) do
      nil ->
        :ok

      {max, window} ->
        {id, expires_at} = window_id(name, key, window)
        count = :ets.update_counter(@table, id, {2, 1}, {id, 0, expires_at})
        if count <= max, do: :ok, else: {:error, :rate_limited}
    end
  end

  @doc "Whether `key` has used up `name`'s limit, without counting a hit."
  def limited?(name, key) do
    case limit(name) do
      nil ->
        false

      {max, window} ->
        {id, _expires_at} = window_id(name, key, window)

        case :ets.lookup(@table, id) do
          [{_id, count, _expires_at}] -> count >= max
          [] -> false
        end
    end
  end

  defp limit(name) do
    case Application.get_env(:care_route, :rate_limits) do
      limits when is_list(limits) -> limits[name]
      _disabled -> nil
    end
  end

  defp window_id(name, key, window) do
    now = System.system_time(:second)
    index = div(now, window)
    {{name, key, index}, (index + 1) * window}
  end

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_sweep()
    {:ok, nil}
  end

  # Drops finished windows so the table doesn't grow.
  @impl true
  def handle_info(:sweep, state) do
    now = System.system_time(:second)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_every)
end
