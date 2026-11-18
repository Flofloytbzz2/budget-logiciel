package com.objectifprix.app

import android.Manifest
import android.app.Application
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

class App : Application() {
    override fun onCreate() {
        super.onCreate()
        Store.init(this)
        Settings.load(this)
        L.load(this)
        L.code = L.resolve(Settings.language)
        SavingRules.init()
        SyncService.init()
        Notifier.createChannels(this)
        RefreshWorker.schedule(this)
    }

    companion object {
        var requestNotifications: (() -> Unit)? = null

        fun askNotifications() {
            requestNotifications?.invoke()
        }
    }
}

class MainActivity : ComponentActivity() {
    private val permission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        App.requestNotifications = {
            if (Build.VERSION.SDK_INT >= 33 && !Notifier.hasPermission(this)) {
                permission.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
        setContent {
            AppTheme {
                Root()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        Store.scope.launch {
            SyncService.syncNow()
            SavingRules.applyAuto()
            Reminders.check()
            if (Settings.refreshHours > 0) Store.refreshDue()
            SyncService.syncNow()
        }
    }
}

@Composable
fun Root() {
    val showTutorial = !Settings.onboarded || Settings.tutorialShown
    val inDetail = Nav.detail != null
    val inEdit = Nav.editing

    BackHandler(enabled = inEdit || inDetail) {
        if (inEdit) Nav.editing = false else Nav.detail = null
    }

    Box(Modifier.fillMaxSize().background(Th.bg)) {
        Column(Modifier.fillMaxSize().systemBarsPadding().imePadding()) {
            Box(Modifier.weight(1f).fillMaxWidth()) {
                when {
                    inEdit -> EditScreen(Nav.editId)
                    inDetail -> DetailScreen(Nav.detail ?: "")
                    Nav.tab == 0 -> GoalsTab()
                    Nav.tab == 1 -> AccountScreen()
                    else -> SettingsScreen()
                }
            }
            if (!inEdit && !inDetail) BottomBar()
        }
        if (showTutorial) {
            Box(Modifier.fillMaxSize().systemBarsPadding()) { Tutorial() }
        }
    }
}

@Composable
fun BottomBar() {
    Column(Modifier.fillMaxWidth().background(Th.panel)) {
        Divider()
        Row(Modifier.fillMaxWidth().height(56.dp)) {
            val tabs = listOf("tab.goals", "tab.account", "tab.settings")
            for ((i, key) in tabs.withIndex()) {
                val selected = Nav.tab == i
                Box(
                    Modifier.weight(1f).fillMaxSize().clickable { Nav.tab = i },
                    contentAlignment = Alignment.Center
                ) {
                    Txt(L.t(key), size = 14, weight = if (selected) FontWeight.Bold else FontWeight.Medium,
                        color = if (selected) Th.accent else Th.muted)
                }
            }
        }
    }
}
