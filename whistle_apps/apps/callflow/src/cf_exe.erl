%%%-------------------------------------------------------------------
%%% @copyright (C) 2010-2012, VoIP INC
%%% @doc
%%% @end
%%% @contributors
%%%   Karl Anderson
%%%-------------------------------------------------------------------
-module(cf_exe).

-behaviour(gen_listener).

%% API
-export([start_link/1]).
-export([relay_amqp/2, send_amqp/3]).
-export([get_call/1, set_call/1]).
-export([callid/1, callid/2]).
-export([queue_name/1]).
-export([control_queue/1, control_queue/2]).
-export([continue/1, continue/2]).
-export([branch/2]).
-export([stop/1]).
-export([transfer/1]).
-export([control_usurped/1]).
-export([get_branch_keys/1, get_all_branch_keys/1]).
-export([attempt/1, attempt/2]).
-export([wildcard_is_empty/1]).
-export([callid_update/3]).
-export([add_event_listener/2]).

%% gen_listener callbacks
-export([init/1
         ,handle_call/3
         ,handle_cast/2
         ,handle_info/2
         ,handle_event/2
         ,terminate/2
         ,code_change/3
        ]).

-include("callflow.hrl").

-define(CALL_SANITY_CHECK, 30000).

-define(RESPONDERS, [{{?MODULE, 'relay_amqp'}
                      ,[{<<"*">>, <<"*">>}]
                     }
                    ]).
-define(QUEUE_NAME, <<>>).
-define(QUEUE_OPTIONS, []).
-define(CONSUME_OPTIONS, []).

-record(state, {call = whapps_call:new() :: whapps_call:call()
                ,flow = wh_json:new() :: wh_json:object()
                ,cf_module_pid :: pid()
                ,status = <<"sane">> :: ne_binary()
                ,queue :: api_binary()
               }).
-type state() :: #state{}.

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {'ok', Pid} | 'ignore' | {'error', Error}
%% @end
%%--------------------------------------------------------------------
start_link(Call) ->
    CallId = whapps_call:call_id(Call),
    Bindings = [{'call', [{'callid', CallId}]}
                ,{'self', []}
               ],
    gen_listener:start_link(?MODULE, [{'responders', ?RESPONDERS}
                                      ,{'bindings', Bindings}
                                      ,{'queue_name', ?QUEUE_NAME}
                                      ,{'queue_options', ?QUEUE_OPTIONS}
                                      ,{'consume_options', ?CONSUME_OPTIONS}
                                     ], [Call]).

-spec get_call(pid() | whapps_call:call()) -> {'ok', whapps_call:call()}.
get_call(Srv) when is_pid(Srv) ->
    gen_server:call(Srv, {'get_call'}, 1000);
get_call(Call) ->
    Srv = whapps_call:kvs_fetch('cf_exe_pid', Call),
    get_call(Srv).

-spec set_call(whapps_call:call()) -> 'ok'.
set_call(Call) ->
    Srv = whapps_call:kvs_fetch('cf_exe_pid', Call),
    gen_server:cast(Srv, {'set_call', Call}).

-spec continue(whapps_call:call() | pid()) -> 'ok'.
-spec continue(ne_binary(), whapps_call:call() | pid()) -> 'ok'.
continue(Srv) -> continue(<<"_">>, Srv).

continue(Key, Srv) when is_pid(Srv) ->
    gen_listener:cast(Srv, {'continue', Key});
continue(Key, Call) ->
    Srv = whapps_call:kvs_fetch('cf_exe_pid', Call),
    continue(Key, Srv).

-spec branch(wh_json:object(), whapps_call:call() | pid()) -> 'ok'.
branch(Flow, Srv) when is_pid(Srv) ->
    gen_listener:cast(Srv, {branch, Flow});
branch(Flow, Call) ->
    Srv = whapps_call:kvs_fetch('cf_exe_pid', Call),
    branch(Flow, Srv).


add_event_listener(Srv, {_,_,_}=SpawnInfo) when is_pid(Srv) ->
    gen_listener:cast(Srv, {add_event_listener, SpawnInfo});
add_event_listener(Call, {_,_,_}=SpawnInfo) ->
    add_event_listener(whapps_call:kvs_fetch('cf_exe_pid', Call), SpawnInfo).

-spec stop(whapps_call:call() | pid()) -> 'ok'.
stop(Srv) when is_pid(Srv) ->
    gen_listener:cast(Srv, {stop});
stop(Call) ->
    Srv = whapps_call:kvs_fetch('cf_exe_pid', Call),
    stop(Srv).

-spec transfer(whapps_call:call() | pid()) -> 'ok'.
transfer(Srv) when is_pid(Srv) ->
    gen_listener:cast(Srv, {transfer});
transfer(Call) ->
    Srv = whapps_call:kvs_fetch('cf_exe_pid', Call),
    transfer(Srv).

-spec control_usurped(whapps_call:call() | pid()) -> 'ok'.
control_usurped(Srv) when is_pid(Srv) ->
    gen_listener:cast(Srv, {control_usurped});
control_usurped(Call) ->
    Srv = whapps_call:kvs_fetch('cf_exe_pid', Call),
    control_usurped(Srv).

-spec callid_update(ne_binary(), ne_binary(), whapps_call:call() | pid()) -> 'ok'.
callid_update(CallId, CtrlQ, Srv) when is_pid(Srv) ->
    put(callid, CallId),
    gen_listener:cast(Srv, {callid_update, CallId, CtrlQ});
callid_update(CallId, CtrlQ, Call) ->
    Srv = whapps_call:kvs_fetch('cf_exe_pid', Call),
    callid_update(CallId, CtrlQ, Srv).

-spec callid(whapps_call:call() | pid()) -> ne_binary().
-spec callid(api_binary(), whapps_call:call()) -> ne_binary().

callid(Srv) when is_pid(Srv) ->
    CallId = gen_server:call(Srv, {callid}, 1000),
    put(callid, CallId),
    CallId;
callid(Call) ->
    Srv = whapps_call:kvs_fetch('cf_exe_pid', Call),
    callid(Srv).

callid(_, Call) ->
    callid(Call).

-spec queue_name(whapps_call:call() | pid()) -> ne_binary().
queue_name(Srv) when is_pid(Srv) ->
    gen_listener:queue_name(Srv);
queue_name(Call) ->
    Srv = whapps_call:kvs_fetch('cf_exe_pid', Call),
    queue_name(Srv).

-spec control_queue(whapps_call:call() | pid()) -> ne_binary().
-spec control_queue(api_binary(), whapps_call:call() | pid()) -> ne_binary().

control_queue(Srv) when is_pid(Srv) -> gen_listener:call(Srv, {'control_queue_name'});
control_queue(Call) -> control_queue(whapps_call:kvs_fetch('cf_exe_pid', Call)).
control_queue(_, Call) -> control_queue(Call).

-spec get_branch_keys(whapps_call:call() | pid()) -> {'branch_keys', wh_json:json_strings()}.
get_branch_keys(Srv) when is_pid(Srv) ->
    gen_listener:call(Srv, {'get_branch_keys'});
get_branch_keys(Call) ->
    Srv = whapps_call:kvs_fetch('cf_exe_pid', Call),
    get_branch_keys(Srv).

-spec get_all_branch_keys(whapps_call:call() | pid()) -> {'branch_keys', wh_json:json_strings()}.
get_all_branch_keys(Srv) when is_pid(Srv) ->
    gen_listener:call(Srv, {'get_branch_keys', 'all'});
get_all_branch_keys(Call) ->
    Srv = whapps_call:kvs_fetch('cf_exe_pid', Call),
    get_all_branch_keys(Srv).

-spec attempt(whapps_call:call() | pid()) ->
                           {'attempt_resp', 'ok'} |
                           {'attempt_resp', {'error', term()}}.
-spec attempt(ne_binary(), whapps_call:call() | pid()) ->
                           {'attempt_resp', 'ok'} |
                           {'attempt_resp', {'error', term()}}.
attempt(Srv) -> attempt(<<"_">>, Srv).

attempt(Key, Srv) when is_pid(Srv) ->
    gen_listener:call(Srv, {attempt, Key});
attempt(Key, Call) ->
    Srv = whapps_call:kvs_fetch('cf_exe_pid', Call),
    attempt(Key, Srv).

-spec wildcard_is_empty(whapps_call:call() | pid()) -> boolean().
wildcard_is_empty(Srv) when is_pid(Srv) ->
    gen_listener:call(Srv, {'wildcard_is_empty'});
wildcard_is_empty(Call) ->
    Srv = whapps_call:kvs_fetch('cf_exe_pid', Call),
    wildcard_is_empty(Srv).

-spec relay_amqp(wh_json:object(), wh_proplist()) -> any().
relay_amqp(JObj, Props) ->
    Pids = [props:get_value('cf_module_pid', Props)
            | props:get_value('cf_event_pids', Props, [])
           ],
    [whapps_call_command:relay_event(Pid, JObj) || Pid <- Pids, is_pid(Pid)].

-spec send_amqp(pid() | whapps_call:call(), api_terms(), wh_amqp_worker:publish_fun()) -> 'ok'.
send_amqp(Srv, API, PubFun) when is_pid(Srv), is_function(PubFun, 1) ->
    gen_listener:cast(Srv, {'send_amqp', API, PubFun});
send_amqp(Call, API, PubFun) when is_function(PubFun, 1) ->
    send_amqp(whapps_call:kvs_fetch('cf_exe_pid', Call), API, PubFun).

%%%===================================================================
%%% gen_listener callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {'ok', State} |
%%                     {'ok', State, Timeout} |
%%                     'ignore' |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([Call]) ->
    process_flag('trap_exit', 'true'),
    CallId = whapps_call:call_id(Call),
    put('callid', CallId),
    self() ! 'initialize',
    {'ok', #state{call=Call}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {'reply', Reply, State} |
%%                                   {'reply', Reply, State, Timeout} |
%%                                   {'noreply', State} |
%%                                   {'noreply', State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call({get_call}, _From, #state{call=Call}=State) ->
    {'reply', {'ok', Call}, State};
handle_call({callid}, _From, #state{call=Call}=State) ->
    {'reply', whapps_call:call_id_direct(Call), State};
handle_call({control_queue_name}, _From, #state{call=Call}=State) ->
    {'reply', whapps_call:control_queue_direct(Call), State};
handle_call({get_branch_keys}, _From, #state{flow = Flow}=State) ->
    Children = wh_json:get_value(<<"children">>, Flow, wh_json:new()),
    Reply = {branch_keys, lists:delete(<<"_">>, wh_json:get_keys(Children))},
    {'reply', Reply, State};
handle_call({get_branch_keys, all}, _From, #state{flow = Flow}=State) ->
    Children = wh_json:get_value(<<"children">>, Flow, wh_json:new()),
    Reply = {branch_keys, wh_json:get_keys(Children)},
    {'reply', Reply, State};
handle_call({attempt, Key}, _From, #state{flow=Flow}=State) ->
    case wh_json:get_value([<<"children">>, Key], Flow) of
        'undefined' ->
            lager:info("attempted 'undefined' child ~s", [Key]),
            Reply = {'attempt_resp', {'error', 'undefined'}},
            {'reply', Reply, State};
        NewFlow ->
            case wh_json:is_empty(NewFlow) of
                'true' ->
                    lager:info("attempted empty child ~s", [Key]),
                    Reply = {'attempt_resp', {'error', 'empty'}},
                    {'reply', Reply, State};
                'false' ->
                    lager:info("branching to attempted child ~s", [Key]),
                    Reply = {'attempt_resp', 'ok'},
                    {'reply', Reply, launch_cf_module(State#state{flow = NewFlow})}
            end
    end;
handle_call({wildcard_is_empty}, _From, #state{flow = Flow}=State) ->
    case wh_json:get_value([<<"children">>, <<"_">>], Flow) of
        'undefined' -> {'reply', 'true', State};
        ChildFlow -> {'reply', wh_json:is_empty(ChildFlow), State}
    end;
handle_call(_Request, _From, State) ->
    Reply = {'error', 'unimplemented'},
    {'reply', Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {'noreply', State} |
%%                                  {'noreply', State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast({'set_call', Call}, State) ->
    {'noreply', State#state{call=Call}};
handle_cast({'continue', Key}, #state{flow=Flow}=State) ->
    lager:info("continuing to child ~s", [Key]),
    case wh_json:get_value([<<"children">>, Key], Flow) of
        'undefined' when Key =:= <<"_">> ->
            lager:info("wildcard child does not exist, we are lost...hanging up"),
            {'stop', 'normal', State};
        'undefined' ->
            lager:info("requested child does not exist, trying wild card", [Key]),
            ?MODULE:continue(self()),
            {'noreply', State};
        NewFlow ->
            case wh_json:is_empty(NewFlow) of
                'true' -> {'stop', 'normal', State};
                'false' -> {'noreply', launch_cf_module(State#state{flow=NewFlow})}
            end
    end;
handle_cast({stop}, State) ->
    {stop, normal, State};
handle_cast({transfer}, State) ->
    {stop, {shutdown, transfer}, State};
handle_cast({control_usurped}, State) ->
    {stop, {shutdown, control_usurped}, State};
handle_cast({branch, NewFlow}, State) ->
    lager:info("callflow has been branched"),
    {'noreply', launch_cf_module(State#state{flow=NewFlow})};
handle_cast({callid_update, NewCallId, NewCtrlQ}, #state{call=Call}=State) ->
    put(callid, NewCallId),
    PrevCallId = whapps_call:call_id_direct(Call),
    lager:info("updating callid to ~s (from ~s), catch you on the flip side", [NewCallId, PrevCallId]),
    lager:info("removing call event bindings for ~s", [PrevCallId]),
    gen_listener:rm_binding(self(), call, [{callid, PrevCallId}]),
    lager:info("binding to new call events"),
    gen_listener:add_binding(self(), call, [{callid, NewCallId}]),
    lager:info("updating control q to ~s", [NewCtrlQ]),
    NewCall = whapps_call:set_call_id(NewCallId, whapps_call:set_control_queue(NewCtrlQ, Call)),
    {'noreply', State#state{call=NewCall}};

handle_cast({add_event_listener, {M, F, A}}, #state{call=Call}=State) ->
    try spawn_link(M, F, [Call | A]) of
        P when is_pid(P) ->
            lager:info("started event listener ~p from ~s:~s", [P, M, F]),
            {'noreply', State#state{call=whapps_call:kvs_update(cf_event_pids
                                                              ,fun(Ps) -> [P | Ps] end
                                                              ,[P]
                                                              ,Call
                                                             )}}
    catch
        _:_R ->
            lager:info("failed to spawn ~s:~s: ~p", [M, F, _R]),
            {'noreply', State}
    end;

handle_cast({'gen_listener', {'created_queue', Q}}, #state{call=Call}=State) ->
    {'noreply', launch_cf_module(State#state{call=whapps_call:set_controller_queue(Q, Call)
                                           ,queue=Q})};

handle_cast({send_amqp, API, PubFun}, #state{call=Call}=State) ->
    send_amqp_message(Call, API, PubFun),
    {'noreply', State};

handle_cast(_Msg, State) ->
    lager:debug("unhandled cast: ~p", [_Msg]),
    {'noreply', State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {'noreply', State} |
%%                                   {'noreply', State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(initialize, #state{call=Call}) ->
    log_call_information(Call),
    Flow = whapps_call:kvs_fetch(cf_flow, Call),
    Updaters = [fun(C) -> whapps_call:kvs_store('cf_exe_pid', self(), C) end
                ,fun(C) -> whapps_call:call_id_helper(fun cf_exe:callid/2, C) end
                ,fun(C) -> whapps_call:control_queue_helper(fun cf_exe:control_queue/2, C) end
               ],
    {'noreply', #state{call=lists:foldr(fun(F, C) -> F(C) end, Call, Updaters)
                       ,flow=Flow
                      }};
handle_info({'EXIT', _, normal}, State) ->
    %% handle normal exits so we dont need a guard on the next clause, cleaner looking...
    {'noreply', State};
handle_info({'EXIT', Pid, Reason}, #state{cf_module_pid=Pid, call=Call}=State) ->
    LastAction = whapps_call:kvs_fetch(cf_last_action, Call),
    lager:error("action ~s died unexpectedly: ~p", [LastAction, Reason]),
    ?MODULE:continue(self()),
    {'noreply', State};
handle_info(_Msg, State) ->
    lager:debug("unhandled message: ~p", [_Msg]),
    {'noreply', State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% @end
%%--------------------------------------------------------------------
handle_event(JObj, #state{cf_module_pid=Pid, call=Call, queue=ControllerQ}) ->
    CallId = whapps_call:call_id_direct(Call),
    Others = whapps_call:kvs_fetch(cf_event_pids, [], Call),

    case {whapps_util:get_event_type(JObj), wh_json:get_value(<<"Call-ID">>, JObj)} of
        {{<<"call_event">>, <<"call_id_update">>},_} ->
            NewCallId = wh_json:get_value(<<"Call-ID">>, JObj),
            NewCtrlQ = wh_json:get_value(<<"Control-Queue">>, JObj),
            callid_update(NewCallId, NewCtrlQ, self()),
            'ignore';
        {{<<"call_event">>, <<"control_transfer">>}, _} ->
            transfer(self()),
            'ignore';
        {{<<"call_event">>, <<"usurp_control">>}, CallId} ->
            _ = case wh_json:get_value(<<"Controller-Queue">>, JObj) of
                    ControllerQ -> ok;
                    _Else -> control_usurped(self())
                end,
            'ignore';
        {{<<"error">>, _}, _} ->
            case wh_json:get_value([<<"Request">>, <<"Call-ID">>], JObj) of
                CallId -> {'reply', [{cf_module_pid, Pid}
                                   ,{cf_event_pids, Others}
                                  ]};
                'undefined' -> {'reply', [{cf_module_pid, Pid}
                                      ,{cf_event_pids, Others}
                                     ]};
                _Else -> 'ignore'
            end;
        {_, CallId} ->
            {'reply', [{cf_module_pid, Pid}
                     ,{cf_event_pids, Others}
                    ]};
        {_, _Else} when Others =:= [] ->
            lager:info("received event from call ~s while relaying for ~s, dropping", [_Else, CallId]),
            'ignore';
        {_Evt, _Else} ->
            lager:info("the others want to know about ~p", [_Evt]),
            {'reply', [{cf_event_pids, Others}]}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_listener when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_listener terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate({'shutdown', 'transfer'}, _) ->
    lager:info("callflow execution has been transfered");
terminate({'shutdown', 'control_usurped'}, _) ->
    lager:info("the call has been usurped by an external process");
terminate(_Reason, #state{call=Call}) ->
    Cmd = [{<<"Event-Name">>, <<"command">>}
           ,{<<"Event-Category">>, <<"call">>}
           ,{<<"Application-Name">>, <<"hangup">>}
          ],
    send_command(Cmd, whapps_call:control_queue_direct(Call), whapps_call:call_id_direct(Call)),
    lager:info("callflow execution has been stopped: ~p", [_Reason]).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {'ok', NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {'ok', State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
%%--------------------------------------------------------------------
%% @private
%% this function determines if the callflow module specified at the
%% current node is 'available' and attempts to launch it if so.
%% Otherwise it will advance to the next child in the flow
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec launch_cf_module(state()) -> state().
launch_cf_module(#state{call=Call, flow=Flow}=State) ->
    Module = <<"cf_", (wh_json:get_value(<<"module">>, Flow))/binary>>,
    Data = wh_json:get_value(<<"data">>, Flow, wh_json:new()),
    {Pid, Action} = maybe_start_cf_module(Module, Data, Call),
    State#state{cf_module_pid=Pid, call=whapps_call:kvs_store(cf_last_action, Action, Call)}.

-spec maybe_start_cf_module(ne_binary(), wh_proplist(), whapps_call:call()) ->
                                         {pid() | 'undefined', atom()}.
maybe_start_cf_module(ModuleBin, Data, Call) ->
    try wh_util:to_atom(ModuleBin) of
        CFModule ->
            lager:info("moving to action ~s", [CFModule]),
            spawn_cf_module(CFModule, Data, Call)
    catch
        error:undef -> cf_module_not_found(Call);
        error:badarg ->
            %% module not in the atom table yet
            case code:where_is_file(wh_util:to_list(<<ModuleBin/binary, ".beam">>)) of
                non_existing -> cf_module_not_found(Call);
                _Path ->
                    wh_util:to_atom(ModuleBin, 'true'), %% put atom into atom table
                    maybe_start_cf_module(ModuleBin, Data, Call)
            end
    end.

-spec cf_module_not_found(whapps_call:call()) ->
                                 {'undefined', atom()}.
cf_module_not_found(Call) ->
    lager:error("unknown callflow action, reverting to last action"),
    ?MODULE:continue(self()),
    {undefined, whapps_call:kvs_fetch(cf_last_action, Call)}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% helper function to spawn a linked callflow module, from the entry
%% point 'handle' having set the callid on the new process first
%% @end
%%--------------------------------------------------------------------
-spec spawn_cf_module(CFModule, list(), whapps_call:call()) -> {pid(), CFModule}.
spawn_cf_module(CFModule, Data, Call) ->
    AMQPConsumer = wh_amqp_channel:consumer_pid(),
    {spawn_link(
       fun() ->
               _ = wh_amqp_channel:consumer_pid(AMQPConsumer),
               put(callid, whapps_call:call_id_direct(Call)),
               try
                   CFModule:handle(Data, Call)
               catch
                   _E:R ->
                       ST = erlang:get_stacktrace(),
                       lager:info("action ~s died unexpectedly (~s): ~p", [CFModule, _E, R]),
                       wh_util:log_stacktrace(ST),
                       throw(R)
               end
       end), CFModule}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% unlike the whapps_call_command this send command does not call the
%% functions of this module to form the headers, nor does it set
%% the reply queue.  Used when this module is terminating to send
%% a hangup command without relying on the (now terminated) cf_exe.
%% @end
%%--------------------------------------------------------------------
-spec send_amqp_message(whapps_call:call(), api_terms(), wh_amqp_worker:publish_fun()) -> 'ok'.
send_amqp_message(Call, API, PubFun) ->
    PubFun(add_server_id(API, whapps_call:controller_queue(Call))).

-spec send_command(wh_proplist(), api_binary(), api_binary()) -> 'ok'.
send_command(_, 'undefined', _) -> lager:debug("no control queue to send command to");
send_command(_, _, 'undefined') -> lager:debug("no call id to send command to");
send_command(Command, ControlQ, CallId) ->
    Props = Command ++ [{<<"Call-ID">>, CallId}
                       | wh_api:default_headers(?APP_NAME, ?APP_VERSION)
                      ],
    whapps_util:amqp_pool_send(Props, fun(P) -> wapi_dialplan:publish_command(ControlQ, P) end).

-spec add_server_id(api_terms(), ne_binary()) -> api_terms().
add_server_id(API, Q) when is_list(API) ->
    [{<<"Server-ID">>, Q} | props:delete(<<"Server-ID">>, API)];
add_server_id(API, Q) ->
    wh_json:set_value(<<"Server-ID">>, Q, API).

-spec log_call_information(whapps_call:call()) -> 'ok'.
log_call_information(Call) ->
    lager:info("executing callflow ~s", [whapps_call:kvs_fetch(cf_flow_id, Call)]),
    lager:info("account id ~s", [whapps_call:account_id(Call)]),
    lager:info("request ~s", [whapps_call:request(Call)]),
    lager:info("to ~s", [whapps_call:to(Call)]),
    lager:info("from ~s", [whapps_call:from(Call)]),
    lager:info("CID ~s ~s", [whapps_call:caller_id_name(Call), whapps_call:caller_id_number(Call)]),
    case whapps_call:inception(Call) of
        <<"offnet">> = I -> lager:info("inception ~s: call began from outside the network", [I]);
        <<"onnet">> = I -> lager:info("inception ~s: call began on the network", [I]);
        I -> lager:info("inception ~s", [I])
    end,
    lager:info("authorizing id ~s", [whapps_call:authorizing_id(Call)]).
