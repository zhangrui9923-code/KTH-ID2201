%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 07. 10月 2025 0:15
%%%-------------------------------------------------------------------
-module(node4).
-export([start/1, start/2]).
-define(Stabilize, 1000).
-define(Timeout, 10000).

%% Start a node
start(Id) ->
  start(Id, nil).

start(Id, Peer) ->
  timer:start(),
  spawn(fun() -> init(Id, Peer) end).

init(Id, Peer) ->
  Predecessor = nil,
  {ok, Successor} = connect(Id, Peer),
  schedule_stabilize(),
  Store = storage:create(),
  Replica = storage:create(),
  Next = nil,
  node(Id, Predecessor, Successor, Next, Store, Replica).

%% Connect to the ring
connect(Id, nil) ->
  {ok, {Id, nil, self()}};
connect(_Id, Peer) ->
  Qref = make_ref(),
  Peer ! {key, Qref, self()},
  receive
    {Qref, Skey} ->
      Ref = monitor(Peer),
      {ok, {Skey, Ref, Peer}}
  after ?Timeout ->
    io:format("Timeout: no response~n", []),
    {error, timeout}
  end.

%% Main node loop
node(Id, Predecessor, Successor, Next, Store, Replica) ->
  receive
  %% Basic ring messages
    {key, Qref, Peer} ->
      Peer ! {Qref, Id},
      node(Id, Predecessor, Successor, Next, Store, Replica);

    {notify, New} ->
      {Pred, NewStore, NewReplica} = notify(New, Id, Predecessor, Store, Replica),
      node(Id, Pred, Successor, Next, NewStore, NewReplica);

    {request, Peer} ->
      request(Peer, Predecessor, Successor),
      node(Id, Predecessor, Successor, Next, Store, Replica);

    {status, Pred, Nx} ->
      {Succ, Nxt} = stabilize(Pred, Nx, Id, Successor),
      node(Id, Predecessor, Succ, Nxt, Store, Replica);

    stabilize ->
      stabilize(Successor),
      node(Id, Predecessor, Successor, Next, Store, Replica);

  %% Storage messages
    {add, Key, Value, Qref, Client} ->
      {Added, Repl} = add(Key, Value, Qref, Client, Id, Predecessor, Successor, Store, Replica),
      node(Id, Predecessor, Successor, Next, Added, Repl);

    {lookup, Key, Qref, Client} ->
      lookup(Key, Qref, Client, Id, Predecessor, Successor, Store),
      node(Id, Predecessor, Successor, Next, Store, Replica);

    {handover, Elements, ReplicaElements} ->
      MergedStore = storage:merge(Store, Elements),
      MergedReplica = storage:merge(Replica, ReplicaElements),
      node(Id, Predecessor, Successor, Next, MergedStore, MergedReplica);

    {replicate, Key, Value} ->
      NewReplica = storage:add(Key, Value, Replica),
      node(Id, Predecessor, Successor, Next, Store, NewReplica);

  %% Failure detection
    {'DOWN', Ref, process, _, _} ->
      {Pred, Succ, Nxt, NewStore} = down(Ref, Predecessor, Successor, Next, Store, Replica),
      NewReplica = storage:create(),
      node(Id, Pred, Succ, Nxt, NewStore, NewReplica);

  %% Probe messages
    probe ->
      create_probe(Id, Successor),
      node(Id, Predecessor, Successor, Next, Store, Replica);

    {probe, Id, Nodes, T} ->
      remove_probe(T, Nodes),
      node(Id, Predecessor, Successor, Next, Store, Replica);

    {probe, Ref, Nodes, T} ->
      forward_probe(Ref, T, Nodes, Id, Successor),
      node(Id, Predecessor, Successor, Next, Store, Replica);

  %% Debug and control
    status ->
      io:format("Node ~w:~n  Pred: ~w~n  Succ: ~w~n  Next: ~w~n  Store: ~w items~n  Replica: ~w items~n",
        [Id,
          element(1, if Predecessor =:= nil -> {nil}; true -> Predecessor end),
          element(1, Successor),
          element(1, if Next =:= nil -> {nil}; true -> Next end),
          length(Store),
          length(Replica)]),
      node(Id, Predecessor, Successor, Next, Store, Replica);

    stop ->
      io:format("Node ~w stopping~n", [Id]),
      ok;

    Other ->
      io:format("Node ~w received unknown message: ~w~n", [Id, Other]),
      node(Id, Predecessor, Successor, Next, Store, Replica)
  end.

%% Stabilization
schedule_stabilize() ->
  timer:send_interval(?Stabilize, self(), stabilize).

stabilize({_, _, Spid}) ->
  Spid ! {request, self()}.

stabilize(Pred, Nx, Id, Successor) ->
  {Skey, Sref, Spid} = Successor,
  case Pred of
    nil ->
      Spid ! {notify, {Id, self()}},
      {Successor, Nx};
    {Id, _} ->
      {Successor, Nx};
    {Skey, _} ->
      Spid ! {notify, {Id, self()}},
      {Successor, Nx};
    {Xkey, Xpid} ->
      case key:between(Xkey, Id, Skey) of
        true ->
          drop(Sref),
          Xref = monitor(Xpid),
          Xpid ! {request, self()},
          {{Xkey, Xref, Xpid}, Successor};
        false ->
          Spid ! {notify, {Id, self()}},
          {Successor, Nx}
      end
  end.

%% Notify with replica handling
notify({Nkey, Npid}, Id, Predecessor, Store, Replica) ->
  case Predecessor of
    nil ->
      {StoreKeep, ReplicaKeep} = handover(Id, Store, Replica, Nkey, Npid),
      Nref = monitor(Npid),
      {{Nkey, Nref, Npid}, StoreKeep, ReplicaKeep};
    {Pkey, Pref, _} ->
      case key:between(Nkey, Pkey, Id) of
        true ->
          {StoreKeep, ReplicaKeep} = handover(Id, Store, Replica, Nkey, Npid),
          drop(Pref),
          Nref = monitor(Npid),
          {{Nkey, Nref, Npid}, StoreKeep, ReplicaKeep};
        false ->
          {Predecessor, Store, Replica}
      end
  end.

%% Request
request(Peer, Predecessor, {Skey, _, Spid}) ->
  case Predecessor of
    nil ->
      Peer ! {status, nil, {Skey, Spid}};
    {Pkey, _, Ppid} ->
      Peer ! {status, {Pkey, Ppid}, {Skey, Spid}}
  end.

%% Add with replication
add(Key, Value, Qref, Client, Id, Predecessor, {_, _, Spid}, Store, Replica) ->
  case Predecessor of
    nil ->
      Spid ! {replicate, Key, Value},
      Client ! {Qref, ok},
      {storage:add(Key, Value, Store), Replica};
    {Pkey, _, _} ->
      case key:between(Key, Pkey, Id) of
        true ->
          Spid ! {replicate, Key, Value},
          Client ! {Qref, ok},
          {storage:add(Key, Value, Store), Replica};
        false ->
          Spid ! {add, Key, Value, Qref, Client},
          {Store, Replica}
      end
  end.

%% Lookup
lookup(Key, Qref, Client, Id, Predecessor, {_, _, Spid}, Store) ->
  case Predecessor of
    nil ->
      Result = storage:lookup(Key, Store),
      Client ! {Qref, Result};
    {Pkey, _, _} ->
      case key:between(Key, Pkey, Id) of
        true ->
          Result = storage:lookup(Key, Store),
          Client ! {Qref, Result};
        false ->
          Spid ! {lookup, Key, Qref, Client}
      end
  end.

%% Handover both Store and Replica
handover(Id, Store, Replica, Nkey, Npid) ->
  {StoreKeep, StoreRest} = storage:split(Nkey, Id, Store),
  {ReplicaKeep, ReplicaRest} = storage:split(Nkey, Id, Replica),
  Npid ! {handover, StoreRest, ReplicaRest},
  {StoreKeep, ReplicaKeep}.

%% Handle node failures with replica
down(Ref, {_, Ref, _}, Successor, Next, Store, Replica) ->
  io:format("Predecessor died, merging replica into store~n", []),
  NewStore = storage:merge(Store, Replica),
  {nil, Successor, Next, NewStore};

down(Ref, Predecessor, {_, Ref, _}, Next, Store, _Replica) ->
  case Next of
    nil ->
      io:format("Successor died, no Next node available~n", []),
      {Predecessor, {element(1, Predecessor), nil, self()}, nil, Store};
    {Nkey, Npid} ->
      io:format("Successor died, adopting Next~n", []),
      Nref = monitor(Npid),
      self() ! stabilize,
      {Predecessor, {Nkey, Nref, Npid}, nil, Store}
  end.

%% Monitor utilities
monitor(Pid) ->
  erlang:monitor(process, Pid).

drop(nil) ->
  ok;
drop(Ref) ->
  erlang:demonitor(Ref, [flush]).

%% Probe functions
create_probe(Id, {_, _, Spid}) ->
  Spid ! {probe, Id, [self()], erlang:system_time(microsecond)}.

remove_probe(T, Nodes) ->
  Time = erlang:system_time(microsecond) - T,
  io:format("Probe completed in ~w microseconds, visited ~w nodes: ~w~n",
    [Time, length(Nodes), lists:reverse(Nodes)]).

forward_probe(Ref, T, Nodes, _Id, {_, _, Spid}) ->
  Spid ! {probe, Ref, [self()|Nodes], T}.