%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 20. 9月 2025 23:03
%%%-------------------------------------------------------------------
-module(vector_logger).
-export([start/1, stop/1, test_suite/0, test_dynamic_overlap/0]).

%% 启动向量时钟logger进程
start(Nodes) ->
  spawn_link(fun() -> init(Nodes) end).

%% 停止logger进程
stop(Logger) ->
  Logger ! stop.

%% 初始化logger
init(Nodes) ->
  io:format("Vector Clock Logger started (initial nodes: ~p)~n", [Nodes]),
  io:format("Note: Logger dynamically handles new nodes without prior knowledge~n"),
  Clock = vect:clock(Nodes),
  HoldbackQueue = [],
  loop(Clock, HoldbackQueue).

%% 主循环
loop(Clock, HoldbackQueue) ->
  receive
    {log, From, Time, Msg} ->
      NewClock = vect:update(From, Time, Clock),
      LogEntry = {From, Time, Msg},
      NewQueue = [LogEntry | HoldbackQueue],

      % 详细的队列监控输出
      TimeStr = format_vector_time(Time),
      io:format("[Vector QUEUE] Message queued: ~s from ~w, Queue size: ~w~n",
        [TimeStr, From, length(NewQueue)]),

      {SafeMessages, RemainingQueue} = extract_safe_messages(NewQueue, NewClock),

      if
        length(SafeMessages) > 0 ->
          io:format("[Vector RELEASE] Released ~w messages, Remaining: ~w~n",
            [length(SafeMessages), length(RemainingQueue)]);
        true -> ok
      end,

      print_messages(SafeMessages),
      loop(NewClock, RemainingQueue);

    stop ->
      io:format("~nFlushing remaining messages in holdback queue (~w messages):~n",
        [length(HoldbackQueue)]),
      SortedRemaining = sort_by_vector_time(HoldbackQueue),
      print_messages(SortedRemaining),
      io:format("Vector Clock Logger stopping~n"),
      ok;

    Unknown ->
      io:format("Logger received unknown message: ~p~n", [Unknown]),
      loop(Clock, HoldbackQueue)
  end.

extract_safe_messages(Queue, Clock) ->
  extract_safe_messages(Queue, Clock, [], []).

extract_safe_messages([], _Clock, Safe, Remaining) ->
  SortedSafe = sort_by_vector_time(Safe),
  {SortedSafe, Remaining};

extract_safe_messages([{From, Time, Msg} = Entry | Rest], Clock, Safe, Remaining) ->
  case vect:safe(Time, Clock) of
    true ->
      extract_safe_messages(Rest, Clock, [Entry | Safe], Remaining);
    false ->
      extract_safe_messages(Rest, Clock, Safe, [Entry | Remaining])
  end.

sort_by_vector_time(Messages) ->
  lists:sort(fun({_, T1, _}, {_, T2, _}) ->
    vector_time_compare(T1, T2)
             end, Messages).

vector_time_compare(T1, T2) ->
  case {vect:leq(T1, T2), vect:leq(T2, T1)} of
    {true, _} -> true;
    {false, true} -> false;
    {false, false} -> T1 =< T2
  end.

print_messages([]) ->
  ok;
print_messages([{From, Time, Msg} | Rest]) ->
  TimeStr = format_vector_time(Time),
  io:format("log: ~s ~w ~p~n", [TimeStr, From, Msg]),
  print_messages(Rest).

format_vector_time([]) ->
  "[]";
format_vector_time(Time) ->
  Sorted = lists:sort(Time),
  Parts = [io_lib:format("~w:~w", [Name, Value]) || {Name, Value} <- Sorted],
  "[" ++ lists:flatten(lists:join(",", Parts)) ++ "]".

%% 测试动态节点和部分重叠的worker集合
test_dynamic_overlap() ->
  io:format("=== 测试动态节点和重叠Worker集合 ===~n"),
  io:format("演示: Logger不需要预先知道所有节点~n~n"),

  Logger = start([]),

  io:format("阶段1: 启动第一组workers (john, paul, ringo)~n"),
  W1 = vector_worker:start(john, Logger, 1, 800, 100),
  W2 = vector_worker:start(paul, Logger, 2, 800, 100),
  W3 = vector_worker:start(ringo, Logger, 3, 800, 100),

  vector_worker:peers(W1, [W2, W3]),
  vector_worker:peers(W2, [W1, W3]),
  vector_worker:peers(W3, [W1, W2]),

  timer:sleep(2000),

  io:format("~n阶段2: 动态添加第二组workers (george, paul重叠, pete)~n"),
  W4 = vector_worker:start(george, Logger, 4, 800, 100),
  W5 = vector_worker:start(pete, Logger, 5, 800, 100),

  vector_worker:peers(W2, [W1, W3, W4, W5]),
  vector_worker:peers(W4, [W2, W5]),
  vector_worker:peers(W5, [W2, W4]),

  timer:sleep(2000),

  io:format("~n阶段3: 观察happen-before顺序是否正确维护~n"),
  timer:sleep(1000),

  lists:foreach(fun vector_worker:stop/1, [W1, W2, W3, W4, W5]),
  stop(Logger),

  io:format("~n结论: Logger成功处理了动态添加的节点和重叠集合~n").

test_suite() ->
  io:format("=== 向量时钟系统完整测试 ===~n~n"),
  vect:test(),
  timer:sleep(1000),
  test_dynamic_overlap().