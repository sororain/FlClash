package com.sororain.clash.service.models

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

@Parcelize
data class NotificationParams(
    val title: String = "Sororain",
    val stopText: String = "STOP",
    val onlyStatisticsProxy: Boolean = false,
) : Parcelable