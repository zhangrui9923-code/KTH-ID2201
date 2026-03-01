%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 06. 10月 2025 23:56
%%%-------------------------------------------------------------------
-module(node2).
-export([start/1, start/2, stop/1]).
-define(Stabilize, 1000).
-define(Timeout, 10000).

%% Start a node
start(Id) ->
  start(Id, nil).

start(Id, Peer) ->
  timer:start(),
  spawn(fun() -> init(Id, Peer) end).

%% Stop a node gracefully
stop(Node) ->
  Node ! stop.

init(Id, Peer) ->
  Predecessor = nil,
  {ok, Successor} = connect(Id, Peer),
  schedule_stabilize(),
  Store = storage:create(),
  io:format("Node ~w started~n", [Id]),
  node(Id, Predecessor, Successor, Store, 0, 0).

%% Connect to the ring
connect(Id, nil) ->
  {ok, {Id, self()}};
connect(_Id, Peer) ->
  Qref = make_ref(),
  Peer ! {key, Qref, self()},
  receive
    {Qref, Skey} ->
      {ok, {Skey, Peer}}
  after ?Timeout ->
    io:format("Connect timeout~n", []),
    {error, timeout}
  end.

%% Main node loop with statistics
node(Id, Predecessor, Successor, Store, AddCount, LookupCount) ->
  receive
  %% Basic ring messages
    {key, Qref, Peer} ->
      Peer ! {Qref, Id},
      node(Id, Predecessor, Successor, Store, AddCount, LookupCount);

    {notify, New} ->
      {Pred, NewStore} = notify(New, Id, Predecessor, Store),
      node(Id, Pred, Successor, NewStore, AddCount, LookupCount);

    {request, Peer} ->
      request(Peer, Predecessor),
      node(Id, Predecessor, Successor, Store, AddCount, LookupCount);

    {status, Pred} ->
      Succ = stabilize(Pred, Id, Successor),
      node(Id, Predecessor, Succ, Store, AddCount, LookupCount);

    stabilize ->
      stabilize(Successor),
      node(Id, Predecessor, Successor, Store, AddCount, LookupCount);

  %% Storage messages
    {add, Key, Value, Qref, Client} ->
      {Added, NewAddCount} = add(Key, Value, Qref, Client, Id,
        Predecessor, Successor, Store, AddCount),
      node(Id, Predecessor, Successor, Added, NewAddCount, LookupCount);

    {lookup, Key, Qref, Client} ->
      NewLookupCount = lookup(Key, Qref, Client, Id, Predecessor,
        Successor, Store, LookupCount),
      node(Id, Predecessor, Successor, Store, AddCount, NewLookupCount);

    {handover, Elements} ->
      Merged = storage:merge(Store, Elements),
      io:format("Node ~w received ~w keys in handover~n",
        [Id, length(Elements)]),
      node(Id, Predecessor, Successor, Merged, AddCount, LookupCount);

  %% Probe messages
    probe ->
      create_probe(Id, Successor),
      node(Id, Predecessor, Successor, Store, AddCount, LookupCount);

    {probe, Id, Nodes, T} ->
      remove_probe(T, Nodes),
      node(Id, Predecessor, Successor, Store, AddCount, LookupCount);

    {probe, Ref, Nodes, T} ->
      forward_probe(Ref, T, Nodes, Id, Successor),
      node(Id, Predecessor, Successor, Store, AddCount, LookupCount);

  %% Debug and control
    status ->
      print_status(Id, Predecessor, Successor, Store, AddCount, LookupCount),
      node(Id, Predecessor, Successor, Store, AddCount, LookupCount);

    stats ->
      io:format("Node ~w stats: ~w adds, ~w lookups~n",
        [Id, AddCount, LookupCount]),
      node(Id, Predecessor, Successor, Store, AddCount, LookupCount);

    {get_store, From} ->
      From ! {store, Store},
      node(Id, Predecessor, Successor, Store, AddCount, LookupCount);

    stop ->
      io:format("Node ~w stopping (processed ~w adds, ~w lookups)~n",
        [Id, AddCount, LookupCount]),
      ok;

    Unknown ->
      io:format("Node ~w: unknown message ~w~n", [Id, Unknown]),
      node(Id, Predecessor, Successor, Store, AddCount, LookupCount)
  end.

%% Stabilization
schedule_stabilize() ->
  timer:send_interval(?Stabilize, self(), stabilize).

stabilize({_, Spid}) ->
  Spid ! {request, self()}.

stabilize(Pred, Id, Successor) ->
  {Skey, Spid} = Successor,
  case Pred of
    nil ->
      Spid ! {notify, {Id, self()}},
      Successor;
    {Id, _} ->
      Successor;
    {Skey, _} ->
      Spid ! {notify, {Id, self()}},
      Successor;
    {Xkey, Xpid} ->
      case key:between(Xkey, Id, Skey) of
        true ->
          Xpid ! {request, self()},
          {Xkey, Xpid};
        false ->
          Spid ! {notify, {Id, self()}},
          Successor
      end
  end.

%% Notify
notify({Nkey, Npid}, Id, Predecessor, Store) ->
  case Predecessor of
    nil ->
      Keep = handover(Id, Store, Nkey, Npid),
      {{Nkey, Npid}, Keep};
    {Pkey, _} ->
      case key:between(Nkey, Pkey, Id) of
        true ->
          Keep = handover(Id, Store, Nkey, Npid),
          {{Nkey, Npid}, Keep};
        false ->
          {Predecessor, Store}
      end
  end.

%% Request
request(Peer, Predecessor) ->
  case Predecessor of
    nil ->
      Peer ! {status, nil};
    {Pkey, Ppid} ->
      Peer ! {status, {Pkey, Ppid}}
  end.

%% Add element - fixed version with statistics
add(Key, Value, Qref, Client, Id, Predecessor, {_, Spid}, Store, AddCount) ->
  case Predecessor of
    nil ->
      %% We're the only node or responsible for all keys
      Client ! {Qref, ok},
      {storage:add(Key, Value, Store), AddCount + 1};
    {Pkey, _} ->
      case key:between(Key, Pkey, Id) of
        true ->
          %% Key belongs to us
          Client ! {Qref, ok},
          {storage:add(Key, Value, Store), AddCount + 1};
        false ->
          %% Forward to successor
          Spid ! {add, Key, Value, Qref, Client},
          {Store, AddCount}
      end
  end.

%% Lookup element - fixed version with statistics
lookup(Key, Qref, Client, Id, Predecessor, {_, Spid}, Store, LookupCount) ->
  case Predecessor of
    nil ->
      %% We're the only node
      Result = storage:lookup(Key, Store),
      Client ! {Qref, Result},
      LookupCount + 1;
    {Pkey, _} ->
      case key:between(Key, Pkey, Id) of
        true ->
          %% Key belongs to us
          Result = storage:lookup(Key, Store),
          Client ! {Qref, Result},
          LookupCount + 1;
        false ->
          %% Forward to successor
          Spid ! {lookup, Key, Qref, Client},
          LookupCount
      end
  end.

%% Handover
handover(Id, Store, Nkey, Npid) ->
  {Keep, Rest} = storage:split(Nkey, Id, Store),
  case length(Rest) of
    0 -> ok;
    N ->
      Npid ! {handover, Rest},
      io:format("Node ~w handed over ~w keys to ~w~n", [Id, N, Nkey])
  end,
  Keep.

%% Probe functions
create_probe(Id, {_, Spid}) ->
  Spid ! {probe, Id, [self()], erlang:system_time(microsecond)}.

remove_probe(T, Nodes) ->
  Time = erlang:system_time(microsecond) - T,
  io:format("Probe: ~w μs, ~w nodes~n", [Time, length(Nodes)]).

forward_probe(Ref, T, Nodes, _Id, {_, Spid}) ->
  Spid ! {probe, Ref, [self()|Nodes], T}.

%% Better status output
print_status(Id, Predecessor, Successor, Store, AddCount, LookupCount) ->
  PredKey = case Predecessor of
              nil -> nil;
              {K, _} -> K
            end,
  {SuccKey, _} = Successor,

  io:format("~n=== Node ~w ===~n", [Id]),
  io:format("  Predecessor: ~w~n", [PredKey]),
  io:format("  Successor:   ~w~n", [SuccKey]),
  io:format("  Store size:  ~w items~n", [length(Store)]),
  io:format("  Statistics:  ~w adds, ~w lookups~n", [AddCount, LookupCount]),

  %% Show range
  case Predecessor of
    nil ->
      io:format("  Range:       all keys~n");
    {PK, _} ->
      io:format("  Range:       (~w, ~w]~n", [PK, Id])
  end,
  io:format("~n").