%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 20. 9月 2025 22:43
%%%-------------------------------------------------------------------
-module(lamport_test).
-export([run/2, compare/2]).

%% 运行测试，创建4个workers模拟Beatles成员
%% Sleep: worker发送消息的间隔时间
%% Jitter: 发送消息和记录日志间的随机延迟
run(Sleep, Jitter) ->
  % 启动logger，监控4个workers
  Log = hw_logger:start([john, paul, ringo, george]),

  % 创建4个workers，每个都有不同的随机种子
  A = logical_worker:start(john, Log, 13, Sleep, Jitter),
  B = logical_worker:start(paul, Log, 23, Sleep, Jitter),
  C = logical_worker:start(ringo, Log, 36, Sleep, Jitter),
  D = logical_worker:start(george, Log, 49, Sleep, Jitter),

  % 设置peers关系 - 每个worker都知道其他所有workers
  logical_worker:peers(A, [B, C, D]),
  logical_worker:peers(B, [A, C, D]),
  logical_worker:peers(C, [A, B, D]),
  logical_worker:peers(D, [A, B, C]),

  % 让系统运行5秒
  timer:sleep(5000),

  % 停止所有进程
  hw_logger:stop(Log),
  logical_worker:stop(A),
  logical_worker:stop(B),
  logical_worker:stop(C),
  logical_worker:stop(D).

%% 比较有无Lamport时钟的系统
%% Sleep: worker发送消息的间隔时间
%% Jitter: 发送消息和记录日志间的随机延迟
compare(Sleep, Jitter) ->
  io:format("=== Lamport时钟系统 vs 原始系统比较 ===~n~n"),

  io:format("1. 原始系统（使用time模块但无Lamport逻辑）：~n"),
  io:format("   - 使用time:inc()递增时间戳~n"),
  io:format("   - 不使用time:merge()，不同步时钟~n"),
  io:format("   - 没有holdback队列，消息立即打印~n"),
  io:format("   - 可能出现因果关系乱序~n~n"),

  run_original_system(Sleep, Jitter),

  timer:sleep(2000),

  io:format("~n2. Lamport时钟系统（逻辑时间戳）：~n"),
  io:format("   - 使用递增的逻辑时间戳~n"),
  io:format("   - 使用holdback队列确保顺序~n"),
  io:format("   - 维护因果关系~n"),
  io:format("   - 显示holdback队列状态~n~n"),

  run(Sleep, Jitter).



%% 运行原始系统（使用物理时间戳但无逻辑时钟）
run_original_system(Sleep, Jitter) ->
  % 启动简单logger（无holdback队列）
  Log = spawn_link(fun() -> simple_logger_loop() end),

  % 创建4个原始workers（使用物理时间戳）
  A = spawn_link(fun() -> original_worker_init(john, Log, 13, Sleep, Jitter) end),
  B = spawn_link(fun() -> original_worker_init(paul, Log, 23, Sleep, Jitter) end),
  C = spawn_link(fun() -> original_worker_init(ringo, Log, 36, Sleep, Jitter) end),
  D = spawn_link(fun() -> original_worker_init(george, Log, 49, Sleep, Jitter) end),

  timer:sleep(100), % 确保workers启动

  % 设置peers关系
  A ! {peers, [B, C, D]},
  B ! {peers, [A, C, D]},
  C ! {peers, [A, B, D]},
  D ! {peers, [A, B, C]},

  % 让系统运行5秒
  timer:sleep(5000),

  % 停止所有进程
  Log ! stop,
  A ! stop,
  B ! stop,
  C ! stop,
  D ! stop.

%% 简单的logger（无holdback队列，立即打印）
simple_logger_loop() ->
  receive
    {log, From, Time, Msg} ->
      io:format("log: ~w ~w ~p~n", [Time, From, Msg]),
      simple_logger_loop();
    stop ->
      io:format("Original logger stopping~n"),
      ok
  end.

%% 原始worker初始化（使用time模块但无Lamport逻辑）
original_worker_init(Name, Logger, Seed, Sleep, Jitter) ->
  rand:seed(exsss, {Seed, Seed, Seed}),
  Clock = time:zero(),  % 使用time模块初始化时钟
  receive
    {peers, Peers} ->
      original_worker_loop(Name, Logger, Peers, Sleep, Jitter, Clock);
    stop ->
      ok
  end.

%% 原始worker主循环（使用time模块但无Lamport逻辑）
original_worker_loop(Name, Logger, Peers, Sleep, Jitter, Clock) ->
  Wait = rand:uniform(Sleep),
  receive
  %% 接收消息 - 只递增自己的时钟，不合并
    {msg, _SenderTime, Msg} ->
      % 不执行merge，只递增自己的时钟
      NewClock = time:inc(Name, Clock),
      Logger ! {log, Name, NewClock, {received, Msg}},
      original_worker_loop(Name, Logger, Peers, Sleep, Jitter, NewClock);

    stop ->
      ok;

    Error ->
      NewClock = time:inc(Name, Clock),
      Logger ! {log, Name, NewClock, {error, Error}},
      original_worker_loop(Name, Logger, Peers, Sleep, Jitter, NewClock)

  after Wait ->
    case Peers of
      [] ->
        original_worker_loop(Name, Logger, Peers, Sleep, Jitter, Clock);
      _ ->
        Selected = select_random(Peers),
        Message = {hello, rand:uniform(100)},

        % 递增时钟（发送事件）
        SendClock = time:inc(Name, Clock),

        % 发送消息
        Selected ! {msg, SendClock, Message},

        % 引入jitter延迟（可能导致乱序）
        timer:sleep(rand:uniform(Jitter + 1) - 1),

        % 记录发送事件（可能因jitter延迟而乱序）
        Logger ! {log, Name, SendClock, {sending, Message}},

        original_worker_loop(Name, Logger, Peers, Sleep, Jitter, SendClock)
    end
  end.

%% 随机选择helper函数
select_random(List) ->
  Index = rand:uniform(length(List)),
  lists:nth(Index, List).