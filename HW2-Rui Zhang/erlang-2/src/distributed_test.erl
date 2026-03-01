%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 16. 9月 2025 17:01
%%%-------------------------------------------------------------------
-module(distributed_test).
-export([
  setup_region/1,
  broadcast_region/1,
  update_region/1,
  send_message/3,
  show_status/0,
  cleanup/0,
  force_network_sync/0,
  test_connection/2
]).

%% 区域城市定义
-define(CITIES, #{
  europe => [stockholm, oslo, berlin, paris, london],
  asia => [tokyo, beijing, mumbai, bangkok, seoul],
  africa => [cairo, lagos, johannesburg, nairobi, casablanca],
  america => [newyork, toronto, mexico_city, sao_paulo, santiago],
  oceania => [sydney, melbourne, wellington, suva, port_moresby]
}).

%% 设置指定区域的路由器
setup_region(Region) ->
  io:format("=== Setting up ~w region on node ~w ===~n", [Region, node()]),

  case maps:get(Region, ?CITIES, undefined) of
    undefined ->
      io:format("Unknown region: ~w~n", [Region]),
      io:format("Available regions: ~w~n", [maps:keys(?CITIES)]),
      error;
    Cities ->
      io:format("Creating routers for ~w: ~w~n", [Region, Cities]),

      %% 启动所有路由器
      lists:foreach(fun(City) ->
        routy:start(City, City),
        timer:sleep(100),
        io:format("Started router: ~w~n", [City])
                    end, Cities),

      %% 建立区域内连接（星形拓扑，第一个城市为中心）
      [Hub|Others] = Cities,
      connect_star(Hub, Others),

      io:format("Region ~w setup complete with ~w routers~n", [Region, length(Cities)]),
      Cities
  end.

%% 建立星形连接（中心辐射型）
connect_star(_Hub, []) -> ok;
connect_star(Hub, Others) ->
  lists:foreach(fun(City) ->
    Hub ! {add, City, City},
    City ! {add, Hub, Hub},
    io:format("Connected ~w <-> ~w~n", [Hub, City]),
    timer:sleep(50)
                end, Others).

%% 区域广播链路状态
broadcast_region(Region) ->
  case maps:get(Region, ?CITIES, undefined) of
    undefined ->
      io:format("Unknown region: ~w~n", [Region]);
    Cities ->
      io:format("=== Broadcasting in ~w region ===~n", [Region]),
      lists:foreach(fun(City) ->
        case whereis(City) of
          undefined ->
            io:format("Router ~w not running~n", [City]);
          _ ->
            io:format("Broadcasting from ~w~n", [City]),
            City ! broadcast,
            timer:sleep(100)
        end
                    end, Cities),
      io:format("Broadcast complete for ~w region~n", [Region])
  end.

%% 区域更新路由表
update_region(Region) ->
  case maps:get(Region, ?CITIES, undefined) of
    undefined ->
      io:format("Unknown region: ~w~n", [Region]);
    Cities ->
      io:format("=== Updating routing tables in ~w region ===~n", [Region]),
      lists:foreach(fun(City) ->
        case whereis(City) of
          undefined ->
            io:format("Router ~w not running~n", [City]);
          _ ->
            io:format("Updating ~w~n", [City]),
            City ! update,
            timer:sleep(100)
        end
                    end, Cities),
      io:format("Update complete for ~w region~n", [Region])
  end.

%% 发送消息
send_message(From, To, Message) ->
  case whereis(From) of
    undefined ->
      io:format("Router ~w not found~n", [From]),
      error;
    _ ->
      io:format("=== Sending message ===~n"),
      io:format("From: ~w~n", [From]),
      io:format("To: ~w~n", [To]),
      io:format("Message: ~s~n", [Message]),
      From ! {send, To, Message},
      ok
  end.

%% 强制网络同步（用于跨区域连接后）
force_network_sync() ->
  io:format("=== Force Network Synchronization ===~n"),

  %% 获取所有活跃路由器
  AllCities = lists:flatten(maps:values(?CITIES)),
  ActiveRouters = lists:filter(fun(City) ->
    whereis(City) =/= undefined
                               end, AllCities),

  io:format("Active routers: ~w~n", [ActiveRouters]),

  %% 强制所有路由器广播
  io:format("Step 1: Broadcasting from all active routers...~n"),
  lists:foreach(fun(Router) ->
    io:format("  Broadcasting from ~w~n", [Router]),
    Router ! broadcast,
    timer:sleep(100)
                end, ActiveRouters),

  %% 等待广播传播
  io:format("Waiting for broadcast propagation...~n"),
  timer:sleep(2000),

  %% 强制所有路由器更新路由表
  io:format("Step 2: Updating all routing tables...~n"),
  lists:foreach(fun(Router) ->
    io:format("  Updating ~w~n", [Router]),
    Router ! update,
    timer:sleep(100)
                end, ActiveRouters),

  %% 等待路由表计算完成
  io:format("Waiting for routing table computation...~n"),
  timer:sleep(1500),

  io:format("Network synchronization complete~n").

%% 测试两个路由器之间的连接
test_connection(From, To) ->
  io:format("=== Testing Connection: ~w -> ~w ===~n", [From, To]),

  case routy:status(From) of
    {_, _, _, Intf, Table, Map} ->
      Interfaces = intf:list(Intf),
      io:format("~w interfaces: ~w~n", [From, Interfaces]),
      io:format("~w routing table: ~w~n", [From, Table]),
      io:format("~w network map: ~w~n", [From, Map]),

      %% 检查路由表中是否有到目标的路由
      case lists:keyfind(To, 1, Table) of
        {To, Gateway} ->
          io:format("Route found: ~w -> ~w via ~w~n", [From, To, Gateway]);
        false ->
          io:format("No route found from ~w to ~w~n", [From, To])
      end;
    timeout ->
      io:format("Timeout getting status from ~w~n", [From])
  end.

%% 显示网络状态
show_status() ->
  io:format("=== Network Status Report ===~n"),
  io:format("Current node: ~w~n", [node()]),
  io:format("Connected nodes: ~w~n", [nodes()]),

  AllCities = lists:flatten(maps:values(?CITIES)),
  RunningRouters = lists:filter(fun(City) ->
    whereis(City) =/= undefined
                                end, AllCities),

  io:format("Total routers defined: ~w~n", [length(AllCities)]),
  io:format("Running routers: ~w~n", [length(RunningRouters)]),
  io:format("Active routers: ~w~n", [RunningRouters]),

  %% 显示每个运行路由器的详细状态
  io:format("~n--- Detailed Router Status ---~n"),
  lists:foreach(fun(Router) ->
    case routy:status(Router) of
      {Name, Counter, _Hist, Intf, Table, _Map} ->
        Interfaces = intf:list(Intf),
        io:format("~w: counter=~w, interfaces=~w, routes=~w~n",
          [Name, Counter, Interfaces, length(Table)]),
        %% 显示路由表内容
        if length(Table) > 0 ->
          io:format("  Routes: ~w~n", [Table]);
          true -> ok
        end;
      timeout ->
        io:format("~w: timeout~n", [Router])
    end
                end, RunningRouters).

%% 清理所有路由器
cleanup() ->
  io:format("=== Cleaning up all routers on node ~w ===~n", [node()]),

  AllCities = lists:flatten(maps:values(?CITIES)),
  StoppedCount = lists:foldl(fun(City, Count) ->
    case whereis(City) of
      undefined -> Count;
      _ ->
        City ! stop,
        timer:sleep(50),
        Count + 1
    end
                             end, 0, AllCities),

  timer:sleep(500),
  io:format("Cleanup complete: stopped ~w routers~n", [StoppedCount]).