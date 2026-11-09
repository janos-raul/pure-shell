// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

package eu.pureshell.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.Build
import android.os.IBinder

/**
 * Keeps the app process in the foreground state while SSH sessions are
 * connected. Without it Android blocks the network of a backgrounded app a few
 * seconds after it leaves the screen and destroys its open TCP connections.
 *
 * The sessions themselves live in the Flutter engine (Dart); this service only
 * holds the process. It is started by Dart with the number of connected
 * sessions and stopped when that is zero or the activity is destroyed (the
 * engine and with it the sessions are gone then).
 *
 * The notification shows the count and nothing else: no hostnames, usernames
 * or terminal content. It is hidden on a locked screen.
 */
class SessionService : Service() {
    companion object {
        const val CHANNEL_ID = "sessions"
        const val NOTIFICATION_ID = 1
        const val ACTION_UPDATE = "eu.pureshell.app.SESSIONS_UPDATE"
        const val ACTION_DISCONNECT_ALL = "eu.pureshell.app.SESSIONS_DISCONNECT_ALL"
        const val EXTRA_COUNT = "count"

        /** True while the service is in the foreground. */
        @Volatile
        var running = false
            private set

        /** Set by MainActivity: asks Dart to close every session. */
        @Volatile
        var onDisconnectAll: (() -> Unit)? = null
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_DISCONNECT_ALL -> {
                val disconnect = onDisconnectAll
                if (disconnect != null) {
                    disconnect() // Dart closes the sessions, then reports 0
                } else {
                    stop() // the engine is gone: nothing to disconnect
                }
            }
            else -> {
                val count = intent?.getIntExtra(EXTRA_COUNT, 0) ?: 0
                if (count <= 0) stop() else show(count)
            }
        }
        return START_NOT_STICKY
    }

    private fun stop() {
        running = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    private fun show(count: Int) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Sessions", NotificationManager.IMPORTANCE_LOW).apply {
                lockscreenVisibility = Notification.VISIBILITY_SECRET
                setShowBadge(false)
            }
        )
        val open = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName)?.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val disconnectAll = PendingIntent.getService(
            this,
            1,
            Intent(this, SessionService::class.java).setAction(ACTION_DISCONNECT_ALL),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_session)
            .setContentTitle("PureShell")
            .setContentText(if (count == 1) "1 active session" else "$count active sessions")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_SECRET)
            .setContentIntent(open)
            .addAction(
                Notification.Action.Builder(
                    Icon.createWithResource(this, R.drawable.ic_stat_session),
                    "Disconnect all",
                    disconnectAll,
                ).build()
            )
            .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        running = true
    }
}
