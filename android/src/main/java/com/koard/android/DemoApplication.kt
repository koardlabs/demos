package com.koard.android

import android.app.Application
import com.koardlabs.merchant.sdk.KoardMerchantSdk
import com.koardlabs.merchant.sdk.domain.KoardEnvironment
import com.koardlabs.merchant.sdk.domain.KoardLogLevel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import timber.log.Timber

class DemoApplication : Application() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val sdkMutex = Mutex()
    private val _ready = MutableStateFlow(false)
    val sdkReady = _ready.asStateFlow()
    private val _error = MutableStateFlow<String?>(null)
    val initializationError = _error.asStateFlow()
    private val _darkAppearance = MutableStateFlow<Boolean?>(null)
    val darkAppearance = _darkAppearance.asStateFlow()

    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.DEBUG) Timber.plant(Timber.DebugTree())
        val preferences = getSharedPreferences("demo.appearance", MODE_PRIVATE)
        if (preferences.contains("dark")) _darkAppearance.value = preferences.getBoolean("dark", false)
        scope.launch {
            try {
                initializeSdk()
            } catch (error: Exception) {
                Timber.e(error, "SDK initialization failed")
                _error.value = "The register couldn't start. Check the demo configuration and reopen the app."
            }
        }
    }

    suspend fun initializeSdk() = withContext(Dispatchers.IO) {
        sdkMutex.withLock {
            if (!KoardMerchantSdk.isInitialized()) initializeSdkInstance()
            _ready.value = true
        }
    }

    /** Explicit reader/session teardown. Ordinary logout preserves enrollment. */
    suspend fun resetSdk() = withContext(Dispatchers.IO) {
        sdkMutex.withLock {
            if (KoardMerchantSdk.isInitialized()) {
                val sdk = KoardMerchantSdk.getInstance()
                check(!sdk.hasActiveTapTransaction()) {
                    "Finish or cancel the current transaction before resetting the SDK."
                }
                sdk.deinit()
            }
            initializeSdkInstance()
        }
    }

    // Serialize Activity NFC callbacks with deinit/reinitialization so a callback
    // cannot use the singleton while it is being replaced.
    suspend fun withInitializedSdk(action: suspend (KoardMerchantSdk) -> Unit) =
        withContext(Dispatchers.IO) {
            sdkMutex.withLock {
                if (KoardMerchantSdk.isInitialized()) action(KoardMerchantSdk.getInstance())
            }
        }

    private fun initializeSdkInstance() {
        val environment = when (BuildConfig.ENVIRONMENT) {
            "PROD" -> KoardEnvironment.PROD
            else -> KoardEnvironment.UAT
        }
        KoardMerchantSdk.initialize(
            application = this,
            apiKey = BuildConfig.API_KEY,
            environment = environment,
            timeoutSeconds = 30L,
            logLevel = KoardLogLevel.NONE
        )
    }

    fun setDarkAppearance(value: Boolean?) {
        _darkAppearance.value = value
        getSharedPreferences("demo.appearance", MODE_PRIVATE).edit().apply {
            if (value == null) remove("dark") else putBoolean("dark", value)
        }.apply()
    }
}
