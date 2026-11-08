// PureShell - an open-source Android SSH client
// Copyright (C) 2026 Janos-Raul
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. See the LICENSE file for details.

package eu.pureshell.app

import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.security.keystore.StrongBoxUnavailableException
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.interfaces.ECPublicKey
import java.security.spec.ECGenParameterSpec
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Android Keystore bridge for SSH keys and the app lock.
 *
 * Private key material never leaves the Keystore: there is no export method,
 * not even for debugging. Every key use needs the user (biometric strong or
 * device credential) with a validity timeout of 0, i.e. once per operation.
 *
 * Requires API 30+ (minSdk), where BIOMETRIC_STRONG | DEVICE_CREDENTIAL works
 * together with a CryptoObject.
 */
class KeystoreBridge(private val activity: FragmentActivity) {
    private val keyStore: KeyStore =
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private var activePrompt: BiometricPrompt? = null

    companion object {
        const val AUTHENTICATORS =
            BiometricManager.Authenticators.BIOMETRIC_STRONG or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
        private const val KEYSTORE_AUTH =
            KeyProperties.AUTH_BIOMETRIC_STRONG or KeyProperties.AUTH_DEVICE_CREDENTIAL
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "capabilities" -> result.success(capabilities())
                "generateKey" -> generateKey(call.argument<String>("alias")!!, result)
                "securityLevel" -> result.success(securityLevel(call.argument<String>("alias")!!))
                "publicKey" -> result.success(publicKey(call.argument<String>("alias")!!))
                "sign" -> sign(
                    call.argument<String>("alias")!!,
                    call.argument<ByteArray>("data")!!,
                    call.argument<String>("title") ?: "Use your key",
                    call.argument<String>("subtitle"),
                    result,
                )
                "deleteKey" -> {
                    keyStore.deleteEntry(call.argument<String>("alias")!!)
                    result.success(null)
                }
                "listKeys" -> result.success(keyStore.aliases().toList())
                "generateWrapKey" -> generateWrapKey(call.argument<String>("alias")!!, result)
                "wrap" -> wrap(
                    call.argument<String>("alias")!!,
                    call.argument<ByteArray>("data")!!,
                    result,
                )
                "unwrap" -> unwrap(
                    call.argument<String>("alias")!!,
                    call.argument<ByteArray>("iv")!!,
                    call.argument<ByteArray>("data")!!,
                    result,
                )
                "authenticate" -> authenticate(
                    call.argument<String>("title") ?: "Unlock PureShell",
                    call.argument<String>("subtitle"),
                    result,
                )
                "cancelPrompt" -> {
                    activePrompt?.cancelAuthentication()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: KeyPermanentlyInvalidatedException) {
            result.error("key_invalid", "The key was invalidated", null)
        } catch (e: Exception) {
            // Never put key material, data or exception details into logs.
            result.error("failed", e.javaClass.simpleName, null)
        }
    }

    // ---- state -----------------------------------------------------------

    private fun isDeviceSecure(): Boolean =
        (activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager)
            .isDeviceSecure

    private fun capabilities(): Map<String, Any> {
        val status = BiometricManager.from(activity).canAuthenticate(AUTHENTICATORS)
        return mapOf(
            "secureLockScreen" to isDeviceSecure(),
            "canAuthenticate" to (status == BiometricManager.BIOMETRIC_SUCCESS),
        )
    }

    // ---- EC signing keys -------------------------------------------------

    private fun ecSpec(alias: String, strongBox: Boolean): KeyGenParameterSpec {
        val b = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setUserAuthenticationRequired(true)
            // Timeout 0: every single use needs the user.
            .setUserAuthenticationParameters(0, KEYSTORE_AUTH)
            // Adding a fingerprint must not destroy the SSH key: being locked
            // out of every server after enrolling another finger outweighs the
            // small security gain of invalidation (the device credential still
            // protects the key, and the key is not usable without the user).
            .setInvalidatedByBiometricEnrollment(false)
        if (strongBox) b.setIsStrongBoxBacked(true)
        return b.build()
    }

    private fun generateKey(alias: String, result: MethodChannel.Result) {
        if (!isDeviceSecure()) {
            result.error("no_screen_lock", "A screen lock is required", null)
            return
        }
        if (keyStore.containsAlias(alias)) {
            result.error("exists", "Alias already exists", null)
            return
        }
        var strongBox = true
        val generator = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore",
        )
        try {
            generator.initialize(ecSpec(alias, true))
            generator.generateKeyPair()
        } catch (e: StrongBoxUnavailableException) {
            strongBox = false
            generator.initialize(ecSpec(alias, false))
            generator.generateKeyPair()
        }
        result.success(
            mapOf(
                "securityLevel" to levelOf(alias, strongBoxRequested = strongBox),
                "publicKey" to publicKey(alias),
            ),
        )
    }

    /** Uncompressed point 0x04 || X || Y of the public key. */
    private fun publicKey(alias: String): ByteArray {
        val pub = keyStore.getCertificate(alias).publicKey as ECPublicKey
        fun fixed(v: java.math.BigInteger): ByteArray {
            val raw = v.toByteArray().let { if (it.size > 1 && it[0] == 0.toByte()) it.copyOfRange(1, it.size) else it }
            return ByteArray(32 - raw.size) + raw
        }
        return byteArrayOf(0x04) + fixed(pub.w.affineX) + fixed(pub.w.affineY)
    }

    private fun securityLevel(alias: String): String = levelOf(alias, strongBoxRequested = false)

    /**
     * STRONGBOX / TEE / SOFTWARE as reported by the Keystore. On API 30 the
     * platform cannot tell StrongBox from TEE after the fact; a key that was
     * just created with StrongBox succeeding is reported as such.
     */
    private fun levelOf(alias: String, strongBoxRequested: Boolean): String {
        val key = keyStore.getKey(alias, null) as java.security.Key
        val info = KeyFactory.getInstance(key.algorithm, "AndroidKeyStore")
            .getKeySpec(key as PrivateKey, KeyInfo::class.java)
        if (Build.VERSION.SDK_INT >= 31) {
            return when (info.securityLevel) {
                KeyProperties.SECURITY_LEVEL_STRONGBOX -> "STRONGBOX"
                KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> "TEE"
                else -> "SOFTWARE"
            }
        }
        @Suppress("DEPRECATION")
        val hardware = info.isInsideSecureHardware
        return when {
            !hardware -> "SOFTWARE"
            strongBoxRequested -> "STRONGBOX"
            else -> "TEE"
        }
    }

    private fun sign(
        alias: String,
        data: ByteArray,
        title: String,
        subtitle: String?,
        result: MethodChannel.Result,
    ) {
        val key = keyStore.getKey(alias, null) as PrivateKey
        val signature = Signature.getInstance("SHA256withECDSA")
        signature.initSign(key)
        prompt(BiometricPrompt.CryptoObject(signature), title, subtitle, result) { r ->
            val s = r.cryptoObject!!.signature!!
            s.update(data)
            s.sign() // DER-encoded ECDSA signature
        }
    }

    // ---- AES wrap key (software-key fallback only) -----------------------

    private fun generateWrapKey(alias: String, result: MethodChannel.Result) {
        if (!isDeviceSecure()) {
            result.error("no_screen_lock", "A screen lock is required", null)
            return
        }
        val spec = KeyGenParameterSpec.Builder(
            alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
            .setUserAuthenticationParameters(0, KEYSTORE_AUTH)
            .setInvalidatedByBiometricEnrollment(false) // see ecSpec()
            .build()
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(spec)
        generator.generateKey()
        val key = keyStore.getKey(alias, null) as SecretKey
        val info = javax.crypto.SecretKeyFactory.getInstance(key.algorithm, "AndroidKeyStore")
            .getKeySpec(key, KeyInfo::class.java) as KeyInfo
        @Suppress("DEPRECATION")
        val level = if (Build.VERSION.SDK_INT >= 31) {
            if (info.securityLevel == KeyProperties.SECURITY_LEVEL_SOFTWARE) "SOFTWARE" else "TEE"
        } else if (info.isInsideSecureHardware) "TEE" else "SOFTWARE"
        result.success(mapOf("securityLevel" to level))
    }

    private fun wrap(alias: String, data: ByteArray, result: MethodChannel.Result) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, keyStore.getKey(alias, null) as SecretKey)
        prompt(BiometricPrompt.CryptoObject(cipher), "Protect your key", null, result) { r ->
            val c = r.cryptoObject!!.cipher!!
            mapOf("iv" to c.iv, "data" to c.doFinal(data))
        }
    }

    private fun unwrap(alias: String, iv: ByteArray, data: ByteArray, result: MethodChannel.Result) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            keyStore.getKey(alias, null) as SecretKey,
            GCMParameterSpec(128, iv),
        )
        prompt(BiometricPrompt.CryptoObject(cipher), "Use your key", null, result) { r ->
            r.cryptoObject!!.cipher!!.doFinal(data)
        }
    }

    // ---- app lock --------------------------------------------------------

    private fun authenticate(title: String, subtitle: String?, result: MethodChannel.Result) {
        prompt(null, title, subtitle, result) { true }
    }

    // ---- BiometricPrompt -------------------------------------------------

    private fun prompt(
        crypto: BiometricPrompt.CryptoObject?,
        title: String,
        subtitle: String?,
        result: MethodChannel.Result,
        onSuccess: (BiometricPrompt.AuthenticationResult) -> Any?,
    ) {
        if (activePrompt != null) {
            result.error("busy", "Another prompt is showing", null)
            return
        }
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult) {
                activePrompt = null
                try {
                    result.success(onSuccess(r))
                } catch (e: Exception) {
                    result.error("failed", e.javaClass.simpleName, null)
                }
            }

            override fun onAuthenticationError(code: Int, message: CharSequence) {
                activePrompt = null
                val kind = when (code) {
                    BiometricPrompt.ERROR_USER_CANCELED,
                    BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                    BiometricPrompt.ERROR_CANCELED -> "cancelled"
                    BiometricPrompt.ERROR_LOCKOUT,
                    BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> "lockout"
                    BiometricPrompt.ERROR_NO_BIOMETRICS,
                    BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL,
                    BiometricPrompt.ERROR_HW_NOT_PRESENT,
                    BiometricPrompt.ERROR_HW_UNAVAILABLE -> "unavailable"
                    else -> "failed"
                }
                result.error(kind, null, null)
            }
            // onAuthenticationFailed: a wrong finger; the prompt stays open.
        }
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .apply { if (subtitle != null) setSubtitle(subtitle) }
            .setAllowedAuthenticators(AUTHENTICATORS)
            .build()
        val p = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback)
        activePrompt = p
        if (crypto != null) p.authenticate(info, crypto) else p.authenticate(info)
    }
}
