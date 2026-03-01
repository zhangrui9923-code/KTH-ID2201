%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 13. 9月 2025 19:53
%%%-------------------------------------------------------------------
-module(dijkstra).
-export([table/2, route/2]).
-export([entry/2, replace/4, update/4, iterate/3]). % 导出用于测试

%% 返回到达Node的最短路径长度，如果节点未找到则返回0
entry(Node, Sorted) ->
  case lists:keyfind(Node, 1, Sorted) of
    {Node, Length, _Gateway} -> Length;
    false -> 0
  end.

%% 替换Sorted列表中Node的条目，使用新的长度N和Gateway
%% 要求Node必须在列表中存在，返回的列表按路径长度排序
replace(Node, N, Gateway, Sorted) ->
  % 移除旧条目
  NewSorted = lists:keydelete(Node, 1, Sorted),
  % 插入新条目并保持排序
  insert_sorted({Node, N, Gateway}, NewSorted).

%% 更新排序列表：只有当新路径更短时才更新
%% 如果节点不存在，不添加新条目
update(Node, N, Gateway, Sorted) ->
  CurrentLength = entry(Node, Sorted),
  if
  % 如果节点不存在（CurrentLength == 0）或者新路径不更短，不更新
    CurrentLength == 0 orelse N >= CurrentLength ->
      Sorted;
  % 如果新路径更短，替换现有条目
    N < CurrentLength ->
      replace(Node, N, Gateway, Sorted)
  end.

%% 辅助函数：将条目插入到排序列表中的正确位置
insert_sorted(Entry, []) ->
  [Entry];
insert_sorted({Node, Length, Gateway} = Entry, [{N, L, G} = Head | Tail]) ->
  if
    Length =< L ->
      [Entry, Head | Tail];
    true ->
      [Head | insert_sorted(Entry, Tail)]
  end.

%% Dijkstra算法的核心迭代函数
%% 构建路由表：给定排序的节点列表、地图和已构建的表
iterate(Sorted, Map, Table) ->
  case Sorted of
    % 情况1：排序列表为空，路由表完成
    [] ->
      Table;

    % 情况2：第一个条目是无限路径的虚拟条目，说明剩余节点都不可达
    [{_Node, inf, _Gateway} | _Rest] ->
      Table;

    % 情况3：处理第一个条目
    [{Node, Length, Gateway} | RestSorted] ->
      % 将当前节点添加到路由表中（只保存节点和网关）
      NewTable = [{Node, Gateway} | Table],

      % 获取从当前节点可达的所有节点
      Reachable = map:reachable(Node, Map),

      % 更新排序列表：对每个可达节点，尝试通过当前路径更新
      UpdatedSorted = update_reachable(Reachable, Length + 1, Gateway, RestSorted),

      % 继续迭代
      iterate(UpdatedSorted, Map, NewTable)
  end.

%% 辅助函数：更新所有可达节点的路径信息
update_reachable([], _NewLength, _Gateway, Sorted) ->
  Sorted;
update_reachable([ReachableNode | Rest], NewLength, Gateway, Sorted) ->
  % 尝试更新这个可达节点的路径
  UpdatedSorted = update(ReachableNode, NewLength, Gateway, Sorted),
  % 继续处理其他可达节点
  update_reachable(Rest, NewLength, Gateway, UpdatedSorted).

%% 主要导出函数：构建路由表
%% 给定网关列表和地图，生成完整的路由表
table(Gateways, Map) ->
  % 获取地图中的所有节点
  AllNodes = map:all_nodes(Map),

  % 构建初始排序列表
  InitialSorted = build_initial_sorted(AllNodes, Gateways),

  % 使用iterate函数构建路由表
  iterate(InitialSorted, Map, []).

%% 主要导出函数：在路由表中查找到达指定节点的网关
route(Node, Table) ->
  case lists:keyfind(Node, 1, Table) of
    {Node, Gateway} -> {ok, Gateway};
    false -> notfound
  end.

%% 辅助函数：构建初始排序列表
%% 网关节点距离为0，其他节点距离为infinity
build_initial_sorted(AllNodes, Gateways) ->
  % 为所有节点创建条目
  InitialEntries = lists:map(
    fun(Node) ->
      case lists:member(Node, Gateways) of
        true -> {Node, 0, Node};  % 网关：距离0，网关是自己
        false -> {Node, inf, unknown}  % 其他节点：距离无限，网关未知
      end
    end,
    AllNodes
  ),
  % 按距离排序（0 < inf）
  lists:sort(fun({_, Len1, _}, {_, Len2, _}) -> Len1 =< Len2 end, InitialEntries).