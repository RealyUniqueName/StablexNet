package ru.stablex.net;

import haxe.io.Bytes;


/**
* Class for extracting messages by Server.extract()
*
*/
class MsgExtract <Message>{
    //extracted message
    public var msg : Message;
    //Amount of processed bytes from client socket buffer
    public var length : Int;


    /**
    * Constructor
    *
    */
    public function new (msg:Message, length:Int) : Void {
        this.msg    = msg;
        this.length = length;
    }//function new()


    /**
    * Treat data as string messages separated by delimiter. Creates messages without delimiter.
    * Use it for Server.extract method like this:
    *   serv.extract = callback(MsgExtract.extractString, "\n");
    *
    * @param delimiter - message separator. Can take any length string
    */
    static public function extractString(delimiter:String, buf:Bytes, pos:Int, length:Int) : MsgExtract<String> {
        var last : Int = pos + length - delimiter.length;
        var p    : Int = pos;
        var complete : Bool = false;

        while( p <= last && !complete ){
            #if !flash
                complete = (buf.readString(p, delimiter.length) == delimiter);
            #else
                var i : Int = 0;
                while( i < delimiter.length && i <= last && buf.get(p + i) == StringTools.fastCodeAt(delimiter, i) ){
                    i++;
                }
                complete = delimiter.length == i;
            #end
            p ++;
        }

        if( complete ){
            return new MsgExtract(StringTools.trim(buf.readString(pos, p - pos - 1)), p - pos + delimiter.length - 1);
        }else{
            return null;
        }
    }//function extractString()


    /**
    * Pack string messages.
    * Use it for Server.extract method like this:
    *   serv.pack = callback(MsgExtract.packString, "\n");
    * @param delimiter - message separator. E.g. zero-byte for flash XMLSocket
    */
    static public function packString(delimiter:String, msg:String) : Bytes {
        return Bytes.ofString(msg + delimiter);
    }//function packString()


}//class MsgExtract