package com.digitalstorm.ciadpi

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File

class ByeDpiVpnService : VpnService() {

    private val byeDpiProxy = ByeDpiProxy()
    private var proxyJob: Job? = null
    private var tunFd: ParcelFileDescriptor? = null
    private val mutex = Mutex()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    companion object {
        private const val TAG = "ByeDpiVpnService"
        private const val FOREGROUND_SERVICE_ID = 1
        private const val NOTIFICATION_CHANNEL_ID = "ByeDPIVpn"

        const val ACTION_START = "com.digitalstorm.ciadpi.START"
        const val ACTION_STOP = "com.digitalstorm.ciadpi.STOP"
        const val EXTRA_ARGS = "extra_args"
        const val EXTRA_PORT = "extra_port"

        const val STATUS_CONNECTED = "connected"
        const val STATUS_DISCONNECTED = "disconnected"
        const val STATUS_FAILED = "failed"

        var isRunning = false
            private set

        // Direct callback for status changes — set by MainActivity
        var statusListener: ((String) -> Unit)? = null
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onDestroy() {
        super.onDestroy()
        tunFd?.close()
        scope.cancel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground()

        return when (intent?.action) {
            ACTION_START -> {
                val args = intent.getStringArrayExtra(EXTRA_ARGS) ?: arrayOf()
                val port = intent.getIntExtra(EXTRA_PORT, 1080)
                scope.launch { start(args, port) }
                START_STICKY
            }
            ACTION_STOP -> {
                scope.launch { stop() }
                START_NOT_STICKY
            }
            else -> {
                Log.w(TAG, "Unknown action: ${intent?.action}")
                START_NOT_STICKY
            }
        }
    }

    override fun onRevoke() {
        Log.i(TAG, "VPN revoked")
        scope.launch { stop() }
    }

    override fun onBind(intent: Intent): IBinder? {
        return super.onBind(intent)
    }

    private suspend fun start(args: Array<String>, port: Int) {
        Log.i(TAG, "Starting VPN with port=$port, args=${args.joinToString(" ")}")

        if (isRunning) {
            Log.w(TAG, "VPN already connected")
            broadcastStatus(STATUS_CONNECTED)
            return
        }

        try {
            mutex.withLock {
                startProxy(args, port)
                // Small delay to let the proxy bind the port
                delay(300)
                startTun2Socks("127.0.0.1", port)
                isRunning = true
                broadcastStatus(STATUS_CONNECTED)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start VPN", e)
            broadcastStatus(STATUS_FAILED)
            stop()
        }
    }

    private suspend fun stop() {
        Log.i(TAG, "Stopping VPN")

        if (!isRunning) {
            Log.w(TAG, "VPN not connected")
            broadcastStatus(STATUS_DISCONNECTED)
            return
        }

        mutex.withLock {
            try {
                withContext(Dispatchers.IO) {
                    stopProxy()
                    stopTun2Socks()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to stop VPN", e)
            }
        }

        isRunning = false
        broadcastStatus(STATUS_DISCONNECTED)
        stopSelf()
    }

    private fun startProxy(args: Array<String>, port: Int) {
        Log.i(TAG, "Starting proxy")

        if (proxyJob != null) {
            throw IllegalStateException("Proxy already started")
        }

        // Build full args: "ciadpi -p PORT -x 1 [user_args...]"
        val fullArgs = arrayOf("ciadpi", "-p", port.toString(), "-x", "1") + args

        proxyJob = scope.launch(Dispatchers.IO) {
            val code = byeDpiProxy.startProxy(fullArgs)

            delay(500)

            if (code != 0) {
                Log.e(TAG, "Proxy stopped with code $code")
                withContext(Dispatchers.Main) {
                    broadcastStatus(STATUS_FAILED)
                    isRunning = false
                    stopTun2Socks()
                    stopSelf()
                }
            }
        }

        Log.i(TAG, "Proxy started")
    }

    private suspend fun stopProxy() {
        Log.i(TAG, "Stopping proxy")

        try {
            byeDpiProxy.stopProxy()
            proxyJob?.cancel()

            val completed = withTimeoutOrNull(2000) {
                proxyJob?.join()
                true
            }

            if (completed == null) {
                Log.w(TAG, "Proxy not finished in time, force closing...")
                byeDpiProxy.forceClose()
            }

            proxyJob = null
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop proxy", e)
        }

        Log.i(TAG, "Proxy stopped")
    }

    private fun startTun2Socks(ip: String, port: Int) {
        Log.i(TAG, "Starting tun2socks")

        if (tunFd != null) {
            throw IllegalStateException("VPN already started")
        }

        val tun2socksConfig = buildString {
            appendLine("tunnel:")
            appendLine("  mtu: 8500")
            appendLine("misc:")
            appendLine("  task-stack-size: 81920")
            appendLine("socks5:")
            appendLine("  address: $ip")
            appendLine("  port: $port")
            appendLine("  udp: udp")
        }

        val configFile = try {
            File.createTempFile("config", ".tmp", cacheDir).apply {
                writeText(tun2socksConfig)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create config file", e)
            throw e
        }

        val builder = Builder()
        builder.setSession("ByeDPI")
        builder.setConfigureIntent(
            PendingIntent.getActivity(
                this, 0,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE
            )
        )

        builder.addAddress("10.10.10.10", 32)
        builder.addRoute("0.0.0.0", 0)
        builder.addDnsServer("8.8.8.8")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        // Exclude our own app from VPN
        builder.addDisallowedApplication(applicationContext.packageName)

        val fd = builder.establish()
            ?: throw IllegalStateException("VPN connection failed")

        this.tunFd = fd

        TProxyService.TProxyStartService(configFile.absolutePath, fd.fd)

        Log.i(TAG, "Tun2Socks started. ip: $ip port: $port")
    }

    private fun stopTun2Socks() {
        Log.i(TAG, "Stopping tun2socks")

        if (tunFd == null) {
            Log.w(TAG, "VPN fd is null, skipping")
            return
        }

        try {
            TProxyService.TProxyStopService()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop TProxyService", e)
        }

        try {
            tunFd?.close()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to close tunFd", e)
        } finally {
            tunFd = null
        }

        Log.i(TAG, "Tun2socks stopped")
    }

    private fun broadcastStatus(status: String) {
        Log.d(TAG, "Broadcasting status: $status")
        statusListener?.invoke(status)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "ByeDPI VPN",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "DPI bypass VPN service"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun startForeground() {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )

        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
            .setContentTitle("ByeByeDPI")
            .setContentText("DPI bypass active")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                FOREGROUND_SERVICE_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(FOREGROUND_SERVICE_ID, notification)
        }
    }
}
