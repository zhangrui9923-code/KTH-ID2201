%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 01. 10月 2025 19:27
%%%-------------------------------------------------------------------
-module(gms1).
-export([start/1, start/2]).

-define(timeout, 5000).

%% 启动第一个节点（领导者）
start(Id) ->
  Self = self(),
  {ok, spawn_link(fun()-> init(Id, Self) end)}.

init(Id, Master) ->
  io:format("gms1 ~w: leader started~n", [Id]),
  leader(Id, Master, [], [Master]).

%% 启动从节点并加入现有组
start(Id, Grp) ->
  Self = self(),
  {ok, spawn_link(fun()-> init(Id, Grp, Self) end)}.

init(Id, Grp, Master) ->
  Self = self(),
  Grp ! {join, Master, Self},
  receive
    {view, [Leader|Slaves], Group} ->
      io:format("gms1 ~w: joined group, leader is ~w~n", [Id, Leader]),
      Master ! {view, Group},
      slave(Id, Master, Leader, Slaves, Group)
  after ?timeout ->
    io:format("gms1 ~w: timeout~n", [Id]),
    Master ! {error, "no reply from leader"}
  end.

%% 领导者状态
leader(Id, Master, Slaves, Group) ->
  receive
    {mcast, Msg} ->
      bcast(Id, {msg, Msg}, Slaves),
      Master ! Msg,
      leader(Id, Master, Slaves, Group);
    {join, Wrk, Peer} ->
      Slaves2 = lists:append(Slaves, [Peer]),
      Group2 = lists:append(Group, [Wrk]),
      io:format("gms1 ~w: adding node, new view: ~w~n", [Id, Group2]),
      bcast(Id, {view, [self()|Slaves2], Group2}, Slaves2),
      Master ! {view, Group2},
      leader(Id, Master, Slaves2, Group2);
    stop ->
      ok
  end.

%% 从节点状态
slave(Id, Master, Leader, Slaves, Group) ->
  receive
    {mcast, Msg} ->
      Leader ! {mcast, Msg},
      slave(Id, Master, Leader, Slaves, Group);
    {join, Wrk, Peer} ->
      Leader ! {join, Wrk, Peer},
      slave(Id, Master, Leader, Slaves, Group);
    {msg, Msg} ->
      Master ! Msg,
      slave(Id, Master, Leader, Slaves, Group);
    {view, [Leader|Slaves2], Group2} ->
      io:format("gms1 ~w: new view ~w~n", [Id, Group2]),
      Master ! {view, Group2},
      slave(Id, Master, Leader, Slaves2, Group2);
    stop ->
      ok
  end.

%% 广播消息到所有节点
bcast(_Id, Msg, Nodes) ->
  lists:foreach(fun(Node) -> Node ! Msg end, Nodes).