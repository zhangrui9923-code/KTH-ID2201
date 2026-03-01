-module(test).
-compile(export_all).
-define(Timeout, 1000).

%% Starting up nodes
start(Module) ->
  Id = key:generate(),
  apply(Module, start, [Id]).

start(Module, P) ->
  Id = key:generate(),
  apply(Module, start, [Id, P]).

start(_, 0, _) ->
  ok;
start(Module, N, P) ->
  start(Module, P),
  start(Module, N-1, P).

%% Basic operations
add(Key, Value, P) ->
  Q = make_ref(),
  P ! {add, Key, Value, Q, self()},
  receive
    {Q, ok} ->
      ok
  after ?Timeout ->
    {error, "timeout"}
  end.

lookup(Key, Node) ->
  Q = make_ref(),
  Node ! {lookup, Key, Q, self()},
  receive
    {Q, Value} ->
      Value
  after ?Timeout ->
    {error, "timeout"}
  end.

%% Generate random keys
keys(N) ->
  lists:map(fun(_) -> key:generate() end, lists:seq(1, N)).

%% Add all keys
add(Keys, P) ->
  lists:foreach(fun(K) -> add(K, gurka, P) end, Keys).

%% Check all keys
check(Keys, P) ->
  T1 = erlang:system_time(microsecond),
  {Failed, Timeout} = check(Keys, P, 0, 0),
  T2 = erlang:system_time(microsecond),
  Done = (T2 - T1) / 1000,
  io:format("~w lookups in ~.2f ms (~.2f μs per lookup)~n",
    [length(Keys), Done, (T2-T1)/length(Keys)]),
  io:format("~w failed, ~w timeouts~n", [Failed, Timeout]),
  ok.

check([], _, Failed, Timeout) ->
  {Failed, Timeout};
check([Key|Keys], P, Failed, Timeout) ->
  case lookup(Key, P) of
    {Key, _} ->
      check(Keys, P, Failed, Timeout);
    {error, _} ->
      check(Keys, P, Failed, Timeout+1);
    false ->
      check(Keys, P, Failed+1, Timeout)
  end.

%% ========== Performance Testing Functions ==========

%% Split list into N chunks
split_list(List, N) ->
  Len = length(List),
  ChunkSize = max(1, Len div N),
  split_list_helper(List, ChunkSize, []).

split_list_helper([], _, Acc) ->
  lists:reverse(Acc);
split_list_helper(List, Size, Acc) ->
  case length(List) =< Size of
    true ->
      lists:reverse([List | Acc]);
    false ->
      {Chunk, Rest} = lists:split(Size, List),
      split_list_helper(Rest, Size, [Chunk | Acc])
  end.

%% Concurrent add - simulate multiple clients
concurrent_add(NumClients, KeysPerClient, Node) ->
  io:format("~n=== Concurrent Add Test ===~n"),
  io:format("Clients: ~w, Keys per client: ~w~n",
    [NumClients, KeysPerClient]),

  Parent = self(),
  AllKeys = keys(NumClients * KeysPerClient),
  KeyGroups = split_list(AllKeys, NumClients),

  T1 = erlang:system_time(microsecond),

  Pids = lists:map(
    fun(ClientKeys) ->
      spawn(fun() ->
        lists:foreach(fun(K) ->
          add(K, gurka, Node)
                      end, ClientKeys),
        Parent ! {done, self(), length(ClientKeys)}
            end)
    end,
    KeyGroups),

  %% Wait for all clients
  TotalAdded = lists:foldl(
    fun(Pid, Acc) ->
      receive
        {done, Pid, Count} -> Acc + Count
      after 60000 ->
        io:format("Client ~w timeout~n", [Pid]),
        Acc
      end
    end,
    0,
    Pids),

  T2 = erlang:system_time(microsecond),
  Time = (T2 - T1) / 1000,

  io:format("Added ~w keys in ~.2f ms~n", [TotalAdded, Time]),
  io:format("Throughput: ~.2f keys/sec~n",
    [TotalAdded / (Time/1000)]),

  AllKeys.

%% Concurrent lookup - simulate multiple clients
concurrent_check(Keys, NumClients, Node) ->
  io:format("~n=== Concurrent Lookup Test ===~n"),
  io:format("Clients: ~w, Total keys: ~w~n",
    [NumClients, length(Keys)]),

  Parent = self(),
  KeyGroups = split_list(Keys, NumClients),

  T1 = erlang:system_time(microsecond),

  Pids = lists:map(
    fun(ClientKeys) ->
      spawn(fun() ->
        Result = check_keys(ClientKeys, Node),
        Parent ! {done, self(), Result}
            end)
    end,
    KeyGroups),

  %% Collect results
  {TotalChecked, TotalFailed, TotalTimeout} = lists:foldl(
    fun(Pid, {Checked, Failed, Timeout}) ->
      receive
        {done, Pid, {C, F, T}} ->
          {Checked + C, Failed + F, Timeout + T}
      after 60000 ->
        {Checked, Failed, Timeout}
      end
    end,
    {0, 0, 0},
    Pids),

  T2 = erlang:system_time(microsecond),
  Time = (T2 - T1) / 1000,

  io:format("Checked ~w keys in ~.2f ms~n", [TotalChecked, Time]),
  io:format("~w failed, ~w timeouts~n", [TotalFailed, TotalTimeout]),
  io:format("Throughput: ~.2f lookups/sec~n",
    [TotalChecked / (Time/1000)]),

  ok.

check_keys(Keys, Node) ->
  check_keys(Keys, Node, 0, 0, 0).

check_keys([], _, Checked, Failed, Timeout) ->
  {Checked, Failed, Timeout};
check_keys([Key|Keys], Node, Checked, Failed, Timeout) ->
  case lookup(Key, Node) of
    {Key, _} ->
      check_keys(Keys, Node, Checked+1, Failed, Timeout);
    {error, _} ->
      check_keys(Keys, Node, Checked+1, Failed, Timeout+1);
    false ->
      check_keys(Keys, Node, Checked+1, Failed+1, Timeout)
  end.

%% Performance benchmarks
benchmark(single_node_4000) ->
  io:format("~n========================================~n"),
  io:format("Benchmark: Single Node, 4000 elements~n"),
  io:format("========================================~n"),

  N1 = node2:start(key:generate()),
  timer:sleep(500),

  Keys = keys(4000),

  io:format("~nAdding 4000 keys...~n"),
  T1 = erlang:system_time(microsecond),
  add(Keys, N1),
  T2 = erlang:system_time(microsecond),
  io:format("Add time: ~.2f ms~n", [(T2-T1)/1000]),

  timer:sleep(500),

  io:format("~nLooking up 4000 keys...~n"),
  check(Keys, N1),

  N1 ! stop,
  Keys;

benchmark(four_nodes_1000_each) ->
  io:format("~n========================================~n"),
  io:format("Benchmark: 4 Nodes, 1000 keys each~n"),
  io:format("========================================~n"),

  N1 = node2:start(key:generate()),
  N2 = node2:start(key:generate(), N1),
  N3 = node2:start(key:generate(), N1),
  N4 = node2:start(key:generate(), N1),

  io:format("Waiting for stabilization...~n"),
  timer:sleep(3000),

  N1 ! status,
  N2 ! status,
  N3 ! status,
  N4 ! status,

  %% Use concurrent add
  Keys = concurrent_add(4, 1000, N1),

  timer:sleep(1000),

  io:format("~nLooking up all keys...~n"),
  check(Keys, N1),

  lists:foreach(fun(N) -> N ! stop end, [N1, N2, N3, N4]),
  Keys;

benchmark(distributed_clients) ->
  io:format("~n========================================~n"),
  io:format("Benchmark: Distributed Client Access~n"),
  io:format("========================================~n"),

  N1 = node2:start(key:generate()),
  N2 = node2:start(key:generate(), N1),
  N3 = node2:start(key:generate(), N1),
  N4 = node2:start(key:generate(), N1),

  timer:sleep(3000),

  Nodes = [N1, N2, N3, N4],
  Keys = keys(4000),

  io:format("~nTest 1: All clients access N1~n"),
  T1 = erlang:system_time(microsecond),
  concurrent_add(4, 1000, N1),
  T2 = erlang:system_time(microsecond),
  io:format("Time: ~.2f ms~n", [(T2-T1)/1000]),

  timer:sleep(1000),

  io:format("~nTest 2: Clients distributed across nodes~n"),
  Parent = self(),
  T3 = erlang:system_time(microsecond),

  lists:foreach(
    fun({Node, I}) ->
      spawn(fun() ->
        ClientKeys = keys(1000),
        add(ClientKeys, Node),
        Parent ! {done, I}
            end)
    end,
    lists:zip(Nodes, lists:seq(1,4))),

  lists:foreach(fun(I) ->
    receive {done, I} -> ok end
                end, lists:seq(1,4)),

  T4 = erlang:system_time(microsecond),
  io:format("Time: ~.2f ms~n", [(T4-T3)/1000]),

  lists:foreach(fun(N) -> N ! stop end, Nodes),
  ok;

benchmark(large_scale_10000) ->
  io:format("~n========================================~n"),
  io:format("Benchmark: Large Scale - 10000 elements~n"),
  io:format("========================================~n"),

  io:format("~nTest 1: Single node~n"),
  N1 = node2:start(key:generate()),
  timer:sleep(500),

  Keys1 = keys(10000),
  T1 = erlang:system_time(microsecond),
  add(Keys1, N1),
  T2 = erlang:system_time(microsecond),
  io:format("Add time: ~.2f ms~n", [(T2-T1)/1000]),

  check(Keys1, N1),
  N1 ! stop,

  io:format("~nTest 2: Four nodes~n"),
  N1b = node2:start(key:generate()),
  N2b = node2:start(key:generate(), N1b),
  N3b = node2:start(key:generate(), N1b),
  N4b = node2:start(key:generate(), N1b),
  timer:sleep(3000),

  Keys2 = keys(10000),
  T3 = erlang:system_time(microsecond),
  add(Keys2, N1b),
  T4 = erlang:system_time(microsecond),
  io:format("Add time: ~.2f ms~n", [(T4-T3)/1000]),

  check(Keys2, N1b),

  lists:foreach(fun(N) -> N ! stop end, [N1b, N2b, N3b, N4b]),
  ok.

%% Run all benchmarks
run_all_benchmarks() ->
  benchmark(single_node_4000),
  timer:sleep(1000),
  benchmark(four_nodes_1000_each),
  timer:sleep(1000),
  benchmark(distributed_clients),
  timer:sleep(1000),
  benchmark(large_scale_10000),
  ok.


    








