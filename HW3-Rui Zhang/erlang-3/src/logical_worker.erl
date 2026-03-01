%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 20. 9月 2025 22:41
%%%-------------------------------------------------------------------
-module(logical_worker).
-export([start/5, stop/1, peers/2]).

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

%% 初始化worker，设置随机种子和初始Lamport时钟
init(Name, Logger, Seed, Sleep, Jitter) ->
  rand:seed(exsss, {Seed, Seed, Seed}),
  Clock = time:zero(),
  receive
    {peers, Peers} ->
      loop(Name, Logger, Peers, Sleep, Jitter, Clock);
    stop ->
      ok
  end.

%% 便利函数：向worker发送peers列表
peers(Worker, Peers) ->
  Worker ! {peers, Peers}.

%% 主循环 - 处理消息接收和发送，维护Lamport时钟
loop(Name, Logger, Peers, Sleep, Jitter, Clock) ->
  Wait = rand:uniform(Sleep),
  receive
  %% 接收来自其他worker的消息
    {msg, MsgTime, Msg} ->
      % 1. 合并本地时钟和消息时间戳
      MergedTime = time:merge(Clock, MsgTime),
      % 2. 递增时钟
      NewClock = time:inc(Name, MergedTime),
      % 3. 记录接收事件
      Logger ! {log, Name, NewClock, {received, Msg}},
      loop(Name, Logger, Peers, Sleep, Jitter, NewClock);

  %% 停止消息
    stop ->
      ok;

  %% 处理未知消息
    Error ->
      NewClock = time:inc(Name, Clock),
      Logger ! {log, Name, NewClock, {error, Error}},
      loop(Name, Logger, Peers, Sleep, Jitter, NewClock)

  after Wait ->
    %% 超时后向random peer发送消息
    case Peers of
      [] ->
        loop(Name, Logger, Peers, Sleep, Jitter, Clock);
      _ ->
        % 1. 递增时钟（发送事件）
        SendClock = time:inc(Name, Clock),

        % 2. 选择目标并创建消息
        Selected = select(Peers),
        Message = {hello, rand:uniform(100)},

        % 3. 发送消息到peer（包含时间戳）
        Selected ! {msg, SendClock, Message},

        % 4. 引入jitter延迟
        jitter(Jitter),

        % 5. 记录发送事件到logger
        Logger ! {log, Name, SendClock, {sending, Message}},

        loop(Name, Logger, Peers, Sleep, Jitter, SendClock)
    end
  end.

%% 随机选择一个peer
select(Peers) ->
  Index = rand:uniform(length(Peers)),
  lists:nth(Index, Peers).

%% 引入随机延迟（模拟网络延迟）
jitter(0) ->
  ok;
jitter(Jitter) ->
  timer:sleep(rand:uniform(Jitter)).