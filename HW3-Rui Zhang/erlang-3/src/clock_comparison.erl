%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 20. 9月 2025 23:07
%%%-------------------------------------------------------------------
-module(clock_comparison).
-export([run_comparison/2, test_all/0, analyze_differences/0, quick_comparison/0,
  compare_holdback_behavior/2, test_dynamic_overlap/0]).

%% 运行Lamport时钟和向量时钟的并行比较测试
run_comparison(Sleep, Jitter) ->
  io:format("=== 时钟系统并行比较测试 ===~n"),
  io:format("参数: Sleep=~w, Jitter=~w~n~n", [Sleep, Jitter]),

  io:format("1. Lamport时钟系统:~n"),
  io:format("   - 时间戳: 单调递增整数~n"),
  io:format("   - 特点: 维护因果关系，但无法检测并发~n"),
  run_lamport_test(Sleep, Jitter),

  timer:sleep(2000),

  io:format("~n2. 向量时钟系统:~n"),
  io:format("   - 时间戳: 进程名和计数器的向量~n"),
  io:format("   - 特点: 维护因果关系，能检测并发事件~n"),
  run_vector_test(Sleep, Jitter).

%% 比较holdback队列行为
compare_holdback_behavior(Sleep, Jitter) ->
  io:format("=== Holdback队列行为对比 ===~n"),
  io:format("观察每次消息入队和释放的详细信息~n~n"),

  io:format("--- Lamport时钟Holdback行为 ---~n"),
  run_lamport_test(Sleep, Jitter),

  timer:sleep(2000),

  io:format("~n--- 向量时钟Holdback行为 ---~n"),
  io:format("(向量时钟会显示详细的队列操作信息)~n"),
  run_vector_test(Sleep, Jitter),

  io:format("~n=== 对比总结 ===~n"),
  io:format("观察要点:~n"),
  io:format("1. 入队时机: 两个系统每次收到消息都会入队~n"),
  io:format("2. 释放时机: 向量时钟显示详细的释放信息~n"),
  io:format("3. 队列大小: 向量时钟通常能更快释放消息~n"),
  io:format("4. 最终状态: 观察停止时剩余的消息数量差异~n").

%% 测试动态节点和重叠集合（对比版本）
test_dynamic_overlap() ->
  io:format("=== 动态节点和重叠Worker集合对比测试 ===~n~n"),

  io:format("演示1: Lamport时钟处理动态节点~n"),
  test_lamport_dynamic(),

  timer:sleep(2000),

  io:format("~n演示2: 向量时钟处理动态节点~n"),
  vector_logger:test_dynamic_overlap(),

  io:format("~n=== 结论 ===~n"),
  io:format("两个系统都能处理动态添加的节点和重叠的worker集合~n"),
  io:format("关键观察:~n"),
  io:format("- Logger不需要预先知道所有节点~n"),
  io:format("- 新节点可以在运行时动态加入~n"),
  io:format("- 部分重叠的worker集合不影响happen-before顺序~n"),
  io:format("- 向量时钟提供更详细的因果关系追踪~n").

%% Lamport时钟的动态节点测试
test_lamport_dynamic() ->
  Logger = hw_logger:start([]),

  io:format("阶段1: 启动第一组workers (alice, bob)~n"),
  W1 = logical_worker:start(alice, Logger, 1, 800, 100),
  W2 = logical_worker:start(bob, Logger, 2, 800, 100),

  logical_worker:peers(W1, [W2]),
  logical_worker:peers(W2, [W1]),

  timer:sleep(1500),

  io:format("~n阶段2: 动态添加节点 charlie (与bob重叠)~n"),
  W3 = logical_worker:start(charlie, Logger, 3, 800, 100),

  logical_worker:peers(W2, [W1, W3]),
  logical_worker:peers(W3, [W2]),

  timer:sleep(1500),

  lists:foreach(fun logical_worker:stop/1, [W1, W2, W3]),
  hw_logger:stop(Logger).

%% 运行Lamport时钟测试
run_lamport_test(Sleep, Jitter) ->
  Log = hw_logger:start([john, paul, ringo]),

  A = logical_worker:start(john, Log, 13, Sleep, Jitter),
  B = logical_worker:start(paul, Log, 23, Sleep, Jitter),
  C = logical_worker:start(ringo, Log, 36, Sleep, Jitter),

  logical_worker:peers(A, [B, C]),
  logical_worker:peers(B, [A, C]),
  logical_worker:peers(C, [A, B]),

  timer:sleep(3000),

  hw_logger:stop(Log),
  logical_worker:stop(A),
  logical_worker:stop(B),
  logical_worker:stop(C).

%% 运行向量时钟测试
run_vector_test(Sleep, Jitter) ->
  Log = vector_logger:start([john, paul, ringo]),

  A = vector_worker:start(john, Log, 13, Sleep, Jitter),
  B = vector_worker:start(paul, Log, 23, Sleep, Jitter),
  C = vector_worker:start(ringo, Log, 36, Sleep, Jitter),

  vector_worker:peers(A, [B, C]),
  vector_worker:peers(B, [A, C]),
  vector_worker:peers(C, [A, B]),

  timer:sleep(3000),

  vector_logger:stop(Log),
  vector_worker:stop(A),
  vector_worker:stop(B),
  vector_worker:stop(C).

%% 分析两种时钟系统的差异
analyze_differences() ->
  io:format("=== 两种时钟系统的详细分析 ===~n~n"),

  io:format("📊 时间戳表示:~n"),
  io:format("• Lamport时钟: 单个整数 (1, 2, 3, 4, ...)~n"),
  io:format("• 向量时钟: 进程-计数器对列表 ([{john,2}, {paul,1}])~n~n"),

  io:format("🔍 因果关系检测:~n"),
  io:format("• Lamport时钟: 能检测因果关系 (如果A->B, 则T(A) < T(B))~n"),
  io:format("• 向量时钟: 也能检测因果关系 (如果A->B, 则V(A) < V(B))~n~n"),

  io:format("⚡ 并发检测能力:~n"),
  io:format("• Lamport时钟: 无法检测并发 (T1 < T2不意味着有因果关系)~n"),
  io:format("• 向量时钟: 能检测并发 (V1 || V2 当且仅当 !(V1≤V2) && !(V2≤V1))~n~n"),

  io:format("💾 存储开销:~n"),
  io:format("• Lamport时钟: O(1) - 只需一个整数~n"),
  io:format("• 向量时钟: O(n) - 需要存储n个进程的计数器~n~n"),

  io:format("🚀 性能影响:~n"),
  io:format("• Lamport时钟: 更新快，比较快~n"),
  io:format("• 向量时钟: 更新较慢，比较较慢，但信息更丰富~n~n"),

  io:format("🔒 Holdback队列效果:~n"),
  io:format("• Lamport时钟: 可能过度保守 (串行化一些并发事件)~n"),
  io:format("• 向量时钟: 更精确 (只阻塞真正有因果依赖的事件)~n~n").

%% 完整的比较测试套件
test_all() ->
  io:format("=== 完整的时钟系统比较测试 ===~n~n"),

  io:format("1. 基础功能比较~n"),
  run_comparison(1000, 150),

  timer:sleep(2000),

  io:format("~n2. Holdback队列详细对比~n"),
  compare_holdback_behavior(800, 100),

  timer:sleep(2000),

  io:format("~n3. 动态节点和重叠集合测试~n"),
  test_dynamic_overlap(),

  timer:sleep(1000),

  io:format("~n4. 理论差异分析~n"),
  analyze_differences(),

  io:format("~n=== 比较测试完成 ===~n").

%% 快速比较测试
quick_comparison() ->
  run_comparison(800, 100).