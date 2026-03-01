%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 01. 10月 2025 19:30
%%%-------------------------------------------------------------------
-module(gms3).
-export([start/1, start/2]).

-define(timeout, 5000).
-define(arghh, 100).

%% 启动第一个节点
start(Id) ->
  Rnd = rand:uniform(1000),
  Self = self(),
  {ok, spawn_link(fun()-> init(Id, Rnd, Self) end)}.

init(Id, Rnd, Master) ->
  rand:seed(exsplus, {Rnd, Rnd, Rnd}),
  leader(Id, Master, 1, [], [Master]).

%% 启动从节点
start(Id, Grp) ->
  Rnd = rand:uniform(1000),
  Self = self(),
  {ok, spawn_link(fun()-> init(Id, Rnd, Grp, Self) end)}.

init(Id, Rnd, Grp, Master) ->
  rand:seed(exsplus, {Rnd, Rnd, Rnd}),
  Self = self(),
  Grp ! {join, Master, Self},
  receive
    {view, N, [Leader|Slaves], Group} ->
      erlang:monitor(process, Leader),
      Master ! {view, Group},
      slave(Id, Master, Leader, N+1, {view, N, [Leader|Slaves], Group},
        Slaves, Group)
  after ?timeout ->
    Master ! {error, "no reply from leader"}
  end.

%% 领导者状态（带序列号）
leader(Id, Master, N, Slaves, Group) ->
  receive
    {mcast, Msg} ->
      bcast(Id, {msg, N, Msg}, Slaves),
      Master ! Msg,
      leader(Id, Master, N+1, Slaves, Group);
    {join, Wrk, Peer} ->
      Slaves2 = lists:append(Slaves, [Peer]),
      Group2 = lists:append(Group, [Wrk]),
      bcast(Id, {view, N, [self()|Slaves2], Group2}, Slaves2),
      Master ! {view, Group2},
      leader(Id, Master, N+1, Slaves2, Group2);
    stop ->
      ok
  end.

%% 从节点状态（带序列号和最后消息）
slave(Id, Master, Leader, N, Last, Slaves, Group) ->
  receive
    {mcast, Msg} ->
      Leader ! {mcast, Msg},
      slave(Id, Master, Leader, N, Last, Slaves, Group);
    {join, Wrk, Peer} ->
      Leader ! {join, Wrk, Peer},
      slave(Id, Master, Leader, N, Last, Slaves, Group);
    {msg, N, Msg} ->
      Master ! Msg,
      slave(Id, Master, Leader, N+1, {msg, N, Msg}, Slaves, Group);
    {msg, I, _} when I < N ->
      slave(Id, Master, Leader, N, Last, Slaves, Group);
    {view, N, [Leader|Slaves2], Group2} ->
      Master ! {view, Group2},
      slave(Id, Master, Leader, N+1, {view, N, [Leader|Slaves2], Group2},
        Slaves2, Group2);
    {view, I, _, _} when I < N ->
      slave(Id, Master, Leader, N, Last, Slaves, Group);
    {'DOWN', _Ref, process, Leader, _Reason} ->
      election(Id, Master, N, Last, Slaves, Group);
    stop ->
      ok
  end.

%% 选举过程（重传最后一条消息）
election(Id, Master, N, Last, Slaves, [_|Group]) ->
  Self = self(),
  case Slaves of
    [Self|Rest] ->
      bcast(Id, Last, Rest),
      bcast(Id, {view, N, Slaves, Group}, Rest),
      Master ! {view, Group},
      leader(Id, Master, N+1, Rest, Group);
    [Leader|Rest] ->
      erlang:monitor(process, Leader),
      slave(Id, Master, Leader, N, Last, Rest, Group)
  end.

%% 带随机崩溃的广播
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
