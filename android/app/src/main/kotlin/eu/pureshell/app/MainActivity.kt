// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

package eu.pureshell.app

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.PersistableBundle
import android.os.Bundle
import android.view.WindowManager
import android.widget.FrameLayout
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity: BiometricPrompt needs a FragmentActivity.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Block screenshots, screen recording and the recent-apps preview.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        super.onCreate(savedInstanceState)
    }

    private var inputView: TerminalInputView? = null
    private var pendingNotificationResult: MethodChannel.Result? = null
    private val notificationRequestCode = 4711

    private fun notificationsAllowed(): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == notificationRequestCode) {
            pendingNotificationResult?.success(notificationsAllowed())
            pendingNotificationResult = null
        }
    }

    override fun onDestroy() {
        // The Flutter engine, and with it every session, goes with the
        // activity: nothing left for the service to keep alive.
        SessionService.onDisconnectAll = null
        stopService(Intent(this, SessionService::class.java))
        super.onDestroy()
    }

    private fun inputView(channel: MethodChannel): TerminalInputView =
        inputView ?: TerminalInputView(this) { event ->
            channel.invokeMethod("event", event)
        }.also {
            addContentView(it, FrameLayout.LayoutParams(1, 1))
            inputView = it
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val keystore = KeystoreBridge(this)
        MethodChannel(messenger, "eu.pureshell.app/keystore")
            .setMethodCallHandler { call, result -> keystore.handle(call, result) }

        // Lets the user allow screenshots (off by default; the window is
        // secure from onCreate until Dart says otherwise).
        MethodChannel(messenger, "eu.pureshell.app/window")
            .setMethodCallHandler { call, result ->
                if (call.method == "setSecure") {
                    val secure = call.argument<Boolean>("secure") ?: true
                    if (secure) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        // "Direct" terminal input: an invisible native view owns the soft
        // keyboard while a terminal is shown and reports what is typed.
        val inputChannel = MethodChannel(messenger, "eu.pureshell.app/terminal_input")
        inputChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "attach" -> {
                    inputView(inputChannel).attach()
                    result.success(null)
                }
                "detach" -> {
                    inputView?.detach(call.argument<Boolean>("hide") ?: true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Keep-alive foreground service: Dart reports how many sessions are
        // connected; the notification shows that number and nothing else.
        val sessionsChannel = MethodChannel(messenger, "eu.pureshell.app/sessions")
        SessionService.onDisconnectAll = {
            runOnUiThread { sessionsChannel.invokeMethod("disconnectAll", null) }
        }
        sessionsChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val count = call.argument<Int>("count") ?: 0
                    val intent = Intent(this, SessionService::class.java)
                        .setAction(SessionService.ACTION_UPDATE)
                        .putExtra(SessionService.EXTRA_COUNT, count)
                    try {
                        if (count <= 0) {
                            stopService(Intent(this, SessionService::class.java))
                        } else if (SessionService.running) {
                            startService(intent)
                        } else {
                            startForegroundService(intent)
                        }
                    } catch (e: Exception) {
                        // Not allowed to start a foreground service right now
                        // (app in the background): the sessions just are not
                        // kept alive. Nothing to log.
                    }
                    result.success(null)
                }
                "notificationsAllowed" -> result.success(notificationsAllowed())
                "requestNotifications" -> {
                    if (notificationsAllowed()) {
                        result.success(true)
                    } else {
                        pendingNotificationResult?.success(false)
                        pendingNotificationResult = result
                        requestPermissions(
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            notificationRequestCode,
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Copy from the terminal: on Android 13+ the clip is marked sensitive,
        // so the system's clipboard preview does not show it. Nothing is logged.
        MethodChannel(messenger, "eu.pureshell.app/clipboard")
            .setMethodCallHandler { call, result ->
                if (call.method == "copy") {
                    val text = call.argument<String>("text") ?: ""
                    val clip = ClipData.newPlainText("", text)
                    if (Build.VERSION.SDK_INT >= 33) {
                        clip.description.extras = PersistableBundle().apply {
                            putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
                        }
                    }
                    (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
                        .setPrimaryClip(clip)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        // Share a piece of text (the public key) through the system share
        // sheet. Public data only.
        MethodChannel(messenger, "eu.pureshell.app/share")
            .setMethodCallHandler { call, result ->
                if (call.method == "shareText") {
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, call.argument<String>("text"))
                    }
                    startActivity(Intent.createChooser(send, null))
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }
}
