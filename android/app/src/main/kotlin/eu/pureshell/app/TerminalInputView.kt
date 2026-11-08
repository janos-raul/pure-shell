// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

package eu.pureshell.app

import android.content.Context
import android.content.pm.ApplicationInfo
import android.text.InputType
import android.util.Log
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputMethodManager
import io.flutter.embedding.android.FlutterView

/**
 * An invisible view that owns the soft keyboard while a terminal is shown
 * ("Direct" input, the way Termux does it).
 *
 * The input type is TYPE_NULL and the connection never keeps text: what the
 * keyboard commits or composes is reported to Dart as it happens, and the
 * editable stays empty, so the keyboard has no context to learn from or
 * predict with. Nothing is logged except, in debuggable builds, the name of
 * the path an input took.
 *
 * Input is only accepted between [attach] and [detach] (or until the view
 * loses focus, for example to a Flutter text field); everything arriving
 * outside that is dropped.
 */
class TerminalInputView(
    context: Context,
    private val emit: (Map<String, Any?>) -> Unit,
) : View(context) {
    private val imm =
        context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
    private val debuggable =
        (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    /** True while this view is meant to receive input. */
    var attached = false
        private set

    init {
        isFocusable = true
        isFocusableInTouchMode = true
        defaultFocusHighlightEnabled = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        importantForAutofill = IMPORTANT_FOR_AUTOFILL_NO
    }

    private fun path(name: String) {
        if (debuggable) Log.d("PureShellInput", "path=$name")
    }

    private fun flutterView(): FlutterView? = find(rootView)

    private fun find(view: View): FlutterView? {
        if (view is FlutterView) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                find(view.getChildAt(i))?.let { return it }
            }
        }
        return null
    }

    fun attach() {
        attached = true
        requestFocus()
        post { if (attached) imm.showSoftInput(this, 0) }
    }

    fun detach(hide: Boolean) {
        attached = false
        if (hasFocus()) {
            clearFocus()
            flutterView()?.requestFocus()
        }
        if (hide) imm.hideSoftInputFromWindow(windowToken, 0)
    }

    override fun onFocusChanged(gainFocus: Boolean, direction: Int, previous: android.graphics.Rect?) {
        super.onFocusChanged(gainFocus, direction, previous)
        if (!gainFocus && attached) {
            // Focus went elsewhere (a Flutter text field, a dialog): stop
            // accepting; Dart attaches again when the terminal is back.
            attached = false
            emit(mapOf("type" to "blur"))
        }
    }

    override fun onCheckIsTextEditor(): Boolean = true

    override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection {
        // NULL: the most correct type for a terminal (Termux does the same).
        outAttrs.inputType = InputType.TYPE_NULL
        outAttrs.imeOptions = EditorInfo.IME_FLAG_NO_FULLSCREEN or
            EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
        outAttrs.initialSelStart = 0
        outAttrs.initialSelEnd = 0
        return Connection(this)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (!attached) return true // dropped
        val chars = typedCharacters(event)
        if (chars != null) {
            if (event.action != KeyEvent.ACTION_UP) {
                path("key-event")
                emit(mapOf("type" to "key-text", "text" to chars))
            }
            return true
        }
        // Everything else (Enter, Backspace, arrows, Ctrl+letter, ...) goes
        // to Flutter's key handling, where the terminal maps it.
        path("key-event-forwarded")
        // FlutterView feeds its keyboard pipeline only through
        // dispatchKeyEvent (it has no onKeyDown/onKeyUp).
        return flutterView()?.dispatchKeyEvent(event) ?: false
    }

    /** The characters a key press types, or null if it is not plain text. */
    private fun typedCharacters(event: KeyEvent): String? {
        if (event.action == KeyEvent.ACTION_MULTIPLE &&
            event.keyCode == KeyEvent.KEYCODE_UNKNOWN
        ) {
            return event.characters?.takeIf { it.isNotEmpty() }
        }
        if (event.isCtrlPressed || event.isAltPressed || event.isMetaPressed) return null
        val u = event.unicodeChar
        if (u and android.view.KeyCharacterMap.COMBINING_ACCENT != 0) return null
        if (u < 0x20 || u == 0x7f) return null // Enter, Tab, Backspace, ...
        return String(Character.toChars(u))
    }

    private inner class Connection(target: View) : BaseInputConnection(target, true) {
        // The editable is never edited, so it stays empty and the keyboard
        // has no text around the cursor to look at.

        override fun commitText(text: CharSequence?, newCursorPosition: Int): Boolean {
            if (attached) {
                path("text-commit")
                emit(mapOf("type" to "commit", "text" to (text?.toString() ?: "")))
            }
            return true
        }

        override fun setComposingText(text: CharSequence?, newCursorPosition: Int): Boolean {
            if (attached) {
                path("text-composing")
                emit(mapOf("type" to "composing", "text" to (text?.toString() ?: "")))
            }
            return true
        }

        override fun finishComposingText(): Boolean {
            if (attached) emit(mapOf("type" to "finish"))
            return true
        }

        override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean {
            if (attached && beforeLength > 0) {
                path("text-delete")
                emit(mapOf("type" to "delete", "before" to beforeLength))
            }
            return true
        }

        override fun deleteSurroundingTextInCodePoints(before: Int, after: Int): Boolean =
            deleteSurroundingText(before, after)

        override fun performEditorAction(actionCode: Int): Boolean {
            if (attached) {
                path("editor-action")
                emit(mapOf("type" to "enter"))
            }
            return true
        }
    }
}
