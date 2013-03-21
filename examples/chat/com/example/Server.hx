package com.example;

import ru.stablex.net.MsgExtract;
import ru.stablex.net.SxServer;



/**
*   classname:  Server
*
* Simple chat server
*/

class Server extends SxServer<TClient,String>{
    //server instance
    static public var inst : Server;
    //connected users
    public var users : List<TClient>;


    /**
    * Entry point
    *
    */
    static public function main() : Void {
        //create server instance
        Server.inst = new Server();

        //methods to pack/extract data from messages
        Server.inst.pack    = callback(MsgExtract.packString, "\n");
        Server.inst.extract = callback(MsgExtract.extractString, "\n");

        Server.inst.users = new List();

        //go-go-go
        Server.inst.run("0.0.0.0", 20000);
    }//function main()


    /**
    * Process new connection
    *
    */
    override public function onConnect(sock:sys.net.Socket, send:String->Void, close:Void->Void) : TClient {
        trace("New connection");
        return {
            name : null,
            send : send, //this is method to send messages to this client
            close : close //this is method to disconnect client
        };
    }//function onConnect()


    /**
    * Handle user messages
    *
    */
    override public function onMessage(user:TClient, msg:String) : Void {
        //if this user still has no name, use this message as a name
        if( user.name == null ){
            user.name = msg;
            //add him to users list
            this.users.add(user);

            //announce new user
            this.broadcast("NEW USER: " + user.name);

        //otherwise just send his message to every user
        }else{
            this.broadcast(user.name + " said: " + msg);
        }
    }//function onMessage()


    /**
    * Handle disconnections
    *
    */
    override public function onDisconnect(user:TClient) : Void {
        trace("Disconnected: " + user.name);

        this.users.remove(user);

        if( user.name != null ){
            this.broadcast("USER DISCONNECTED: " + user.name);
        }
    }//function onDisconnect()


    /**
    * Send message to all users
    *
    */
    public function broadcast(msg:String) : Void {
        for(user in this.users){
            user.send(msg);
        }
    }//function broadcast()



}//class Server