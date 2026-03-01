%%%-------------------------------------------------------------------
%%% @author 23229
%%% @copyright (C) 2025, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 13. 9月 2025 20:30
%%%-------------------------------------------------------------------
-module(routy).
-export([start/2, stop/1, status/1]).

%% 启动路由器进程并注册
%% Reg: 注册名称 (如 r1, r2)
%% Name: 路由器符号名称 (如 stockholm, london)
start(Reg, Name) ->
  register(Reg, spawn(fun() -> init(Name) end)).

%% 停止路由器进程
stop(Node) ->
  Node ! stop,
  unregister(Node).

%% 获取路由器状态
status(Node) ->
  Node ! {status, self()},
  receive
    {status, Status} -> Status
  after 5000 ->
    timeout
  end.

%% 初始化路由器状态
init(Name) ->
  Intf = intf:new(),
  Map = map:new(),
  Table = dijkstra:table([], Map), % 初始时没有网关
  Hist = hist:new(Name),
  router(Name, 0, Hist, Intf, Table, Map).

%% 主路由器进程循环
router(Name, N, Hist, Intf, Table, Map) ->
  receive
  %% 添加接口连接
    {add, Node, Pid} ->
      io:format("~w: adding interface to ~w~n", [Name, Node]),
      Ref = erlang:monitor(process, Pid),
      Intf1 = intf:add(Node, Ref, Pid, Intf),
      router(Name, N, Hist, Intf1, Table, Map);

  %% 移除接口连接
    {remove, Node} ->
      io:format("~w: removing interface to ~w~n", [Name, Node]),
      case intf:ref(Node, Intf) of
        {ok, Ref} ->
          erlang:demonitor(Ref),
          Intf1 = intf:remove(Node, Intf),
          router(Name, N, Hist, Intf1, Table, Map);
        notfound ->
          router(Name, N, Hist, Intf, Table, Map)
      end;

  %% 进程DOWN消息处理
    {'DOWN', Ref, process, _, _} ->
      case intf:name(Ref, Intf) of
        {ok, Down} ->
          io:format("~w: exit received from ~w~n", [Name, Down]),
          Intf1 = intf:remove(Down, Intf),
          router(Name, N, Hist, Intf1, Table, Map);
        notfound ->
          router(Name, N, Hist, Intf, Table, Map)
      end;

  %% 处理链路状态消息
    {links, Node, R, Links} ->
      io:format("~w: received link-state message from ~w~n", [Name, Node]),
      case hist:update(Node, R, Hist) of
        {new, Hist1} ->
          io:format("~w: new link-state message, broadcasting~n", [Name]),
          intf:broadcast({links, Node, R, Links}, Intf),
          Map1 = map:update(Node, Links, Map),
          router(Name, N, Hist1, Intf, Table, Map1);
        old ->
          io:format("~w: old link-state message, ignoring~n", [Name]),
          router(Name, N, Hist, Intf, Table, Map)
      end;

  %% 更新路由表
    update ->
      io:format("~w: updating routing table~n", [Name]),
      Gateways = intf:list(Intf),
      Table1 = dijkstra:table(Gateways, Map),
      io:format("~w: routing table updated with gateways ~w~n", [Name, Gateways]),
      router(Name, N, Hist, Intf, Table1, Map);

  %% 广播链路状态消息
    broadcast ->
      io:format("~w: broadcasting link-state message~n", [Name]),
      Links = intf:list(Intf),
      Message = {links, Name, N, Links},
      intf:broadcast(Message, Intf),
      router(Name, N+1, Hist, Intf, Table, Map);

  %% 路由消息到目的地（本地）
    {route, Name, From, Message} ->
      io:format("~w: received message '~w' from ~w~n", [Name, Message, From]),
      router(Name, N, Hist, Intf, Table, Map);

  %% 路由消息到其他目的地
    {route, To, From, Message} ->
      io:format("~w: routing message '~w' from ~w to ~w~n", [Name, Message, From, To]),
      case dijkstra:route(To, Table) of
        {ok, Gw} ->
          case intf:lookup(Gw, Intf) of
            {ok, Pid} ->
              io:format("~w: forwarding via gateway ~w~n", [Name, Gw]),
              Pid ! {route, To, From, Message};
            notfound ->
              io:format("~w: gateway ~w not found in interfaces~n", [Name, Gw])
          end;
        notfound ->
          io:format("~w: no route to ~w found~n", [Name, To])
      end,
      router(Name, N, Hist, Intf, Table, Map);

  %% 本地用户发送消息
    {send, To, Message} ->
      io:format("~w: sending message '~w' to ~w~n", [Name, Message, To]),
      self() ! {route, To, Name, Message},
      router(Name, N, Hist, Intf, Table, Map);

  %% 状态查询
    {status, From} ->
      io:format("~w: status requested~n", [Name]),
      From ! {status, {Name, N, Hist, Intf, Table, Map}},
      router(Name, N, Hist, Intf, Table, Map);

  %% 停止路由器
    stop ->
      io:format("~w: stopping router~n", [Name]),
      ok;

  %% 处理未知消息
    Unknown ->
      io:format("~w: received unknown message ~w~n", [Name, Unknown]),
      router(Name, N, Hist, Intf, Table, Map)
  end.
