package com.mobileclaw.mobileclaw_app

import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestAllDeclaredRuntimePermissions()
    }

    private fun requestAllDeclaredRuntimePermissions() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return

        val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
        }

        val requestedPermissions = packageInfo.requestedPermissions ?: return
        val runtimePermissions = requestedPermissions.filter { permission ->
            val permissionInfo = try {
                packageManager.getPermissionInfo(permission, 0)
            } catch (_: PackageManager.NameNotFoundException) {
                null
            }

            permissionInfo != null &&
                (permissionInfo.protectionLevel and android.content.pm.PermissionInfo.PROTECTION_MASK_BASE) ==
                android.content.pm.PermissionInfo.PROTECTION_DANGEROUS
        }

        val missingPermissions = runtimePermissions.filter { permission ->
            ContextCompat.checkSelfPermission(this, permission) != PackageManager.PERMISSION_GRANTED
        }

        if (missingPermissions.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, missingPermissions.toTypedArray(), REQUEST_PERMISSIONS_CODE)
        }
    }

    companion object {
        private const val REQUEST_PERMISSIONS_CODE = 1001
    }
}
