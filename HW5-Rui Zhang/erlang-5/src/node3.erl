%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 07. 10月 2025 0:15
%%%-------------------------------------------------------------------
-module(node3).
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
  Next = nil,
  node(Id, Predecessor, Successor, Next, Store).

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
node(Id, Predecessor, Successor, Next, Store) ->
  receive
  %% Basic ring messages
    {key, Qref, Peer} ->
      Peer ! {Qref, Id},
      node(Id, Predecessor, Successor, Next, Store);

    {notify, New} ->
      {Pred, NewStore} = notify(New, Id, Predecessor, Store),
      node(Id, Pred, Successor, Next, NewStore);

    {request, Peer} ->
      request(Peer, Predecessor, Successor),
      node(Id, Predecessor, Successor, Next, Store);

    {status, Pred, Nx} ->
      {Succ, Nxt} = stabilize(Pred, Nx, Id, Successor),
      node(Id, Predecessor, Succ, Nxt, Store);

    stabilize ->
      stabilize(Successor),
      node(Id, Predecessor, Successor, Next, Store);

  %% Storage messages
    {add, Key, Value, Qref, Client} ->
      Added = add(Key, Value, Qref, Client, Id, Predecessor, Successor, Store),
      node(Id, Predecessor, Successor, Next, Added);

    {lookup, Key, Qref, Client} ->
      lookup(Key, Qref, Client, Id, Predecessor, Successor, Store),
      node(Id, Predecessor, Successor, Next, Store);

    {handover, Elements} ->
      Merged = storage:merge(Store, Elements),
      node(Id, Predecessor, Successor, Next, Merged);

  %% Failure detection
    {'DOWN', Ref, process, _, _} ->
      {Pred, Succ, Nxt} = down(Ref, Predecessor, Successor, Next),
      node(Id, Pred, Succ, Nxt, Store);

  %% Probe messages
    probe ->
      create_probe(Id, Successor),
      node(Id, Predecessor, Successor, Next, Store);

    {probe, Id, Nodes, T} ->
      remove_probe(T, Nodes),
      node(Id, Predecessor, Successor, Next, Store);

    {probe, Ref, Nodes, T} ->
      forward_probe(Ref, T, Nodes, Id, Successor),
      node(Id, Predecessor, Successor, Next, Store);

  %% Debug and control
    status ->
      io:format("Node ~w:~n  Pred: ~w~n  Succ: ~w~n  Next: ~w~n  Store: ~w items~n",
        [Id,
          element(1, if Predecessor =:= nil -> {nil}; true -> Predecessor end),
          element(1, Successor),
          element(1, if Next =:= nil -> {nil}; true -> Next end),
          length(Store)]),
      node(Id, Predecessor, Successor, Next, Store);

    stop ->
      io:format("Node ~w stopping~n", [Id]),
      ok;

    Other ->
      io:format("Node ~w received unknown message: ~w~n", [Id, Other]),
      node(Id, Predecessor, Successor, Next, Store)
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
          %% New node between us and successor
          drop(Sref),
          Xref = monitor(Xpid),
          Xpid ! {request, self()},
          {{Xkey, Xref, Xpid}, Successor};
        false ->
          %% We are between Pred and Successor
          Spid ! {notify, {Id, self()}},
          {Successor, Nx}
      end
  end.

%% Notify
notify({Nkey, Npid}, Id, Predecessor, Store) ->
  case Predecessor of
    nil ->
      Keep = handover(Id, Store, Nkey, Npid),
      Nref = monitor(Npid),
      {{Nkey, Nref, Npid}, Keep};
    {Pkey, Pref, _} ->
      case key:between(Nkey, Pkey, Id) of
        true ->
          Keep = handover(Id, Store, Nkey, Npid),
          drop(Pref),
          Nref = monitor(Npid),
          {{Nkey, Nref, Npid}, Keep};
        false ->
          {Predecessor, Store}
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

%% Storage operations
add(Key, Value, Qref, Client, Id, Predecessor, {_, _, Spid}, Store) ->
  case Predecessor of
    nil ->
      %% We're the only node
      Client ! {Qref, ok},
      storage:add(Key, Value, Store);
    {Pkey, _, _} ->
      case key:between(Key, Pkey, Id) of
        true ->
          Client ! {Qref, ok},
          storage:add(Key, Value, Store);
        false ->
          Spid ! {add, Key, Value, Qref, Client},
          Store
      end
  end.

lookup(Key, Qref, Client, Id, Predecessor, {_, _, Spid}, Store) ->
  case Predecessor of
    nil ->
      %% We're the only node
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

handover(Id, Store, Nkey, Npid) ->
  {Keep, Rest} = storage:split(Nkey, Id, Store),
  Npid ! {handover, Rest},
  Keep.

%% Failure handling
down(Ref, {_, Ref, _}, Successor, Next) ->
  %% Predecessor died
  io:format("Predecessor died~n", []),
  {nil, Successor, Next};

down(Ref, Predecessor, {_, Ref, _}, Next) ->
  %% Successor died
  case Next of
    nil ->
      %% No next node - we're alone now
      io:format("Successor died, no Next node available~n", []),
      {Predecessor, {element(1, Predecessor), nil, self()}, nil};
    {Nkey, Npid} ->
      io:format("Successor died, adopting Next~n", []),
      Nref = monitor(Npid),
      self() ! stabilize,
      {Predecessor, {Nkey, Nref, Npid}, nil}
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