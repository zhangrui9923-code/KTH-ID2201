%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 13. 9月 2025 20:16
%%%-------------------------------------------------------------------
-module(intf).
-export([new/0, add/4, remove/2, lookup/2, ref/2, name/2, list/1, broadcast/2]).

%% 返回空的接口集合
new() ->
  [].

%% 添加新的接口条目到集合中
%% Name: 符号名称 (如 london)
%% Ref: 进程引用
%% Pid: 进程标识符
%% Intf: 当前接口集合
%% 返回新的接口集合
add(Name, Ref, Pid, Intf) ->
  % 移除同名的旧条目（如果存在），然后添加新条目
  NewIntf = remove(Name, Intf),
  [{Name, Ref, Pid} | NewIntf].

%% 根据接口名称移除条目
%% Name: 接口名称
%% Intf: 接口集合
%% 返回新的接口集合
remove(Name, Intf) ->
  lists:keydelete(Name, 1, Intf).

%% 根据接口名称查找进程标识符
%% Name: 接口名称
%% Intf: 接口集合
%% 返回 {ok, Pid} 或 notfound
lookup(Name, Intf) ->
  case lists:keyfind(Name, 1, Intf) of
    {Name, _Ref, Pid} -> {ok, Pid};
    false -> notfound
  end.

%% 根据接口名称查找进程引用
%% Name: 接口名称
%% Intf: 接口集合
%% 返回 {ok, Ref} 或 notfound
ref(Name, Intf) ->
  case lists:keyfind(Name, 1, Intf) of
    {Name, Ref, _Pid} -> {ok, Ref};
    false -> notfound
  end.

%% 根据进程引用查找接口名称
%% Ref: 进程引用
%% Intf: 接口集合
%% 返回 {ok, Name} 或 notfound
name(Ref, Intf) ->
  case lists:keyfind(Ref, 2, Intf) of
    {Name, Ref, _Pid} -> {ok, Name};
    false -> notfound
  end.

%% 返回所有接口名称的列表
%% Intf: 接口集合
%% 返回名称列表
list(Intf) ->
  [Name || {Name, _Ref, _Pid} <- Intf].

%% 向所有接口进程广播消息
%% Message: 要发送的消息
%% Intf: 接口集合
%% 无返回值，副作用是发送消息
broadcast(Message, Intf) ->
  lists:foreach(
    fun({_Name, _Ref, Pid}) ->
      Pid ! Message
    end,
    Intf
  ).