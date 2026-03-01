%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 13. 9月 2025 20:31
%%%-------------------------------------------------------------------
-module(routy_test).
-export([test_network/0, print_status/1, cleanup/0]).

%% 自动化测试：创建5个路由器的网络并演示功能
test_network() ->
  io:format("=== Starting Routy Network Test ===~n"),
  io:format("请确保已编译所有模块: map, intf, hist, dijkstra, routy~n"),

  %% 创建5个路由器：stockholm, goteborg, malmo, lund, uppsala
  io:format("~n1. Creating routers...~n"),
  routy:start(r1, stockholm),
  routy:start(r2, goteborg),
  routy:start(r3, malmo),
  routy:start(r4, lund),
  routy:start(r5, uppsala),

  timer:sleep(100),

  %% 建立网络拓扑
  %% stockholm <-> goteborg <-> malmo <-> lund
  %%     |                        |
  %%   uppsala                 (环形)
  io:format("~n2. Establishing network connections...~n"),

  %% Stockholm connections
  r1 ! {add, goteborg, r2},
  r1 ! {add, uppsala, r5},


  %% Goteborg connections
  r2 ! {add, stockholm, r1},
  r2 ! {add, malmo, r3},

  %% Malmo connections
  r3 ! {add, goteborg, r2},
  r3 ! {add, lund, r4},

  %% Lund connections
  r4 ! {add, malmo, r3},
  r4 ! {add, stockholm, r1},
  r4 ! {add, uppsala, r5},
  % 创建环路

  %% Uppsala connections
  r5 ! {add, stockholm, r1},
  r5 ! {add, lund, r4},

  timer:sleep(100),

  %% 广播链路状态信息
  io:format("~n3. Broadcasting link-state messages...~n"),
  r1 ! broadcast,
  timer:sleep(50),
  r2 ! broadcast,
  timer:sleep(50),
  r3 ! broadcast,
  timer:sleep(50),
  r4 ! broadcast,
  timer:sleep(50),
  r5 ! broadcast,

  timer:sleep(200),

  %% 更新所有路由表
  io:format("~n4. Updating routing tables...~n"),
  r1 ! update,
  r2 ! update,
  r3 ! update,
  r4 ! update,
  r5 ! update,

  timer:sleep(100),

  %% 测试消息路由
  io:format("~n5. Testing message routing...~n"),

  %% 从stockholm发送消息到各个目的地
  r1 ! {send, lund, "Hello from Stockholm to Lund!"},
  timer:sleep(100),

  %%r1 ! {send, uppsala, "Direct message to Uppsala"},
  %%timer:sleep(100),

  %% 从malmo发送到stockholm
  %%r3 ! {send, stockholm, "Reply from Malmo to Stockholm"},
  %%timer:sleep(100),

  %% 从uppsala发送到lund (需要多跳)
  %%r5 ! {send, lund, "Message from Uppsala to Lund via Stockholm"},
  %%timer:sleep(100),

  %% 显示所有路由器状态
  io:format("~n6. Final network status:~n"),
  print_all_status(),

  %% 测试节点故障
  io:format("~n7. Testing node failure (stopping uppsala)...~n"),
  r5 ! stop,
  timer:sleep(200),

  %% 重新广播和更新路由表
  io:format("~n8. Updating network after failure...~n"),
  r1 ! broadcast,
  r3 ! broadcast,
  r4 ! broadcast,
  r2 ! broadcast,
  timer:sleep(200),

  r1 ! update,
  r3 ! update,
  r4 ! update,
  r2 ! update,
  timer:sleep(100),

  %% 测试故障后的路由
  io:format("~n9. Testing routing after failure...~n"),
  r1 ! {send, lund, "Message after uppsala failure"},
  timer:sleep(100),

  io:format("~n=== Test completed ===~n").

%% 打印单个路由器状态
print_status(Router) ->
  case routy:status(Router) of
    {Name, N, _Hist, Intf, Table, _Map} ->
      Interfaces = intf:list(Intf),
      io:format("Router ~w (counter: ~w)~n", [Name, N]),
      io:format("  Interfaces: ~w~n", [Interfaces]),
      io:format("  Routing table: ~w~n", [Table]);
    timeout ->
      io:format("Router ~w: timeout~n", [Router])
  end.

%% 打印所有路由器状态
print_all_status() ->
  Routers = [r1, r2, r3, r4, r5],
  lists:foreach(fun(R) ->
    case whereis(R) of
      undefined ->
        io:format("Router ~w: not running~n", [R]);
      _ ->
        print_status(R)
    end,
    io:format("~n")
                end, Routers).

%% 清理所有路由器进程
cleanup() ->
  Routers = [r1, r2, r3, r4, r5],
  lists:foreach(fun(R) ->
    case whereis(R) of
      undefined -> ok;
      _ -> routy:stop(R)
    end
                end, Routers),
  io:format("All routers stopped.~n").