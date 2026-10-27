package com.digisanchika.app

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    // Ensure screenshots/screen recording are allowed (debug/dev builds).
    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
  }
}
