%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 13. 9月 2025 12:43
%%%-------------------------------------------------------------------
-module(map).
-export([new/0, update/3, reachable/2, all_nodes/1]).

%% 返回一个空的地图（空列表）
new() ->
  [].

%% 更新地图，Node有到Links列表中所有节点的方向性连接
%% 旧条目会被移除
update(Node, Links, Map) ->
  % 移除旧条目（如果存在）
  MapWithoutOld = lists:keydelete(Node, 1, Map),
  % 添加新条目
  [{Node, Links} | MapWithoutOld].

%% 返回从Node直接可达的节点列表
reachable(Node, Map) ->
  case lists:keyfind(Node, 1, Map) of
    {Node, Links} -> Links;
    false -> []
  end.

%% 返回地图中所有节点的列表，包括没有出边的节点
all_nodes(Map) ->
  % 获取所有有出边的节点
  NodesWithOutgoing = [Node || {Node, _Links} <- Map],
  % 获取所有目标节点（可能没有出边）
  AllTargets = lists:flatten([Links || {_Node, Links} <- Map]),
  % 合并并去重
  AllNodes = NodesWithOutgoing ++ AllTargets,
  lists:usort(AllNodes).
