package com.example;

import ru.stablex.net.MsgExtract;
import ru.stablex.net.SxServer;


typedef TClient = {
    send  : String->Void,
    close : Void->Void
}


/**
*   classname:  Policy
*
* Policy server for Flash clients
*/

class Policy extends SxServer<TClient,String>{
    //server instance
    static public var inst : Policy;


    /**
    * Entry point
    *
    */
    static public function main() : Void {
        var args : Array<String> = Sys.args();

        if( args.length < 2 ){
            Sys.println("Usage:");
            Sys.println("\t ./policy IP PORT");
            return;
        }

        //create server instance
        Policy.inst = new Policy();
        Policy.inst.maxClientThreads = 1;

        //methods to pack/extract data from messages
        Policy.inst.pack    = callback(MsgExtract.packString, "\x00");
        Policy.inst.extract = callback(MsgExtract.extractString, "\x00");

        //go-go-go
        Policy.inst.run(args[0], Std.parseInt(args[1]));
    }//function main()


    /**
    * Process new connection
    *
    */
    override public function onConnect(sock:sys.net.Socket, send:String->Void, close:Void->Void) : TClient {
        return {
            send : send, //this is method to send messages to this client
            close : close //this is method to disconnect client
        };
    }//function onConnect()


    /**
    * Handle user messages
    *
    */
    override public function onMessage(user:TClient, msg:String) : Void {
        //just send policy file and disconnect user
        user.send("<?xml version=\"1.0\"?>\n<!DOCTYPE cross-domain-policy SYSTEM \"/xml/dtds/cross-domain-policy.dtd\">\n<cross-domain-policy><allow-access-from domain=\"*\" to-ports=\"*\" /></cross-domain-policy>");
        user.close();
    }//function onMessage()


}//class Policy