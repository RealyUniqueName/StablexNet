package com.example;

/**
* Users' data
*/
typedef TClient = {
    name  : String,
    send  : String->Void,   //this is method to send messages to this client
    close : Void->Void      //this is method to disconnect client
}