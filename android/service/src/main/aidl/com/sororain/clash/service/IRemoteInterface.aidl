// IRemoteInterface.aidl
package com.sororain.clash.service;

import com.sororain.clash.service.ICallbackInterface;
import com.sororain.clash.service.IEventInterface;
import com.sororain.clash.service.IResultInterface;
import com.sororain.clash.service.IVoidInterface;
import com.sororain.clash.service.models.VpnOptions;
import com.sororain.clash.service.models.NotificationParams;

interface IRemoteInterface {
    void invokeAction(in String data, in ICallbackInterface callback);
    void quickSetup(in String initParamsString, in String setupParamsString, in ICallbackInterface callback, in IVoidInterface onStarted);
    void updateNotificationParams(in NotificationParams params);
    void startService(in VpnOptions options, in long runTime, in IResultInterface result);
    void stopService(in IResultInterface result);
    void setEventListener(in IEventInterface event);
    long getRunTime();
}