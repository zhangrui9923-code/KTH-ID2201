%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 18. 9月 2025 23:10
%%%-------------------------------------------------------------------
-module(test).
-export([run/2,full_experiment_suite/0,medium_jitter_test/0,no_jitter_test/0]).

%% 运行测试，创建4个workers模拟Beatles成员
%% Sleep: worker发送消息的间隔时间
%% Jitter: 发送消息和记录日志间的随机延迟
run(Sleep, Jitter) ->
  % 启动logger，监控4个workers
  Log = dist_logger:start([john, paul, ringo, george]),

  % 创建4个workers，每个都有不同的随机种子
  A = worker:start(john, Log, 13, Sleep, Jitter),
  B = worker:start(paul, Log, 23, Sleep, Jitter),
  C = worker:start(ringo, Log, 36, Sleep, Jitter),
  D = worker:start(george, Log, 49, Sleep, Jitter),

  % 设置peers关系 - 每个worker都知道其他所有workers
  worker:peers(A, [B, C, D]),
  worker:peers(B, [A, C, D]),
  worker:peers(C, [A, B, D]),
  worker:peers(D, [A, B, C]),

  % 让系统运行5秒
  timer:sleep(5000),

  % 停止所有进程
  dist_logger:stop(Log),
  worker:stop(A),
  worker:stop(B),
  worker:stop(C),
  worker:stop(D).

%% ============================================================================
%% 实验和分析函数
%% ============================================================================

%% 实验1: 无jitter - 应该很少或没有乱序
no_jitter_test() ->
  io:format("=== 测试: 无Jitter (Jitter=0) ===~n"),
  run(1000, 0).

%% 实验2: 小jitter - 可能有少量乱序
small_jitter_test() ->
  io:format("=== 测试: 小Jitter (Jitter=50) ===~n"),
  run(1000, 50).

%% 实验3: 中等jitter - 应该有明显乱序
medium_jitter_test() ->
  io:format("=== 测试: 中等Jitter (Jitter=200) ===~n"),
  run(1000, 200).

%% 实验4: 大jitter - 应该有很多乱序
large_jitter_test() ->
  io:format("=== 测试: 大Jitter (Jitter=500) ===~n"),
  run(1000, 500).

%% 实验5: 快速发送 + 大jitter - 最容易观察到乱序
chaos_test() ->
  io:format("=== 测试: 混乱模式 (Sleep=200, Jitter=300) ===~n"),
  run(200, 300).

%% 连续实验：观察jitter对消息顺序的影响
jitter_experiment() ->
  io:format("=== Jitter影响实验 ===~n"),

  JitterValues = [0, 25, 50, 100, 200, 400],
  lists:foreach(fun(Jitter) ->
    io:format("~n--- Jitter = ~w ms ---~n", [Jitter]),
    run(800, Jitter),
    timer:sleep(1000)  % 实验间隔
                end, JitterValues).

%% 速度实验：观察发送速度对消息顺序的影响
speed_experiment() ->
  io:format("=== 发送速度影响实验 ===~n"),

  SleepValues = [2000, 1000, 500, 200, 100],
  lists:foreach(fun(Sleep) ->
    io:format("~n--- Sleep = ~w ms, Jitter = 150 ms ---~n", [Sleep]),
    run(Sleep, 150),
    timer:sleep(1000)  % 实验间隔
                end, SleepValues).

%% 短时间高强度测试
stress_test() ->
  io:format("=== 压力测试 (10秒) ===~n"),
  run(100, 200).

%% ============================================================================
%% 分析指导
%% ============================================================================

%% 如何识别消息乱序？
%%
%% 正常顺序应该是：
%% 1. Worker A: log: na john {sending, {hello, 42}}
%% 2. Worker B: log: na paul {received, {hello, 42}}
%%
%% 乱序情况会是：
%% 1. Worker B: log: na paul {received, {hello, 42}}  <- 先出现received
%% 2. Worker A: log: na john {sending, {hello, 42}}   <- 后出现sending
%%
%% 这违反了因果关系：消息必须先被发送，然后才能被接收！

analysis_guide() ->
  io:format("=== 消息乱序分析指南 ===~n"),
  io:format("1. 寻找相同消息内容的sending和received事件~n"),
  io:format("2. 检查时间戳：received出现在sending之前就是乱序~n"),
  io:format("3. 乱序示例:~n"),
  io:format("   WRONG: received {hello,42} 然后 sending {hello,42}~n"),
  io:format("   RIGHT: sending {hello,42} 然后 received {hello,42}~n"),
  io:format("4. Jitter越大，乱序越多~n"),
  io:format("5. Sleep越小(发送越频繁)，乱序机会越多~n~n").

%% 完整的实验套件
full_experiment_suite() ->
  analysis_guide(),

  io:format("开始完整实验套件...~n~n"),

  no_jitter_test(),
  timer:sleep(2000),

  small_jitter_test(),
  timer:sleep(2000),

  medium_jitter_test(),
  timer:sleep(2000),

  large_jitter_test(),
  timer:sleep(2000),

  chaos_test(),

  io:format("~n=== 实验完成 ===~n").

%% ============================================================================
%% 便捷的测试启动函数
%% ============================================================================

%% 快速测试
quick() -> run(1000, 100).

%% 观察乱序的最佳设置
best_disorder() -> run(500, 250).