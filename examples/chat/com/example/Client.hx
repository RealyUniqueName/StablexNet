package com.example;

import flash.display.Sprite;
import flash.events.Event;
import flash.events.KeyboardEvent;
import flash.Lib;
import flash.text.TextFieldAutoSize;
import flash.text.TextField;
import flash.text.TextFieldType;
import ru.stablex.net.SxClient;
import ru.stablex.net.MsgExtract;



/**
*   classname:  Client
*
* Simple chat client
*/

class Client extends Sprite {
    //user instance
    public var user : TClient;
    //chat messages
    public var chat : TextField;
    //input box
    public var input : TextField;


    /**
    * Entry point
    *
    */
    static public function main() : Void {
        Lib.current.addChild(new Client());
    }//function main()


    /**
    * Constructor
    *
    */
    static public function new() : Void {
        super();

        //create UI
        this.createUI();

        //create socket connection with string messages
        var client = new SxClient<String>();
        //client.extract      = callback(MsgExtract.extractString, "\n");
        client.extract      = MsgExtract.extractString.bind("\n");
        client.pack         = MsgExtract.packString.bind("\n");
        client.onMessage    = this.onMessage;
        client.onConnect    = this.onConnect;
        client.onDisconnect = this.onDisconnect;

        //user instance
        this.user = {
            name  : null,
            send  : client.send,
            close : client.close
        };

        //connect to server
        client.connect('localhost', 20000);
        this.showMsg('Trying to connect...');

        //This is not required for flash target, since flash already handles socket events.
        //Does nothing for flash{
            //For other targets we need to check for socket events
            Lib.current.addEventListener(Event.ENTER_FRAME, function(e:Event){
                //if socket has events, this method will fire them
                client.processEvents();
            });
        //}
    }//function new()


    /**
    * Disconnected
    *
    */
    public function onConnect() : Void {
        this.showMsg("CONNECTED");
    }//function onConnect()


    /**
    * Disconnected
    *
    */
    public function onDisconnect() : Void {
        this.showMsg("DISCONNECTED");
    }//function onDisconnect()


    /**
    * Handle messages from server
    *
    */
    public function onMessage(msg:String) : Void {
        this.showMsg(msg);
    }//function onMessage()


    /**
    * Creates ui
    *
    */
    public function createUI() : Void {
        //input box
        this.input = new TextField();
        this.input.border = true;
        this.input.width  = 800;
        this.input.height = 20;
        this.input.type = TextFieldType.INPUT;
        this.addChild(this.input);

        //chat messages
        this.chat = new TextField();
        this.chat.multiline = true;
        this.chat.autoSize  = TextFieldAutoSize.LEFT;
        this.chat.y = 30;
        this.addChild(this.chat);

        //send messages on ENTER key
        Lib.current.stage.addEventListener(KeyboardEvent.KEY_DOWN, function(e:KeyboardEvent){
            //if pressed ENTER
            if( e.keyCode == 13 ) {
                //send message
                this.user.send(this.input.text);
                this.input.text = "";
            }
        });
    }//function createUI()


    /**
    * Show message in chat
    *
    */
    public function showMsg(msg:String) : Void {
        this.chat.text = msg + "\n" + this.chat.text;
    }//function showMsg()



}//class Client