%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 20. 9月 2025 22:42
%%%-------------------------------------------------------------------
-module(hw_logger).
-export([start/1, stop/1]).

%% 启动logger进程
start(Nodes) ->
  spawn_link(fun() -> init(Nodes) end).

%% 停止logger进程
stop(Logger) ->
  Logger ! stop.

%% 初始化logger，设置时钟和holdback队列
init(Nodes) ->
  io:format("Logger started with holdback queue~n"),
  Clock = time:clock(Nodes),
  HoldbackQueue = [],
  loop(Clock, HoldbackQueue).

%% 主循环 - 处理日志消息并管理holdback队列
loop(Clock, HoldbackQueue) ->
  receive
  %% 接收日志消息：{log, 发送者, 时间戳, 消息内容}
    {log, From, Time, Msg} ->
      % 1. 更新时钟
      NewClock = time:update(From, Time, Clock),

      % 2. 创建日志条目
      LogEntry = {From, Time, Msg},

      % 3. 将消息添加到holdback队列
      NewQueue = [LogEntry | HoldbackQueue],

      % 4. 显示holdback队列数量
      display_queue_size(NewQueue),

      % 5. 提取可以安全打印的消息
      {SafeMessages, RemainingQueue} = extract_safe_messages(NewQueue, NewClock),

      % 6. 按时间顺序打印安全消息
      print_messages(SafeMessages),

      loop(NewClock, RemainingQueue);

  %% 停止消息
    stop ->
      io:format("~nFlushing remaining messages in holdback queue:~n"),
      % 打印剩余的所有消息
      SortedRemaining = lists:sort(fun({_, T1, _}, {_, T2, _}) ->
        time:leq(T1, T2)
                                   end, HoldbackQueue),
      print_messages(SortedRemaining),
      io:format("Logger stopping~n"),
      ok;

  %% 处理未知消息
    Unknown ->
      io:format("Logger received unknown message: ~p~n", [Unknown]),
      loop(Clock, HoldbackQueue)
  end.

%% 从holdback队列中提取可以安全打印的消息
extract_safe_messages(Queue, Clock) ->
  extract_safe_messages(Queue, Clock, [], []).

extract_safe_messages([], _Clock, Safe, Remaining) ->
  % 按时间戳排序安全消息
  SortedSafe = lists:sort(fun({_, T1, _}, {_, T2, _}) ->
    time:leq(T1, T2)
                          end, Safe),
  {SortedSafe, Remaining};

extract_safe_messages([{From, Time, Msg} = Entry | Rest], Clock, Safe, Remaining) ->
  case time:safe(Time, Clock) of
    true ->
      % 这条消息可以安全打印
      extract_safe_messages(Rest, Clock, [Entry | Safe], Remaining);
    false ->
      % 这条消息还不能打印，保留在队列中
      extract_safe_messages(Rest, Clock, Safe, [Entry | Remaining])
  end.

%% 打印日志消息
print_messages([]) ->
  ok;
print_messages([{From, Time, Msg} | Rest]) ->
  io:format("log: ~w ~w ~p~n", [Time, From, Msg]),
  print_messages(Rest).

%% 显示holdback队列数量
display_queue_size([]) ->
  io:format("Holdback Queue: 0~n");
display_queue_size(Queue) ->
  QueueSize = length(Queue),
  io:format("Holdback Queue: ~w~n", [QueueSize]).