%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 13. 9月 2025 20:23
%%%-------------------------------------------------------------------
-module(hist).
-export([new/1, update/3]).

%% 创建新的历史记录
%% Name: 本地路由器名称，来自Name的消息总是被视为旧消息
%% 返回初始历史记录结构
new(Name) ->
  % 为本地路由器设置一个非常大的计数器值，
  % 这样任何来自本地路由器的消息都会被视为旧消息
  [{Name, infinity}].

%% 更新历史记录并检查消息是否为新消息
%% Node: 发送消息的节点名称
%% N: 消息编号
%% History: 当前历史记录
%% 返回: old 或 {new, UpdatedHistory}
update(Node, N, History) ->
  case lists:keyfind(Node, 1, History) of
    % 情况1: 找到该节点的历史记录
    {Node, LastSeen} ->
      if
      % 消息编号小于等于已见过的最大编号，是旧消息
        N =< LastSeen ->
          old;
      % 消息编号大于已见过的最大编号，是新消息
        N > LastSeen ->
          % 更新该节点的最大消息编号
          UpdatedHistory = lists:keyreplace(Node, 1, History, {Node, N}),
          {new, UpdatedHistory}
      end;

    % 情况2: 第一次见到来自该节点的消息
    false ->
      % 添加新节点记录
      UpdatedHistory = [{Node, N} | History],
      {new, UpdatedHistory}
  end.