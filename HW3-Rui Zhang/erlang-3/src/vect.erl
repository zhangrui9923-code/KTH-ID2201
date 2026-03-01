%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 20. 9月 2025 22:57
%%%-------------------------------------------------------------------
-module(vect).
-export([zero/0, inc/2, merge/2, leq/2, clock/1, update/3, safe/2,test_clock/0,test/0,test_basic/0,test_concurrent/0,is_concurrent/2,format_vector/1]).

%% ============================================================================
%% 向量时钟基本操作
%% ============================================================================

%% 返回初始向量时间戳（空列表）
zero() ->
  [].

%% 为指定进程增加时钟值
%% Name: 进程名称
%% Time: 当前向量时间戳
%% 返回：更新后的向量时间戳
inc(Name, Time) ->
  case lists:keyfind(Name, 1, Time) of
    {Name, Value} ->
      % 如果找到该进程的条目，增加其值
      lists:keyreplace(Name, 1, Time, {Name, Value + 1});
    false ->
      % 如果没有找到，添加新条目，值为1
      [{Name, 1} | Time]
  end.

%% 合并两个向量时间戳（取每个进程的最大值）
%% Ti, Tj: 两个向量时间戳
%% 返回：合并后的向量时间戳
merge([], Time) ->
  Time;
merge([{Name, Ti} | Rest], Time) ->
  case lists:keyfind(Name, 1, Time) of
    {Name, Tj} ->
      % 取最大值并继续合并
      MaxValue = max(Ti, Tj),
      [{Name, MaxValue} | merge(Rest, lists:keydelete(Name, 1, Time))];
    false ->
      % 如果另一个时间戳中没有此进程，直接保留
      [{Name, Ti} | merge(Rest, Time)]
  end.

%% 比较两个向量时间戳
%% Ti =< Tj 当且仅当对于Ti中的每个条目，Tj中对应条目都大于等于它
%% Ti, Tj: 两个向量时间戳
%% 返回：true如果Ti =< Tj，否则false
leq([], _) ->
  % 空向量时间戳小于等于任何时间戳
  true;
leq([{Name, Ti} | Rest], Time) ->
  case lists:keyfind(Name, 1, Time) of
    {Name, Tj} ->
      if
        Ti =< Tj ->
          % 这个条目满足条件，检查其余条目
          leq(Rest, Time);
        true ->
          % 这个条目不满足条件
          false
      end;
    false ->
      % 如果Tj中没有Name的条目，意味着Tj[Name] = 0
      % Ti > 0时，Ti > Tj[Name]，所以返回false
      Ti =< 0
  end.

%% ============================================================================
%% Logger时钟管理（向量时钟版本）
%% ============================================================================

%% 创建初始时钟来跟踪节点
%% Nodes: 节点列表（在向量时钟中这个参数实际上不需要）
%% 返回：初始时钟（空列表，表示没有看到任何消息）
clock(_Nodes) ->
  % 向量时钟的优势：不需要预先知道有多少节点
  [].

%% 更新时钟
%% From: 发送消息的节点
%% Time: 消息的向量时间戳
%% Clock: 当前时钟状态
%% 返回：更新后的时钟
update(From, Time, Clock) ->
  % 从消息的时间戳中提取发送者的时间值
  {From, TimeValue} = case lists:keyfind(From, 1, Time) of
                        {From, Value} -> {From, Value};
                        false -> {From, 0}  % 如果消息时间戳中没有发送者条目，使用0
                      end,

  % 更新时钟中发送者的条目
  case lists:keyfind(From, 1, Clock) of
    {From, _} ->
      % 更新现有条目
      lists:keyreplace(From, 1, Clock, {From, TimeValue});
    false ->
      % 添加新条目
      [{From, TimeValue} | Clock]
  end.

%% 判断某个时间的事件是否可以安全打印
%% Time: 事件的向量时间戳
%% Clock: 当前时钟状态
%% 返回：true如果安全，false如果还需要等待
safe(Time, Clock) ->
  % 一个事件是安全的，当且仅当：
  % 对于Time中的每个条目{Name, Value}，Clock中都有对应条目且其值 >= Value
  % 这等价于检查 Time =< Clock
  leq(Time, Clock).

%% ============================================================================
%% 调试和测试函数
%% ============================================================================

%% 测试基本向量时钟操作
test_basic() ->
  io:format("=== 测试基本向量时钟操作 ===~n"),

  % 测试初始值
  T0 = zero(),
  io:format("初始时间: ~p~n", [T0]),

  % 测试递增
  T1 = inc(john, T0),
  T2 = inc(paul, T1),
  T3 = inc(john, T2),
  io:format("递增过程: ~p -> ~p -> ~p -> ~p~n", [T0, T1, T2, T3]),

  % 测试合并
  T4 = inc(ringo, zero()),
  T5 = inc(ringo, T4),
  T6 = merge(T3, T5),
  io:format("合并 ~p 和 ~p: ~p~n", [T3, T5, T6]),

  % 测试比较
  io:format("~p =< ~p: ~w~n", [T3, T6, leq(T3, T6)]),
  io:format("~p =< ~p: ~w~n", [T6, T3, leq(T6, T3)]),
  io:format("~p =< ~p: ~w~n", [T1, T2, leq(T1, T2)]).

%% 测试时钟管理
test_clock() ->
  io:format("~n=== 测试向量时钟管理 ===~n"),

  % 创建时钟
  Clock0 = clock([john, paul, ringo]),
  io:format("初始时钟: ~p~n", [Clock0]),

  % 更新时钟
  Time1 = [{john, 3}, {paul, 1}],
  Clock1 = update(john, Time1, Clock0),

  Time2 = [{paul, 2}, {ringo, 1}],
  Clock2 = update(paul, Time2, Clock1),

  Time3 = [{ringo, 2}, {john, 1}],
  Clock3 = update(ringo, Time3, Clock2),

  io:format("更新后时钟: ~p~n", [Clock3]),

  % 测试安全性
  TestTime1 = [{john, 2}, {paul, 1}],
  TestTime2 = [{john, 4}, {paul, 1}],
  TestTime3 = [{paul, 2}],

  io:format("时间戳 ~p 是否安全: ~w~n", [TestTime1, safe(TestTime1, Clock3)]),
  io:format("时间戳 ~p 是否安全: ~w~n", [TestTime2, safe(TestTime2, Clock3)]),
  io:format("时间戳 ~p 是否安全: ~w~n", [TestTime3, safe(TestTime3, Clock3)]).

%% 比较并发事件的测试
test_concurrent() ->
  io:format("~n=== 测试并发事件 ===~n"),

  % 创建两个并发的向量时间戳
  T1 = [{john, 2}, {paul, 1}],      % john的事件
  T2 = [{paul, 2}, {ringo, 1}],     % paul的事件，与john并发

  io:format("T1: ~p~n", [T1]),
  io:format("T2: ~p~n", [T2]),
  io:format("T1 =< T2: ~w~n", [leq(T1, T2)]),
  io:format("T2 =< T1: ~w~n", [leq(T2, T1)]),

  % 检查是否并发
  case {leq(T1, T2), leq(T2, T1)} of
    {false, false} ->
      io:format("T1 和 T2 是并发的！~n");
    _ ->
      io:format("T1 和 T2 有因果关系~n")
  end.

%% 运行所有测试
test() ->
  test_basic(),
  test_clock(),
  test_concurrent().

%% ============================================================================
%% 辅助函数
%% ============================================================================

%% 格式化向量时钟显示
format_vector(Vector) ->
  lists:foldl(fun({Name, Value}, Acc) ->
    Acc ++ io_lib:format("~w:~w ", [Name, Value])
              end, "", Vector).

%% 检查两个向量时钟是否并发
is_concurrent(Ti, Tj) ->
  case {leq(Ti, Tj), leq(Tj, Ti)} of
    {false, false} -> true;   % 都不小于等于对方，说明并发
    _ -> false                % 其他情况都不是并发
  end.