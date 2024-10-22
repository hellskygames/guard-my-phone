package com.guardmyphone.guardphone

import android.app.PendingIntent
import android.content.Intent
import android.content.IntentFilter
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity(), NfcAdapter.ReaderCallback {
    private val CHANNEL = "com.guardmyphone.guardmyphone/nfc"
    private var nfcAdapter: NfcAdapter? = null
    private var lastTagId: String? = null
    private var isNFCEnabled = false
    private lateinit var methodChannel: MethodChannel
    private val handler = Handler(Looper.getMainLooper())
    private var nfcCheckRunnable: Runnable? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nfcAdapter = NfcAdapter.getDefaultAdapter(this)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "enableNFCForeground" -> {
                    enableNFCForeground(result)
                }
                "disableNFCForeground" -> { // Nuevo método para deshabilitar NFC
                    disableNFCForeground(result)
                }
                "startNFCDetection" -> {
                    startNFCDetection(result)
                }
                "stopNFCDetection" -> {
                    stopNFCDetection(result)
                }
                "checkNFCPresence" -> {
                    result.success(lastTagId != null)
                }
                "stopSecurityAfterAuth" -> { // Método que se llama tras la autenticación biométrica
                    stopSecurityAfterAuth(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun enableNFCForeground(result: MethodChannel.Result) {
        val adapter = nfcAdapter
        if (adapter != null) {
            try {
                val intent = Intent(this, javaClass).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                val pendingIntent = PendingIntent.getActivity(
                    this,
                    0,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                val intentFilters = arrayOf(IntentFilter(NfcAdapter.ACTION_TAG_DISCOVERED))

                adapter.enableForegroundDispatch(this, pendingIntent, intentFilters, null)
                isNFCEnabled = true
                result.success(true)
            } catch (e: Exception) {
                result.error("NFC_ERROR", e.message, null)
            }
        } else {
            result.error("NFC_NOT_SUPPORTED", "NFC no está soportado en este dispositivo", null)
        }
    }

    private fun disableNFCForeground(result: MethodChannel.Result) { // Método agregado
        val adapter = nfcAdapter
        if (adapter != null) {
            try {
                adapter.disableForegroundDispatch(this)
                isNFCEnabled = false
                result.success(true)
            } catch (e: Exception) {
                result.error("NFC_ERROR", e.message, null)
            }
        } else {
            result.error("NFC_NOT_SUPPORTED", "NFC no está soportado en este dispositivo", null)
        }
    }

    private fun startNFCDetection(result: MethodChannel.Result) {
        nfcAdapter?.let { adapter ->
            try {
                adapter.enableReaderMode(this, this,
                    NfcAdapter.FLAG_READER_NFC_A or
                            NfcAdapter.FLAG_READER_NFC_B or
                            NfcAdapter.FLAG_READER_NFC_F or
                            NfcAdapter.FLAG_READER_NFC_V,
                    null)

                // Iniciar comprobación periódica de NFC
                startNFCCheck()
                result.success(true)
            } catch (e: Exception) {
                result.error("NFC_ERROR", e.message, null)
            }
        } ?: result.error("NFC_NOT_SUPPORTED", "NFC no está soportado", null)
    }

    private fun stopNFCDetection(result: MethodChannel.Result) {
        try {
            nfcAdapter?.disableReaderMode(this)
            stopNFCCheck()
            lastTagId = null
            result.success(true)
        } catch (e: Exception) {
            result.error("NFC_ERROR", e.message, null)
        }
    }

    private fun startNFCCheck() {
        nfcCheckRunnable = Runnable {
            if (lastTagId == null) {
                handler.post {
                    methodChannel.invokeMethod("onNFCLost", null)
                }
            }
            handler.postDelayed(nfcCheckRunnable!!, 5000) // Comprobar cada 5 segundos
        }
        handler.postDelayed(nfcCheckRunnable!!, 5000)
    }

    private fun stopNFCCheck() {
        nfcCheckRunnable?.let { handler.removeCallbacks(it) }
        nfcCheckRunnable = null
    }

    private fun stopSecurityAfterAuth(result: MethodChannel.Result) {
        try {
            // Detener la detección de NFC y la comprobación periódica
            stopNFCDetection(result)
            stopNFCCheck()

            // Si la alarma estaba sonando, detenerla
            methodChannel.invokeMethod("stopAlarm", null)

            // Desactivar cualquier operación relacionada con la seguridad
            lastTagId = null
            result.success(true)
        } catch (e: Exception) {
            result.error("SECURITY_ERROR", "Error al desactivar la seguridad: ${e.message}", null)
        }
    }

    override fun onTagDiscovered(tag: Tag?) {
        tag?.let {
            val id = bytesToHexString(it.id)
            if (id != lastTagId) {
                lastTagId = id
                handler.post {
                    methodChannel.invokeMethod("onNFCDetected", id)
                }
            }
        }
    }

    private fun bytesToHexString(bytes: ByteArray): String {
        val sb = StringBuilder()
        for (b in bytes) {
            sb.append(String.format("%02x", b))
        }
        return sb.toString()
    }

    override fun onPause() {
        super.onPause()
        if (isNFCEnabled) {
            nfcAdapter?.disableForegroundDispatch(this)
        }
    }

    override fun onResume() {
        super.onResume()
        if (isNFCEnabled) {
            nfcAdapter?.let { adapter ->
                val intent = Intent(this, javaClass).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                val pendingIntent = PendingIntent.getActivity(
                    this,
                    0,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                val intentFilters = arrayOf(IntentFilter(NfcAdapter.ACTION_TAG_DISCOVERED))
                adapter.enableForegroundDispatch(this, pendingIntent, intentFilters, null)
            }
        }
    }
}
