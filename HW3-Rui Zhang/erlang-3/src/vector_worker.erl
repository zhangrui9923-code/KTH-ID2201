%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 20. 9月 2025 23:02
%%%-------------------------------------------------------------------
-module(vector_worker).
-export([start/5, stop/1, peers/2,test_vector/0,quick/0]).

%% 启动支持向量时钟的worker进程
start(Name, Logger, Seed, Sleep, Jitter) ->
  spawn_link(fun() -> init(Name, Logger, Seed, Sleep, Jitter) end).

%% 停止worker进程
stop(Worker) ->
  Worker ! stop.

%% 初始化worker，使用向量时钟
init(Name, Log, Seed, Sleep, Jitter) ->
  % 初始化随机数生成器
  rand:seed(exsss, {Seed, Seed, Seed}),

  % 初始化向量时钟
  Clock = vect:zero(),

  receive
    {peers, Peers} ->
      loop(Name, Log, Peers, Sleep, Jitter, Clock);
    stop ->
      ok
  end.

%% 便利函数：向worker发送peers列表
peers(Wrk, Peers) ->
  Wrk ! {peers, Peers}.

%% 主循环 - 使用向量时钟管理
loop(Name, Log, Peers, Sleep, Jitter, Clock) ->
  Wait = rand:uniform(Sleep),
  receive
  %% 接收到来自其他worker的消息（包含向量时间戳）
    {msg, Time, Msg} ->
      % 1. 合并接收到的向量时钟与本地时钟
      MergedClock = vect:merge(Clock, Time),
      % 2. 为当前进程增加时钟
      NewClock = vect:inc(Name, MergedClock),
      % 3. 记录接收事件
      Log ! {log, Name, NewClock, {received, Msg}},
      loop(Name, Log, Peers, Sleep, Jitter, NewClock);

  %% 停止消息
    stop ->
      ok;

  %% 处理未知消息
    Error ->
      NewClock = vect:inc(Name, Clock),
      Log ! {log, Name, NewClock, {error, Error}},
      loop(Name, Log, Peers, Sleep, Jitter, NewClock)

  after Wait ->
    %% 超时后，选择一个peer发送消息
    case Peers of
      [] ->
        % 如果没有peers，继续循环
        loop(Name, Log, Peers, Sleep, Jitter, Clock);
      _ ->
        % 1. 为发送事件增加时钟
        SendClock = vect:inc(Name, Clock),

        % 2. 选择目标并创建消息
        Selected = select(Peers),
        Message = {hello, rand:uniform(100)},

        % 3. 发送消息（包含向量时间戳）
        Selected ! {msg, SendClock, Message},

        % 4. 引入jitter延迟
        jitter(Jitter),

        % 5. 记录发送事件到logger
        Log ! {log, Name, SendClock, {sending, Message}},

        loop(Name, Log, Peers, Sleep, Jitter, SendClock)
    end
  end.

%% 随机选择一个peer
select(Peers) ->
  Index = rand:uniform(length(Peers)),
  lists:nth(Index, Peers).

%% 引入随机延迟
jitter(0) ->
  ok;
jitter(Jitter) ->
  Delay = rand:uniform(Jitter),
  timer:sleep(Delay).

%% ============================================================================
%% 测试函数
%% ============================================================================

%% 测试向量时钟worker系统
test_vector() ->
  % 启动支持向量时钟的logger
  Logger = vector_logger:start([workerA, workerB, workerC]),

  % 启动3个workers
  WorkerA = start(workerA, Logger, 1, 1000, 100),
  WorkerB = start(workerB, Logger, 2, 1000, 100),
  WorkerC = start(workerC, Logger, 3, 1000, 100),

  % 设置peers关系
  peers(WorkerA, [WorkerB, WorkerC]),
  peers(WorkerB, [WorkerA, WorkerC]),
  peers(WorkerC, [WorkerA, WorkerB]),

  % 运行一段时间
  timer:sleep(5000),

  % 停止所有workers
  stop(WorkerA),
  stop(WorkerB),
  stop(WorkerC),

  % 停止logger
  vector_logger:stop(Logger).

%% 快速测试
quick() ->
  test_vector().
