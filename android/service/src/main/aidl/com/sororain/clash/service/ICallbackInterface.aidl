// ICallbackInterface.aidl
package com.sororain.clash.service;

import com.sororain.clash.service.IAckInterface;

interface ICallbackInterface {
    oneway void onResult(in byte[] data,in boolean isSuccess, in IAckInterface ack);
}