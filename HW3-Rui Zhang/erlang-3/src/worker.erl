%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 18. 9月 2025 23:02
%%%-------------------------------------------------------------------
-module(worker).
-export([start/5, stop/1, peers/2,test/0,simple_test/0,disorder_test/0]).

%% 启动worker进程
%% Name: worker的唯一名称
%% Logger: logger进程的PID
%% Seed: 随机数种子
%% Sleep: 发送消息间隔的最大值
%% Jitter: 引入随机延迟的最大值
start(Name, Logger, Seed, Sleep, Jitter) ->
  spawn_link(fun() -> init(Name, Logger, Seed, Sleep, Jitter) end).

%% 停止worker进程
stop(Worker) ->
  Worker ! stop.

%% 初始化worker
%% 设置随机种子并等待接收peers信息
init(Name, Log, Seed, Sleep, Jitter) ->
  % 使用rand模块初始化随机数生成器（推荐方式）
  rand:seed(exsss, {Seed, Seed, Seed}),

  receive
    {peers, Peers} ->
      loop(Name, Log, Peers, Sleep, Jitter);
    stop ->
      ok
  end.

%% 便利函数：向worker发送peers列表
peers(Wrk, Peers) ->
  Wrk ! {peers, Peers}.

%% 主循环
%% 等待来自peers的消息，或者在随机等待时间后向peer发送消息
loop(Name, Log, Peers, Sleep, Jitter) ->
  Wait = get_random_uniform(Sleep),
  receive
  %% 接收到来自其他worker的消息
    {msg, Time, Msg} ->
      Log ! {log, Name, Time, {received, Msg}},
      loop(Name, Log, Peers, Sleep, Jitter);

  %% 停止消息
    stop ->
      ok;

  %% 处理未知消息
    Error ->
      Log ! {log, Name, na, {error, Error}},
      loop(Name, Log, Peers, Sleep, Jitter)

  after Wait ->
    %% 超时后，选择一个peer发送消息
    case Peers of
      [] ->
        % 如果没有peers，继续循环
        loop(Name, Log, Peers, Sleep, Jitter);
      _ ->
        Selected = select(Peers),
        Time = na,  % worker不跟踪逻辑时间，使用占位符
        Message = {hello, get_random_uniform(100)},

        % 发送消息给选中的peer
        Selected ! {msg, Time, Message},

        % 引入jitter延迟
        jitter(Jitter),

        % 记录发送事件到logger
        Log ! {log, Name, Time, {sending, Message}},

        loop(Name, Log, Peers, Sleep, Jitter)
    end
  end.

%% 随机选择一个peer
select(Peers) ->
  Index = get_random_uniform(length(Peers)),
  lists:nth(Index, Peers).

%% 引入随机延迟
jitter(0) ->
  ok;
jitter(Jitter) ->
  Delay = get_random_uniform(Jitter),
  timer:sleep(Delay).

%% 生成随机数的现代方式
get_random_uniform(N) ->
  rand:uniform(N).

%% ============================================================================
%% 测试和演示代码
%% ============================================================================

%% 测试函数：启动多个workers并让它们相互通信
test() ->
  % 启动logger
  Logger = dist_logger:start([worker1, worker2, worker3]),

  % 启动3个workers
  Worker1 = start(worker1, Logger, 1, 2000, 100),
  Worker2 = start(worker2, Logger, 2, 2000, 100),
  Worker3 = start(worker3, Logger, 3, 2000, 100),

  % 设置peers关系（每个worker知道其他所有workers）
  peers(Worker1, [Worker2, Worker3]),
  peers(Worker2, [Worker1, Worker3]),
  peers(Worker3, [Worker1, Worker2]),

  % 运行一段时间
  timer:sleep(5000),

  % 停止所有workers
  stop(Worker1),
  stop(Worker2),
  stop(Worker3),

  % 停止logger
  dist_logger:stop(Logger).

%% 简化测试：只启动2个workers
simple_test() ->
  Logger = dist_logger:start([workerA, workerB]),

  WorkerA = start(workerA, Logger, 10, 1000, 50),
  WorkerB = start(workerB, Logger, 20, 1000, 50),

  peers(WorkerA, [WorkerB]),
  peers(WorkerB, [WorkerA]),

  timer:sleep(3000),

  stop(WorkerA),
  stop(WorkerB),
  dist_logger:stop(Logger).

%% 演示消息乱序的测试
%% 使用更大的jitter值来增加消息乱序的可能性
disorder_test() ->
  Logger = dist_logger:start([w1, w2, w3]),

  % 使用较大的jitter值来增加乱序概率
  W1 = start(w1, Logger, 100, 500, 200),
  W2 = start(w2, Logger, 200, 500, 200),
  W3 = start(w3, Logger, 300, 500, 200),

  peers(W1, [W2, W3]),
  peers(W2, [W1, W3]),
  peers(W3, [W1, W2]),

  timer:sleep(2000),

  stop(W1),
  stop(W2),
  stop(W3),
  dist_logger:stop(Logger).