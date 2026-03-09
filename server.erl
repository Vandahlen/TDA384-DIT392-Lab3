-module(server).
-export([start/1, stop/1, channel_loop/2]). 

-record(serverState, {
    channels = #{}, % Maps ChannelName -> ChannelPid
    nicks = #{}     % Maps Nick -> Pid for distinction assignment
}).

% Start and register the main server.
start(ServerAtom) ->
    genserver:start(ServerAtom, #serverState{channels = #{}, nicks = #{}}, fun loop/2).

% Stop the server gracefully.
stop(ServerAtom) ->
    % Halt child channels first to prevent orphaned processes.
    catch genserver:request(ServerAtom, halt_associated_processes),
    genserver:stop(ServerAtom).

% Main server loop.
loop(State, Request) ->
    case Request of
        {join, Channel, Pid, Nick} ->
            Channels = State#serverState.channels,
            Nicks = State#serverState.nicks,

            % Concurrency: Get existing channel process or spawn a new one.
            {ChannelPid, NewChannels} = case maps:find(Channel, Channels) of
                error ->
                    CPid = spawn(server, channel_loop, [Channel, []]),
                    {CPid, maps:put(Channel, CPid, Channels)};
                {ok, CPid} -> 
                    {CPid, Channels}
            end,

            % Forward join request to the channel process.
            Ref = make_ref(),
            ChannelPid ! {request, self(), Ref, {join, Pid}},
            receive
                {result, Ref, ok} ->
                    NewNicks = maps:put(Nick, Pid, Nicks),
                    % Return ChannelPid so the client can communicate directly.
                    {reply, {ok, ChannelPid}, State#serverState{channels = NewChannels, nicks = NewNicks}};
                {result, Ref, Error} ->
                    {reply, Error, State#serverState{channels = NewChannels}}
            end;

        {leave, Channel, Pid} ->
            Channels = State#serverState.channels,
            
            case maps:find(Channel, Channels) of
                error ->
                    {reply, {error, user_not_joined, "Channel does not exist"}, State};
                {ok, ChannelPid} ->
                    % Forward leave request to the channel process.
                    Ref = make_ref(),
                    ChannelPid ! {request, self(), Ref, {leave, Pid}},
                    receive
                        {result, Ref, Reply} -> {reply, Reply, State}
                    end
            end;
        
        {nick, OldNick, NewNick, Pid} ->
            Nicks = State#serverState.nicks,
            
            % Ensure nickname uniqueness.
            case maps:is_key(NewNick, Nicks) of
                true ->
                    {reply, {error, nick_taken, "Nick already taken"}, State};
                false ->
                    NicksCleaned = maps:remove(OldNick, Nicks),
                    NewNicks = maps:put(NewNick, Pid, NicksCleaned),
                    {reply, ok, State#serverState{nicks = NewNicks}}
            end;

        {message_send, TargetChannel, _Pid, _Nick, _Msg} ->
            % Fallback: Handle send requests from clients not joined locally.
            Channels = State#serverState.channels,
            case maps:find(TargetChannel, Channels) of
                error -> {reply, {error, user_not_joined, "Channel does not exist"}, State};
                {ok, _ChannelPid} -> {reply, {error, user_not_joined, "You are not in this channel"}, State}
            end;

        halt_associated_processes -> 
            % Terminate all child channels for a clean shutdown.
            maps:foreach(fun(_Ch, CPid) -> exit(CPid, kill) end, State#serverState.channels),
            {reply, ok, State};
            
        _ -> 
            {reply, {error, unknown_command, "Server received unknown command"}, State}
    end.

% Independent channel process. Survives main server crashes.
channel_loop(Channel, Users) ->
    receive
        {request, From, Ref, {join, Pid}} ->
            % Prevent duplicate joins.
            case lists:member(Pid, Users) of
                true ->
                    From ! {result, Ref, {error, user_already_joined, "You are already in this channel"}},
                    channel_loop(Channel, Users);
                false ->
                    From ! {result, Ref, ok},
                    channel_loop(Channel, [Pid | Users])
            end;
            
        {request, From, Ref, {leave, Pid}} ->
            % Verify membership before removal.
            case lists:member(Pid, Users) of
                false ->
                    From ! {result, Ref, {error, user_not_joined, "You are not in this channel"}},
                    channel_loop(Channel, Users);
                true ->
                    From ! {result, Ref, ok},
                    channel_loop(Channel, lists:delete(Pid, Users))
            end;
            
        {request, From, Ref, {message_send, SenderPid, Nick, Msg}} ->
            % Exclude sender to prevent message echo.
            Recipients = lists:delete(SenderPid, Users),
            lists:foreach(fun(UserPid) ->
                % Broadcast message to all members.
                UserPid ! {request, self(), make_ref(), {message_receive, Channel, Nick, Msg}}
            end, Recipients),
            From ! {result, Ref, ok},
            channel_loop(Channel, Users)
    end.