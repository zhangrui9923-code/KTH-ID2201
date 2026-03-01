%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 01. 10月 2025 20:36
%%%-------------------------------------------------------------------
-module(gms4).
-export([start/1, start/2]).

-define(timeout, 5000).
-define(arghh, 100).
-define(ack_timeout, 1000).

start(Id) ->
  Rnd = rand:uniform(1000),
  Self = self(),
  {ok, spawn_link(fun()-> init(Id, Rnd, Self) end)}.

init(Id, Rnd, Master) ->
  rand:seed(exsplus, {Rnd, Rnd, Rnd}),
  io:format("gms4 ~w: leader started~n", [Id]),
  leader(Id, Master, 1, [], [Master]).

start(Id, Grp) ->
  Rnd = rand:uniform(1000),
  Self = self(),
  {ok, spawn_link(fun()-> init(Id, Rnd, Grp, Self) end)}.

init(Id, Rnd, Grp, Master) ->
  rand:seed(exsplus, {Rnd, Rnd, Rnd}),
  Self = self(),
  Grp ! {join, Master, Self},
  receive
    {view, N, [Leader|Slaves], Group, Ref} ->
      %% 立即发送 ACK
      Leader ! {ack, Ref, Self},
      io:format("gms4 ~w: joined group, leader is ~w~n", [Id, Leader]),
      erlang:monitor(process, Leader),
      Master ! {view, Group},
      slave(Id, Master, Leader, N+1,
        {view, N, [Leader|Slaves], Group, Ref},
        Slaves, Group)
  after ?timeout ->
    io:format("gms4 ~w: timeout~n", [Id]),
    Master ! {error, "no reply from leader"}
  end.

leader(Id, Master, N, Slaves, Group) ->
  receive
    {mcast, Msg} ->
      Ref = make_ref(),
      bcast_reliable(Id, {msg, N, Msg, Ref}, Slaves, Ref),
      Master ! Msg,
      leader(Id, Master, N+1, Slaves, Group);

    {join, Wrk, Peer} ->
      Slaves2 = lists:append(Slaves, [Peer]),
      Group2 = lists:append(Group, [Wrk]),
      io:format("gms4 ~w: adding node, new view: ~w~n", [Id, Group2]),
      Ref = make_ref(),
      bcast_reliable(Id, {view, N, [self()|Slaves2], Group2, Ref},
        Slaves2, Ref),
      Master ! {view, Group2},
      leader(Id, Master, N+1, Slaves2, Group2);

    stop ->
      ok
  end.

bcast_reliable(Id, Msg, Nodes, Ref) ->
  lists:foreach(fun(Node) ->
    Node ! Msg,
    crash(Id)
                end, Nodes),
  wait_for_acks(Id, Nodes, Ref, Msg).

wait_for_acks(_Id, [], _Ref, _Msg) ->
  ok;
wait_for_acks(Id, Nodes, Ref, Msg) ->
  receive
    {ack, Ref, From} ->
      Nodes2 = lists:delete(From, Nodes),
      wait_for_acks(Id, Nodes2, Ref, Msg)
  after ?ack_timeout ->
    io:format("leader ~w: retransmitting to ~w nodes~n",
      [Id, length(Nodes)]),
    lists:foreach(fun(Node) -> Node ! Msg end, Nodes),
    wait_for_acks(Id, Nodes, Ref, Msg)
  end.

slave(Id, Master, Leader, N, Last, Slaves, Group) ->
  receive
    {mcast, Msg} ->
      Leader ! {mcast, Msg},
      slave(Id, Master, Leader, N, Last, Slaves, Group);

    {join, Wrk, Peer} ->
      Leader ! {join, Wrk, Peer},
      slave(Id, Master, Leader, N, Last, Slaves, Group);

    {msg, N, Msg, Ref} ->
      Leader ! {ack, Ref, self()},
      Master ! Msg,
      slave(Id, Master, Leader, N+1, {msg, N, Msg, Ref}, Slaves, Group);

    {msg, I, _, Ref} when I < N ->
      %% 重复消息，发送 ACK
      Leader ! {ack, Ref, self()},
      slave(Id, Master, Leader, N, Last, Slaves, Group);

    {view, N, [Leader|Slaves2], Group2, Ref} ->
      Leader ! {ack, Ref, self()},
      io:format("gms4 ~w: new view ~w~n", [Id, Group2]),
      Master ! {view, Group2},
      slave(Id, Master, Leader, N+1,
        {view, N, [Leader|Slaves2], Group2, Ref}, Slaves2, Group2);

    {view, I, [Leader|_], _, Ref} when I < N ->
      %% 重复视图，发送 ACK
      Leader ! {ack, Ref, self()},
      slave(Id, Master, Leader, N, Last, Slaves, Group);

    {'DOWN', _Ref, process, Leader, _Reason} ->
      election(Id, Master, N, Last, Slaves, Group);

    stop ->
      ok
  end.

election(Id, Master, N, Last, Slaves, [_|Group]) ->
  Self = self(),
  case Slaves of
    [Self|Rest] ->
      LastWithoutRef = remove_ref(Last),
      bcast(Id, LastWithoutRef, Rest),
      bcast(Id, {view, N, Slaves, Group}, Rest),
      Master ! {view, Group},
      leader(Id, Master, N+1, Rest, Group);
    [Leader|Rest] ->
      erlang:monitor(process, Leader),
      slave(Id, Master, Leader, N, Last, Rest, Group)
  end.

remove_ref({msg, N, Msg, _Ref}) -> {msg, N, Msg, make_ref()};
remove_ref({view, N, Peers, Group, _Ref}) -> {view, N, Peers, Group, make_ref()};
remove_ref(Other) -> Other.

bcast(Id, Msg, Nodes) ->
  lists:foreach(fun(Node) ->
    Node ! Msg,
    crash(Id)
                end, Nodes).

crash(Id) ->
  case rand:uniform(?arghh) of
    ?arghh ->
      io:format("leader ~w: crash~n", [Id]),
      exit(no_luck);
    _ ->
      ok
  end.
