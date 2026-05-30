package com.digitalstorm.ciadpi

class ByeDpiProxy {
    companion object {
        init {
            System.loadLibrary("byedpi")
        }
    }

    fun startProxy(args: Array<String>): Int {
        return jniStartProxy(args)
    }

    fun stopProxy(): Int {
        return jniStopProxy()
    }

    fun forceClose(): Int {
        return jniForceClose()
    }

    private external fun jniStartProxy(args: Array<String>): Int
    private external fun jniStopProxy(): Int
    external fun jniForceClose(): Int
}
