package com.digitalstorm.ciadpi

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL = "com.digitalstorm.ciadpi/proxy"
        private const val VPN_REQUEST_CODE = 1001
    }

    private var methodChannel: MethodChannel? = null
    private var pendingArgs: Array<String>? = null
    private var pendingPort: Int = 1080
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "startVpn" -> {
                    val args = call.argument<List<String>>("args") ?: listOf()
                    val port = call.argument<Int>("port") ?: 1080
                    startVpn(args.toTypedArray(), port, result)
                }
                "stopVpn" -> {
                    stopVpn()
                    result.success(true)
                }
                "getStatus" -> {
                    result.success(if (ByeDpiVpnService.isRunning) "connected" else "disconnected")
                }
                else -> result.notImplemented()
            }
        }

        // Register a direct status listener on the VPN service —
        // this replaces the unreliable BroadcastReceiver approach
        ByeDpiVpnService.statusListener = { status ->
            mainHandler.post {
                Log.d(TAG, "Status callback received: $status")
                methodChannel?.invokeMethod("onStatusChanged", status)
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        ByeDpiVpnService.statusListener = null
    }

    private fun startVpn(args: Array<String>, port: Int, result: MethodChannel.Result) {
        val vpnIntent = VpnService.prepare(this)
        if (vpnIntent != null) {
            // Need to request VPN permission
            pendingArgs = args
            pendingPort = port
            startActivityForResult(vpnIntent, VPN_REQUEST_CODE)
            result.success(true) // Permission dialog shown
        } else {
            // Permission already granted
            launchVpnService(args, port)
            result.success(true)
        }
    }

    private fun stopVpn() {
        val intent = Intent(this, ByeDpiVpnService::class.java)
        intent.action = ByeDpiVpnService.ACTION_STOP
        startService(intent)
    }

    private fun launchVpnService(args: Array<String>, port: Int) {
        val intent = Intent(this, ByeDpiVpnService::class.java).apply {
            action = ByeDpiVpnService.ACTION_START
            putExtra(ByeDpiVpnService.EXTRA_ARGS, args)
            putExtra(ByeDpiVpnService.EXTRA_PORT, port)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                val args = pendingArgs ?: arrayOf()
                val port = pendingPort
                pendingArgs = null
                launchVpnService(args, port)
            } else {
                Log.w(TAG, "VPN permission denied")
                methodChannel?.invokeMethod("onStatusChanged", "failed")
            }
        }
    }
}
