package com.koard.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.first
import androidx.compose.ui.Modifier
import androidx.lifecycle.lifecycleScope
import com.koard.android.navigation.KoardNavigation
import com.koard.android.ui.theme.KoardAndroidSDKTheme
import kotlinx.coroutines.launch
import timber.log.Timber

class MainActivity : ComponentActivity() {
    @Volatile private var isResumed = false
    private var registrationJob: Job? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = applicationContext as DemoApplication
        setContent {
            val sdkReady by app.sdkReady.collectAsState()
            val error by app.initializationError.collectAsState()
            val darkAppearance by app.darkAppearance.collectAsState()
            KoardAndroidSDKTheme(darkTheme = darkAppearance ?: isSystemInDarkTheme()) {
                Surface {
                    if (sdkReady) KoardNavigation(modifier = Modifier)
                    else Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center,
                        horizontalAlignment = Alignment.CenterHorizontally) {
                        if (error == null) CircularProgressIndicator()
                        Text(error ?: "Preparing register…")
                    }
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        isResumed = true
        refreshNfcRegistration()
    }

    override fun onPause() {
        isResumed = false
        registrationJob?.cancel()
        lifecycleScope.launch {
            (application as DemoApplication).withInitializedSdk { sdk ->
                Timber.v("Unregistering activity for NFC")
                sdk.unregisterActivityForNfc(this@MainActivity)
            }
        }
        super.onPause()
    }

    /** Attach the resumed Activity once the SDK is ready, and again after Settings replaces the SDK. */
    fun refreshNfcRegistration() {
        registrationJob?.cancel()
        registrationJob = lifecycleScope.launch {
            val app = application as DemoApplication
            app.sdkReady.first { it }
            app.withInitializedSdk { sdk ->
                if (isResumed) {
                    Timber.v("Registering activity for NFC")
                    sdk.registerActivityForNfc(this@MainActivity)
                }
            }
        }
    }
}
