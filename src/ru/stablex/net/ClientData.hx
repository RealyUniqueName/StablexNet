package ru.stablex.net;


import haxe.io.Bytes;
import sys.net.Socket;
import ru.stablex.net.SxServer;


/**
* Per client sate object
*
*/
class ClientData<Client,Message> {
    //Is client connected?
    public var online : Bool = false;
    //client structure
    public var client : Client;
    //clients socket
    public var sock : Socket;
    //data buffer
    public var buf : Bytes;
    //buffer useful data length (starting from byte with 0 index)
    public var dataLength : Int = 0;
    /**
    * Server instance
    * @private
    */
    public var server : SxServer<Client,Message>;
#if (cpp || neko)
    /**
    * Thread handling this client
    * @private
    */
    public var thread : ThreadData<Client,Message>;
#end


    /**
    * Constructor
    *
    */
    public function new() : Void {
        this.buf = Bytes.alloc(1024);
    }//function new()


    /**
    * Send message to client
    *
    */
    public function send(msg:Message) : Void {
        if( this.server != null ){
            this.server.sendMessage(this.thread, this, msg);
        }
    }//function send()


    /**
    * Close connection
    *
    */
    public function close() : Void {
        if( this.server != null ){
            this.server.disconnect(this.thread, this);
        }
    }//function close()


}//class ClientData