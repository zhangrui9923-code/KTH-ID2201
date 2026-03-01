-module(worker).
-export([start/4, start/5]).

-define(change, 20).
-define(color, {0,0,0}).

%% 启动第一个worker（领导者）
start(Name, Module, Sleep, Jitter) ->
	spawn(fun() -> init(Name, Module, Sleep, Jitter) end).

init(Name, Module, Sleep, Jitter) ->
	rand:seed(exsplus, erlang:timestamp()),
	{ok, Cast} = apply(Module, start, [Name]),
	Color = ?color,
	io:format("worker ~w: started as leader with color ~w~n", [Name, Color]),
	worker(Name, Cast, Color, Sleep, Jitter, 0).

%% 加入现有组的worker
start(Name, Grp, Module, Sleep, Jitter) ->
	spawn(fun() -> init(Name, Grp, Module, Sleep, Jitter) end).

init(Name, Grp, Module, Sleep, Jitter) ->
	rand:seed(exsplus, erlang:timestamp()),
	{ok, Cast} = apply(Module, start, [Name, Grp]),
	receive
		{view, Group} ->
			io:format("worker ~w: received initial view ~w~n", [Name, Group]),
			%% 请求当前状态
			Ref = make_ref(),
			Cast ! {mcast, {state_request, Ref}},
			%% 等待状态响应
			Color = wait_for_state(Ref, ?color),
			io:format("worker ~w: started with color ~w~n", [Name, Color]),
			worker(Name, Cast, Color, Sleep, Jitter, 0);
		{error, Reason} ->
			io:format("worker ~w: error ~p~n", [Name, Reason])
	after 10000 ->
		io:format("worker ~w: timeout~n", [Name])
	end.

%% 等待状态响应，同时处理其他消息
wait_for_state(Ref, Default) ->
	receive
		{state_request, Ref} ->
			%% 收到自己的请求（从组播返回）
			receive
				{Ref, State} ->
					State
			after 5000 ->
				Default
			end;
		{Ref, State} ->
			%% 直接收到状态
			State;
		_ ->
			%% 忽略其他消息，继续等待
			wait_for_state(Ref, Default)
	after 10000 ->
		Default
	end.

worker(Name, Cast, Color, Sleep, Jitter, N) ->
	Wait = if Sleep == 0 -> 0; true -> rand:uniform(Sleep) end,
	receive
		{mcast, Msg} ->
			Cast ! {mcast, Msg},
			worker(Name, Cast, Color, Sleep, Jitter, N);

	%% 处理状态请求
		{state_request, Ref} ->
			Cast ! {mcast, {Ref, Color}},
			worker(Name, Cast, Color, Sleep, Jitter, N);

	%% 接收状态响应
		{Ref, NewColor} when is_tuple(NewColor), size(NewColor) == 3 ->
			io:format("worker ~w: received state ~w~n", [Name, NewColor]),
			worker(Name, Cast, NewColor, Sleep, Jitter, N);

	%% 颜色变化
		{color, NewColor} when is_tuple(NewColor), size(NewColor) == 3 ->
			io:format("worker ~w: color ~w -> ~w~n", [Name, Color, NewColor]),
			worker(Name, Cast, NewColor, Sleep, Jitter, N);

	%% 加入请求
		{join, Peer, Gms} ->
			Cast ! {join, Peer, Gms},
			worker(Name, Cast, Color, Sleep, Jitter, N);

	%% 视图变化
		{view, _Group} ->
			worker(Name, Cast, Color, Sleep, Jitter, N);

		stop ->
			ok;

		Error ->
			io:format("worker ~w: unknown message ~w~n", [Name, Error]),
			worker(Name, Cast, Color, Sleep, Jitter, N)
	after Wait ->
		%% 随机改变颜色
		case rand:uniform(?change) of
			?change ->
				NewColor = change_color(Color, Jitter),
				Cast ! {mcast, {color, NewColor}},
				worker(Name, Cast, NewColor, Sleep, Jitter, N+1);
			_ ->
				worker(Name, Cast, Color, Sleep, Jitter, N)
		end
	end.

change_color({R, G, B}, Jitter) ->
	{change_component(R, Jitter),
		change_component(G, Jitter),
		change_component(B, Jitter)}.

change_component(C, Jitter) ->
	Delta = rand:uniform(Jitter) - (Jitter div 2),
	NewC = C + Delta,
	if
		NewC < 0 -> 0;
		NewC > 255 -> 255;
		true -> NewC
	end.


 

