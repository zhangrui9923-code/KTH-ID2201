%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 06. 10月 2025 23:55
%%%-------------------------------------------------------------------
-module(node1).
-export([start/1, start/2]).
-define(Stabilize, 1000).
-define(Timeout, 10000).

%% Start a node with given Id
start(Id) ->
  start(Id, nil).

start(Id, Peer) ->
  timer:start(),
  spawn(fun() -> init(Id, Peer) end).

init(Id, Peer) ->
  Predecessor = nil,
  {ok, Successor} = connect(Id, Peer),
  schedule_stabilize(),
  node(Id, Predecessor, Successor).

%% Connect to existing ring or create new one
connect(Id, nil) ->
  {ok, {Id, self()}};
connect(_Id, Peer) ->
  Qref = make_ref(),
  Peer ! {key, Qref, self()},
  receive
    {Qref, Skey} ->
      {ok, {Skey, Peer}}
  after ?Timeout ->
    io:format("Timeout: no response~n", [])
  end.

%% Main node loop
node(Id, Predecessor, Successor) ->
  receive
    {key, Qref, Peer} ->
      Peer ! {Qref, Id},
      node(Id, Predecessor, Successor);

    {notify, New} ->
      Pred = notify(New, Id, Predecessor),
      node(Id, Pred, Successor);

    {request, Peer} ->
      request(Peer, Predecessor),
      node(Id, Predecessor, Successor);

    {status, Pred} ->
      Succ = stabilize(Pred, Id, Successor),
      node(Id, Predecessor, Succ);

    stabilize ->
      stabilize(Successor),
      node(Id, Predecessor, Successor);

    probe ->
      create_probe(Id, Successor),
      node(Id, Predecessor, Successor);

    {probe, Id, Nodes, T} ->
      remove_probe(T, Nodes),
      node(Id, Predecessor, Successor);

    {probe, Ref, Nodes, T} ->
      forward_probe(Ref, T, Nodes, Id, Successor),
      node(Id, Predecessor, Successor);

    status ->
      io:format("Node ~w: Pred=~w, Succ=~w~n",
        [Id, Predecessor, Successor]),
      node(Id, Predecessor, Successor);

    stop ->
      ok;

    _ ->
      node(Id, Predecessor, Successor)
  end.

%% Schedule periodic stabilization
schedule_stabilize() ->
  timer:send_interval(?Stabilize, self(), stabilize).

%% Stabilize procedure - send request to successor
stabilize({_, Spid}) ->
  Spid ! {request, self()}.

%% Handle status message from successor
stabilize(Pred, Id, Successor) ->
  {Skey, Spid} = Successor,
  case Pred of
    nil ->
      %% Successor has no predecessor, notify it
      Spid ! {notify, {Id, self()}},
      Successor;
    {Id, _} ->
      %% Successor's predecessor is us, all good
      Successor;
    {Skey, _} ->
      %% Successor points to itself, notify it
      Spid ! {notify, {Id, self()}},
      Successor;
    {Xkey, Xpid} ->
      %% Check if we should adopt new successor
      case key:between(Xkey, Id, Skey) of
        true ->
          %% New node between us and successor
          Xpid ! {request, self()},
          {Xkey, Xpid};
        false ->
          %% We should be between them
          Spid ! {notify, {Id, self()}},
          Successor
      end
  end.

%% Handle notify message
notify({Nkey, Npid}, Id, Predecessor) ->
  case Predecessor of
    nil ->
      %% No predecessor, accept new node
      {Nkey, Npid};
    {Pkey, _} ->
      %% Check if new node should be our predecessor
      case key:between(Nkey, Pkey, Id) of
        true ->
          %% New node is between current predecessor and us
          {Nkey, Npid};
        false ->
          %% Keep current predecessor
          Predecessor
      end
  end.

%% Handle request message
request(Peer, Predecessor) ->
  case Predecessor of
    nil ->
      Peer ! {status, nil};
    {Pkey, Ppid} ->
      Peer ! {status, {Pkey, Ppid}}
  end.

%% Probe functions for testing ring connectivity
create_probe(Id, {_, Spid}) ->
  Spid ! {probe, Id, [self()], erlang:system_time(microsecond)}.

remove_probe(T, Nodes) ->
  Time = erlang:system_time(microsecond) - T,
  io:format("Probe completed in ~w microseconds, visited ~w nodes~n",
    [Time, length(Nodes)]).

forward_probe(Ref, T, Nodes, Id, {_, Spid}) ->
  Spid ! {probe, Ref, [self()|Nodes], T}.
