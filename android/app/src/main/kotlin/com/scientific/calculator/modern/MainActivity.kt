package com.scientific.calculator.modern

import android.os.Build
import android.os.Bundle
import android.view.View
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A hardware keyboard or a D-pad takes the window out of touch mode.
        // Android 8+ then outlines the focused view, which here is the whole
        // Flutter surface: a coloured frame around the app. Flutter draws its
        // own focus, so the platform highlight is switched off.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            findViewById<View>(FlutterActivity.FLUTTER_VIEW_ID)?.defaultFocusHighlightEnabled = false
        }
    }
}
