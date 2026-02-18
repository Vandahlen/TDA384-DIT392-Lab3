-module(client).
-export([handle/2, initial_state/3]).

% This record defines the structure of the state of a client.
% Add whatever other fields you need.
-record(client_st, {
    gui, % atom of the GUI process
    nick, % nick/username of the client
    server % atom of the chat server
}).

% Return an initial state record. This is called from GUI.
% Do not change the signature of this function.
initial_state(Nick, GUIAtom, ServerAtom) ->
    #client_st{
        gui = GUIAtom,
        nick = Nick,
        server = ServerAtom
    }.

% Join channel
handle(St, {join, Channel}) ->
    Server = St#client_st.server,
    Nick = St#client_st.nick,
    Result = case catch genserver:request(Server, {join, Channel, self(), Nick}) of
        {'EXIT', _} -> {error, server_not_reached, "Server timed out"};
        timeout_error -> {error, server_not_reached, "Server timed out"};
        Other -> Other
    end,
    {reply, Result, St};

% Leave channel
handle(St, {leave, Channel}) ->
    Server = St#client_st.server,
    Result = case catch genserver:request(Server, {leave, Channel, self()}) of
    {'EXIT', _} -> ok;
    timeout_error -> ok;
    Other -> Other
    end,
    {reply, Result, St};

% Sending message (from GUI, to channel)
handle(St, {message_send, Channel, Msg}) ->
    Server = St#client_st.server,
    Nick = St#client_st.nick,

    TryResult = catch genserver:request(Server, {message_send, Channel, self(), Nick, Msg}),

    Result = case TryResult of
        {'EXIT', _} -> {error, server_not_reached, "Server timed out"};
        timeout_error -> {error, server_not_reached, "Server timed out"};
        {error, user_not_joined, "Channel does not exist"} -> 
        {error, server_not_reached, "Channel does not exist"};
        Other -> Other
    end,
    {reply, Result, St};

% This case is only relevant for the distinction assignment!
% Change nick (no check, local only)
handle(St, {nick, NewNick}) ->
    Server = St#client_st.server,
    OldNick = St#client_st.nick,

    Result = genserver:request(Server, {nick, OldNick, NewNick, self()}),
    
    case Result of
        ok -> 
            {reply, ok, St#client_st{nick = NewNick}};
        {error, nick_taken, _} ->
            {reply, {error, nick_taken, "Nick taken"}, St};
        OtherError ->
             {reply, OtherError, St}
    end;

% ---------------------------------------------------------------------------
% The cases below do not need to be changed...
% But you should understand how they work!

% Get current nick
handle(St, whoami) ->
    {reply, St#client_st.nick, St} ;

% Incoming message (from channel, to GUI)
handle(St = #client_st{gui = GUI}, {message_receive, Channel, Nick, Msg}) ->
    gen_server:call(GUI, {message_receive, Channel, Nick++"> "++Msg}),
    {reply, ok, St} ;

% Quit client via GUI
handle(St, quit) ->
    % Any cleanup should happen here, but this is optional
    {reply, ok, St} ;

% Catch-all for any unhandled requests
handle(St, _Data) ->
    {reply, {error, not_implemented, "Client does not handle this command"}, St} .
    