package ru.stablex.net;

import haxe.CallStack;
import haxe.io.Bytes;

#if flash
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.ProgressEvent;
    import flash.events.SecurityErrorEvent;
    import flash.utils.ByteArray;
    import flash.net.Socket;
#else
    import haxe.Timer;
    import haxe.io.Eof;
    import sys.net.Host;
    import sys.net.Socket;
#end

#if cpp
    import cpp.vm.Thread;
#elseif neko
    import neko.vm.Thread;
#end


/**
* Socket threaded client
*
*/
class SxClient<Message> {
    //if socket is connected
    public var online (default,null) : Bool = false;
    //socket
    private var _sock : Socket;
    //remote host
    public var host (default,null) : String;
    //remote port
    public var port (default,null) : Int;
    private var _buf : Bytes;
    //Maximum buffer length
    public var maxBufLength : Int = 65536;
    //useful data length in buffer
    private var _dataLength : Int = 0;

    #if !flash
        //thread for reading data
        private var _read : Thread;
        //thread for connection/sending data
        private var _send : Thread;
        //main thread
        private var _main : Thread;
        //buffer for reading from socket
    #end


    /**
    * Constructor
    *
    */
    public function new () : Void {
        this._sock = new Socket();
        this._buf = Bytes.alloc(1024);
        this._dataLength = 0;
    }//function new()


    /**
    * Create threads:
    *   - one thread for connect/disconnect and sending data
    *   - another one for reading data from server
    */
    public function connect (host:String, port:Int) : Void {
        this.host = host;
        this.port = port;

        if( this.online ){
            this.close();
        }

        #if flash
            try{
                this._sock.removeEventListener(Event.CLOSE, this._onClose);
                this._sock.removeEventListener(Event.CONNECT, this._onConnect);
                this._sock.removeEventListener(IOErrorEvent.IO_ERROR, this._onError);
                this._sock.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, this._onError);
                this._sock.removeEventListener(ProgressEvent.SOCKET_DATA, this._onData);

                this._sock.addEventListener(Event.CLOSE, this._onClose);
                this._sock.addEventListener(Event.CONNECT, this._onConnect);
                this._sock.addEventListener(IOErrorEvent.IO_ERROR, this._onError);
                this._sock.addEventListener(SecurityErrorEvent.SECURITY_ERROR, this._onError);
                this._sock.addEventListener(ProgressEvent.SOCKET_DATA, this._onData);

                this._sock.connect(host, port);
            }catch(e:Dynamic){
                this.error(e);
            }
        #else
            if( this._main == null ) this._main = Thread.current();
            if( this._send == null ) this._send = Thread.create( this._runThread.bind(this._threadSend) );
        #end
    }//function connect()


    /**
    * Send command to close connection and shutdown threads.
    *
    */
    public function close () : Void {
        #if flash
            try{
                this._sock.close();
                this._sock.dispatchEvent(new Event(Event.CLOSE));
            }catch(e:Dynamic){
                this.error(e);
            }
        #else
            if( Thread.current() == this._send ){
                this._disconnect();
            }else{
                this._send.sendMessage( this._disconnect );
            }
        #end
    }//function close()


    /**
    * Process error message
    *
    */
    public function error(e:Dynamic, noStack:Bool = false) : Void {
        var stack : Array<StackItem> = (noStack ? null : CallStack.exceptionStack());

        #if flash
            this.onError(e, stack);
        #else
            if( Thread.current() == this._main ){
                this.onError(e, stack);
            }else{
                this._fire( onError.bind(e, stack) );
            }
        #end
    }//function error()


    /**
    * Send message to server
    *
    */
    public function send (msg:Message) : Void {
        #if flash
            try{
                if( this._sock.connected ){
                    var buf : Bytes = this.pack(msg);
                    this._sock.writeBytes(buf.getData(), 0, buf.length);
                    this._sock.flush();
                }else{
                    throw "Can't send messages while not connected.";
                }
            }catch(e:Dynamic){
                this.error(e);
            }
        #else
            if( Thread.current() != this._send ){
                this._send.sendMessage( this.send.bind(msg) );
            }else{
                try{
                    if( this.online ){
                        var buf : Bytes = this.pack(msg);
                        this._sock.output.writeFullBytes(buf, 0, buf.length);
                    }else{
                        throw "Can't send messages while not connected.";
                    }
                }catch(e:Dynamic){
                    this.error(e);
                }
            }
        #end
    }//function send()


    /**
    * Receive and fire events from children threads.
    * Add this method to ENTER_FRAME listener or run it periodicaly any other way (e.g. by timer)
    * This method does nothing for flash target.
    *
    * @param block - block until anything happen
    */
    public function processEvents (block:Bool = false) : Void {
        #if !flash
            var msg : Dynamic;
            var fn:Void->Void;

            while( true ){
                msg = Thread.readMessage(block);
                //got message
                if( msg != null ){
                    try{
                        fn = msg;
                        fn();
                    }catch(e:Dynamic){
                        this.error(e);
                    }
                //no more messages
                }else{
                    break;
                }
            }//while()
        #end
    }//function processEvents()


/**
*   Events
*/

    /**
    * Successful connection event
    *
    */
    public dynamic function onConnect() : Void {
        trace("Connect");
    }//function onConnect()


    /**
    * Process disconnect
    *
    */
    public dynamic function onDisconnect() : Void {
        trace("Disconnect");
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
    * Pack message to send. By default it returns Std.string(msg)
    *
    */
    public dynamic function pack (msg:Message) : Bytes {
        throw "SxClient.pack() is not implemented.";
        return null;
    }//function pack()


    /**
    * Handle client messages
    *
    */
    public dynamic function onMessage(msg:Message) : Void {
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


/**
* PLATFROM SPECIFIC CODE
*/
#if flash

    /**
    * Handle connection event
    *
    */
    private function _onConnect(e:Event) : Void {
        this.online = true;
        this.onConnect();
    }//function _onConnect()


    /**
    * Handle disconnection event
    *
    */
    private function _onClose(e:Event) : Void {
        this._sock.removeEventListener(Event.CLOSE, this._onClose);
        this._sock.removeEventListener(Event.CONNECT, this._onConnect);
        this._sock.removeEventListener(IOErrorEvent.IO_ERROR, this._onError);
        this._sock.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, this._onError);
        this._sock.removeEventListener(ProgressEvent.SOCKET_DATA, this._onData);
        this.online = false;
        this.onDisconnect();
    }//function _onClose()


    /**
    * Handle errors
    *
    */
    private function _onError(e:Event) : Void {
        this.error(e, false);
    }//function _onError()


    /**
    * Method description
    *
    */
    private function _onData(e:ProgressEvent) : Void {
        //free space in buffer
        var space : Int = this._buf.length - this._dataLength;
        var bytesAvailable : Int = this._sock.bytesAvailable;

        //if we don't have enough free space, allocate more
        while( bytesAvailable > space ){
            //check maximum buffer size
            if( this._buf.length * 2 > this.maxBufLength ){
                this.error("Maximum buffer size reached.", false);
                return;
            }

            //allocate
            var buf : Bytes = Bytes.alloc(this._buf.length * 2);
            buf.blit(0, this._buf, 0, this._dataLength);
            this._buf = buf;

            space = buf.length - this._dataLength;
        }//while()

        //read from socket
        try{
            var byteArray : ByteArray = new ByteArray();
            this._sock.readBytes(byteArray, 0, bytesAvailable);
            this._buf.blit(this._dataLength, Bytes.ofData(byteArray), 0, bytesAvailable);
        }catch(e:Dynamic){
            this.error(e);
            return;
        }

        //extract and process messages {
            var pos    : Int = 0;
            var length : Int = this._dataLength + bytesAvailable;
            var msgExt : MsgExtract<Message>;

            while( length >= 0 ){
                msgExt = this.extract(this._buf, pos, length);

                //no new messages
                if( msgExt == null ){
                    break;

                //got message! work...
                }else{
                    pos    += msgExt.length;
                    length -= msgExt.length;

                    try{
                        this.onMessage(msgExt.msg);
                    }catch(e:Dynamic){
                        this.error(e);
                    }
                }
            }//while()

            //move remaining bytes to the beginning of buffer
            if( pos > 0 ){
                this._buf.blit(0, this._buf, pos, length);
            }
            this._dataLength = length;
        //}
    }//function _onData()


#else

    /**
    * Disconnect, shutdown threads
    *
    */
    private function _disconnect () : Void {
        if( this.online ){
            try{
                this._sock.close();
                this.online = false;
                this._fire(this.onDisconnect);
                //send empty callback to drop send thread blocking
                if( this._send != Thread.current() ){
                    this._send.sendMessage(function():Void{});
                }
                // this._send = null;
            }catch(e:Dynamic){
                this.error(e);
            }
        }
    }//function _disconnect()


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
    * Thread for connection/sending data.
    * Also starts thread for reading after successful connection
    *
    */
    private function _threadSend () : Void {
        //connect{
            try{
                this._sock.connect(new Host(this.host), this.port);
            }catch(e:Dynamic){
                this.error(e);
                try{
                    this._sock.close();
                }catch(e:Dynamic){
                }
                return;
            }

            this.online = true;
            this._fire(this.onConnect);
        //}

        //run reading thread
        if( this._read == null ) this._read = Thread.create( this._runThread.bind(this._threadRead) );

        //now wait for messages
        while(this.online){
            var fn : Void->Void = Thread.readMessage(true);

            try{
                fn();
            }catch(e:Dynamic){
                this.error(e);
            }
        }
    }//function _threadSend()


    /**
    * Thread to read from socket
    *
    */
    private function _threadRead () : Void {
        var sockArray : Array<Socket> = [this._sock];

        while(this.online){
            try{
                var result = Socket.select(sockArray, null, null);
                for(s in result.read){
                    this._processData();
                }
            }catch(e:Dynamic){
                if( !Std.is(e, Eof) ){
                    this.error(e);
                }
                this.close();
            }
        }//while()

        this._read = null;
    }//function _threadRead()


    /**
    * Read messages from server
    *
    */
    private function _processData() : Void {
        //free space in buffer
        var space : Int = this._buf.length - this._dataLength;

        //no free space, increase buffer
        if( space == 0 ){
            //if maximum buffer size is reached, disconnect
            if( this._buf.length * 2 > this.maxBufLength ){
                throw "Maximum buffer size reached";
            }
            //create larger buffer
            var buf : Bytes = Bytes.alloc(this._buf.length * 2);
            buf.blit(0, this._buf, 0, this._dataLength);
            this._buf = buf;
            space = buf.length - this._dataLength;
        }

        //read from socket
        var bytesRead : Int = this._sock.input.readBytes(this._buf, this._dataLength, space);

        //extract and process messages {
            var pos    : Int = 0;
            var length : Int = this._dataLength + bytesRead;
            var msgExt : MsgExtract<Message>;

            while( length >= 0 ){
                msgExt = this.extract(this._buf, pos, length);

                //no new messages
                if( msgExt == null ){
                    break;

                //got message! work...
                }else{
                    pos    += msgExt.length;
                    length -= msgExt.length;

                    this._fire( this.onMessage.bind(msgExt.msg) );
                }
            }//while()

            //move remaining bytes to the beginning of buffer
            if( pos > 0 ){
                this._buf.blit(0, this._buf, pos, length);
            }
            this._dataLength = length;
        //}
    }//function _processData()


    /**
    * Send callback to main thread
    *
    */
    private inline function _fire (fn:Void->Void) : Void {
        this._main.sendMessage(fn);
    }//function _fire()

#end


}//class SxClient