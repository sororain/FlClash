// IEventInterface.aidl
package com.sororain.clash.service;

import com.sororain.clash.service.IAckInterface;

interface IEventInterface {
    oneway void onEvent(in String id, in byte[] data,in boolean isSuccess, in IAckInterface ack);
}