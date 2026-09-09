package com.sororain.clash

import android.app.Application
import android.content.Context
import com.sororain.clash.common.GlobalState

class Application : Application() {

    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        GlobalState.init(this)
    }
}
