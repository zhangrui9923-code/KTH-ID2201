%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 18. 9月 2025 22:48
%%%-------------------------------------------------------------------
-module(dist_logger).
-export([start/1, stop/1,test/0,concurrent_test/0]).

%% 启动logger进程
%% Nodes: 将发送消息给logger的节点列表
start(Nodes) ->
  spawn_link(fun() -> init(Nodes) end).

%% 停止logger进程
stop(Logger) ->
  Logger ! stop.

%% 初始化函数
%% 目前忽略Nodes参数，但保留以备后续扩展使用
init(_Nodes) ->
  io:format("Logger started~n"),
  loop().

%% 主循环，处理接收到的消息
loop() ->
  receive
  %% 接收日志消息：{log, 发送者, 时间戳, 消息内容}
    {log, From, Time, Msg} ->
      log(From, Time, Msg),
      loop();
  %% 停止消息
    stop ->
      io:format("Logger stopping~n"),
      ok;
  %% 处理未知消息
    Unknown ->
      io:format("Logger received unknown message: ~p~n", [Unknown]),
      loop()
  end.

%% 打印日志信息
%% From: 消息发送者
%% Time: 时间戳
%% Msg: 消息内容
log(From, Time, Msg) ->
  io:format("log: ~w ~w ~p~n", [Time, From, Msg]).

%% ============================================================================
%% 辅助函数和测试代码
%% ============================================================================

%% 测试用的发送消息函数
send_log(Logger, From, Msg) ->
  Logger ! {log, From, erlang:timestamp(), Msg}.

%% 简单的测试函数
test() ->
  % 启动logger
  Logger = start([node1, node2, node3]),

  % 发送一些测试消息
  send_log(Logger, node1, "First message"),
  send_log(Logger, node2, "Second message"),
  send_log(Logger, node1, "Third message"),

  % 等待一下让消息处理完
  timer:sleep(100),

  % 停止logger
  stop(Logger).

%% 模拟并发情况的测试
%% 这个函数演示了消息顺序可能出现的问题
concurrent_test() ->
  Logger = start([nodeA, nodeB]),

  % 进程A发送消息给logger，然后发送消息给进程B
  % 进程B收到消息后也发送消息给logger
  % 这种情况下，A的日志消息可能不会在B的消息之前被打印

  % 先创建ProcessB并注册
  ProcessB = spawn(fun() ->
    receive
      {from_a, _} ->
        % B收到A的消息后，立即发送日志
        Logger ! {log, processB, erlang:timestamp(), "Message from B after receiving from A"}
    end
                   end),

  % 注册ProcessB，这样ProcessA可以找到它
  register(test_processB, ProcessB),

  % 创建ProcessA
  _ProcessA = spawn(fun() ->
    Logger ! {log, processA, erlang:timestamp(), "Message from A"},
    % 模拟A向B发送消息
    test_processB ! {from_a, "trigger message"}
                    end),

  % 等待处理完成
  timer:sleep(200),

  % 清理
  case whereis(test_processB) of
    undefined -> ok;  % 进程可能已经结束
    _ -> unregister(test_processB)
  end,
  stop(Logger).