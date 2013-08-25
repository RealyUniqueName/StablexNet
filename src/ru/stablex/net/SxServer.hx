package ru.stablex.net;

import haxe.io.Eof;
import haxe.io.Error;
import haxe.CallStack;
#if cpp
import cpp.net.Poll;
import cpp.vm.Deque;
import cpp.vm.Thread;
#elseif neko
import neko.net.Poll;
import neko.vm.Deque;
import neko.vm.Thread;
#end
import haxe.io.Bytes;
import haxe.Timer;
import sys.net.Host;
import sys.net.Socket;


/**
* Thread server
*
*/
class SxServer<Client,Message> {

    //server socket to accept client connections
    private var _sock : Socket;
    /**
    * Maximum amount of threads for handling client connections.
    * Also each thread runs one additional thread to read data from sockets.
    * So total amount of threads will be doubled:
    *   - one thread to accept new connections, disconnect sockets and send data;
    *   - another one to read data.
    */
    public var maxClientThreads : Int = 10;
    //maximum amount of clients per one thread
    public var maxClientPerThread : Int = 500;
    //Maximum client buffer length
    public var maxBufLength : Int = 65536;
    //client threads
    private var _threads : Array<ThreadData<Client,Message>>;
    //worker thread
    private var _worker : Thread;
    /**
    * Interval for calling `.update()` method in seconds.
    * Zero or negative value if you don't want to run `.update()`
    */
    public var updateInterval : Float = 0;
    //Thread to pass `.update()` to `.worker` every `.updateInterval` seconds
    private var _updater : Thread;


    /**
    * Constructor
    *
    */
    public function new () : Void{
        this._sock    = new Socket();
        this._threads = [];
    }//function new()


    /**
    * Create threads and other stuff
    *
    */
    private function _init() : Void {
        //update thread
        if( this.updateInterval > 0 ){
            this._updater = Thread.create( this._runThread.bind(this._update) );
        }

        //worker thread
        this._worker = Thread.create( this._runThread.bind(this._work) );

        //client threads
        var data : ThreadData<Client,Message>;
        for(i in this._threads.length...this.maxClientThreads){
            data = new ThreadData();
            data.thread = Thread.create( this._runThread.bind( this._clients.bind(data) ) );

            this._threads.push(data);
        }
    }//function _init()


    /**
    * Run server
    *
    */
    public function run (host:String, port:Int) : Void{
        this._init();

        this._sock.bind(new Host(host), port);
        this._sock.listen(10);

        Sys.println("SERVER STARTED");

        //accept new connections
        var s : Socket;
        while(true){
            try{
                s = this._sock.accept();
                s.setBlocking(false);
                this._addSocket(s);
            }catch(e:Dynamic){
                this.error(e);
            }
        }
    }//function run()


    /**
    * Add socket to the least populated thread
    *
    */
    private function _addSocket(s:Socket) : Void {
        //select thread {
            var data : ThreadData<Client,Message> = this._threads[0];
            for(i in 1...this._threads.length){
                if( this._threads[i].clients.length < data.clients.length ){
                    data = this._threads[i];
                }
            }
        //}

        //oops, no more space for new clients
        if( data.clients.length >= this.maxClientPerThread ){
            s.close();
            this.error("Server is full");

        //send socket to selected thread
        }else{
            data.thread.sendMessage( this._startInitClient.bind(data, s) );
        }
    }//function _addSocket()


    /**
    * Method to run threads
    *
    */
    private function _runThread(fn:Void->Void) : Void {
        try{
            fn();
        }catch(e:Dynamic){
            this.error(e);
        }
    }//function _clientThread()


    /**
    * Pass `.update()` to worker every `.updateInterval` seconds
    *
    */
    private function _update() : Void {
        while( this.updateInterval > 0 ){
            Sys.sleep(this.updateInterval);
            this.work(this.onUpdate);
        }
    }//function _update()


    /**
    * Send this work to worker
    *
    */
    public inline function work(fn:Void->Void) : Void {
        this._worker.sendMessage(fn);
    }//function work()


    /**
    * Worker method
    *
    */
    private function _work() : Void {
        var fn:Void->Void;

        while( true ) {
            fn = Thread.readMessage(true);

            try{
                fn();
            }catch(e:Dynamic){
                this.error(e);
            }
        }
    }//function _work()


    /**
    * Handle clients (connections, messages, etc)
    *
    */
    private function _clients(data:ThreadData<Client,Message>) : Void {
        //run thread to read data from sockets
        var readThread : Thread = Thread.create( this._runThread.bind( this._read.bind(data) ) );

        var fn : Void->Void;
        while(true){
            fn = Thread.readMessage(true);
            if( fn != null ){
                try{
                    fn();
                }catch(e:Dynamic){
                    this.error(e);
                }
            }
        }//while(true)
    }//function _clients()


    /**
    * Thread to read from sockets
    *
    */
    private function _read(data:ThreadData<Client,Message>) : Void {
        var poll  : Poll = new Poll(this.maxClientPerThread);
        var socks : Array<Socket> = [ data.socks.pop(true) ];
        var s     : Socket;

        while(true){
            //accept new sockets or remvoe disconnected
            while( (s = data.socks.pop(socks.length == 0)) != null ){
                if( cast(s.custom, ClientData<Dynamic,Dynamic>).online ){
                    socks.push(s);
                }else{
                    socks.remove(s);
                }
            }

            //poll sockets for data
            try{
                var p = poll.poll(socks, 1);

                for(s in poll.poll(socks, 1)){
                    try{
                        this._processData(data, s.custom);
                    }catch(e:Dynamic){
                        socks.remove(s);
                        //WTF?
                        if( !Std.is(e, Eof) ){
                            this.error(e);
                        }
                        this.disconnect(data, s.custom);
                    }
                }

            }catch(e:Dynamic){
                this.error(e);
            }
        }//while(true)
    }//function _read()


    /**
    * Start new client initialization
    *
    */
    private function _startInitClient(data:ThreadData<Client,Message>, s:Socket) : Void {
        var cdata : ClientData<Client,Message>;

        cdata = new ClientData();
        cdata.server = this;
        cdata.thread = data;
        cdata.sock   = s;
        cdata.online = true;

        data.clients.push(cdata);
        this._connect(data, cdata);
    }//function _startInitClient()


    /**
    * Send message
    *
    */
    public function sendMessage(data:ThreadData<Client,Message>, clientData:ClientData<Client,Message>, msg:Message) : Void {
        try{
            if( clientData.online ){
                var buf : Bytes = this.pack(msg);
                clientData.sock.output.writeFullBytes(buf, 0, buf.length);
            }else{
                throw "Can't send message to offline client.";
            }
        }catch(e:Dynamic){
            this.disconnect(data, clientData);
            this.error(e);
        }
    }//function _sendMessage()


    /**
    * On new socket this is sent to worker to create Client instance
    *
    */
    private function _connect(data:ThreadData<Client,Message>, clientData:ClientData<Client,Message>) : Void {
        //if in worker thread, fire onConnect event
        if( Thread.current() == this._worker ){
            try{
                clientData.client = this.onConnect(clientData.sock, clientData.send, clientData.close);
                clientData.sock.custom = clientData;
                data.socks.push(clientData.sock);
            }catch(e:Dynamic){
                this.error(e);
            }

        //if not in worker thread, send to worker
        }else{
            this.work( this._connect.bind(data, clientData) );
        }
    }//function _connect()


    /**
    * Disconnect client
    *
    */
    public function disconnect(data:ThreadData<Client,Message>, clientData:ClientData<Client,Message>) : Void {
        //if not in clients thread, send to that thread
        if( Thread.current() != data.thread ){
            //already disconnected
            if( !clientData.online ) return;

            clientData.online = false;
            clientData.server = null;
            data.socks.push(clientData.sock);

            data.thread.sendMessage( this.disconnect.bind( data, clientData) );

        //in client-thread
        }else{
            //remove client from thread. If it was removed previousely, do nothing
            if( data.clients.remove(clientData) ){
                if( clientData.online ){
                    clientData.online = false;
                    clientData.server = null;
                    data.socks.push(clientData.sock);
                }

                try{
                    clientData.sock.shutdown(true, true);
                    clientData.sock.close();
                }catch(e:Dynamic){
                    this.error(e);
                }

                //process disconnect
                this.work( this.onDisconnect.bind(clientData.client) );
            }
        }
    }//function disconnect()


    /**
    * Process error message
    *
    */
    public function error(e:Dynamic, sendStack:Bool = true) : Void {
        var stack : Array<StackItem> = (sendStack ? CallStack.exceptionStack() : null);

        if( Thread.current() == this._worker ){
            this.onError(e, stack);
        }else{
            this.work( onError.bind(e, stack) );
        }
    }//function error()


    /**
    * Read messages from clients
    *
    */
    private function _processData(data:ThreadData<Client,Message>, clientData:ClientData<Client,Message>) : Void {
        //free space in buffer
        var space : Int = clientData.buf.length - clientData.dataLength;

        //no free space, increase buffer
        if( space == 0 ){
            //if maximum buffer size is reached, disconnect client
            if( clientData.buf.length * 2 > this.maxBufLength ){
                throw "Maximum buffer size reached";
            }
            //create larger buffer
            var buf : Bytes = Bytes.alloc(clientData.buf.length * 2);
            buf.blit(0, clientData.buf, 0, clientData.dataLength);
            clientData.buf = buf;
            space = buf.length - clientData.dataLength;
        }

        //read from socket
        var bytesRead : Int = clientData.sock.input.readBytes(clientData.buf, clientData.dataLength, space);

        //extract and process messages {
            var pos    : Int = 0;
            var length : Int = clientData.dataLength + bytesRead;
            var msgExt : MsgExtract<Message>;

            while( length >= 0 ){
                msgExt = this.extract(clientData.buf, pos, length);

                //no new messages
                if( msgExt == null ){
                    break;

                //got message! work...
                }else{
                    pos    += msgExt.length;
                    length -= msgExt.length;

                    this.work( this.onMessage.bind(clientData.client, msgExt.msg) );
                }
            }//while()

            //move remaining bytes to the beginning of buffer
            if( pos > 0 ){
                clientData.buf.blit(0, clientData.buf, pos, length);
            }
            clientData.dataLength = length;
        //}
    }//function _processData()


    /**
    * Create new client object. Requested every time on new client connection
    *
    */
    public dynamic function onConnect(s:Socket, send:Message->Void, close:Void->Void) : Client {
        trace('connect!');
        return null;
    }//function onConnect()


    /**
    * Process disconnect
    *
    */
    public dynamic function onDisconnect(client:Client) : Void {
        trace('Disconnect');
    }//function onDisconnect()


    /**
    * Extract messages from buffer
    *
    * @param buf - received data buffer
    * @param pos - position of the first byte to process
    * @param length - bytes amount to process
    */
    public dynamic function extract (buf:Bytes, pos:Int, length:Int) : MsgExtract<Message> {
        return null;
    }//function extract()


    /**
    * Pack message to send.
    */
    public dynamic function pack (msg:Message) : Bytes {
        throw "SxServer.pack() is not implemented.";
        return null;
    }//function pack()


    /**
    * Called every `.updateInterval` seconds
    *
    */
    public dynamic function onUpdate() : Void {
        trace('update: ' + Timer.stamp());
    }//function onUpdate()


    /**
    * Handle client messages
    *
    */
    public dynamic function onMessage(client:Client, msg:Message) : Void {
        trace(msg);
    }//function onMessage()


    /**
    * Handle errors
    *
    */
    public dynamic function onError(e:Dynamic, exceptionStack:Null<Array<StackItem>>) : Void {
        if( exceptionStack != null && exceptionStack.length > 0 ){
            trace(CallStack.toString(exceptionStack));
        }
        trace(e);
    }//function onError()


}//class SxServer



/**
* Contains data associated to thread (clients list, thread object, etc)
* @private
*/
class ThreadData<Client,Message> {

    //thread object
    public var thread : Thread;
    //clients
    public var clients : Array<ClientData<Client,Message>>;
    //sockets
    public var socks : Deque<Socket>;


    /**
    * Constructor
    */
    public function new() : Void {
        this.clients = [];
        this.socks = new Deque();
    }//function new()


}//class ThreadData