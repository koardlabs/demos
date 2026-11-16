package com.koard.android.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.launch

private data class TutorialPage(val title: String, val description: String, val icon: ImageVector)

private val tutorialPages = listOf(
    TutorialPage("Prepare your phone", "Select your location and make sure the reader is ready. Review the amount with your customer before starting the payment.", Icons.Default.PhoneAndroid),
    TutorialPage("Accept a contactless card", "Ask the customer to hold their card flat against your phone's NFC antenna until the reader confirms the read. Antenna position varies by phone, usually near the upper back. Follow the reader's on-screen placement guide.", Icons.Default.Contactless),
    TutorialPage("Accept a digital wallet", "Ask the customer to unlock their wallet and hold their phone or watch near your phone's NFC antenna. Keep both devices still until the reader confirms the read.", Icons.Default.AccountBalanceWallet),
    TutorialPage("Let the customer enter their PIN", "When a PIN is requested, hand the phone to the customer and let them enter it privately in the reader's secure screen. Never ask them to share their PIN with you.", Icons.Default.Dialpad),
    TutorialPage("Wait for the payment result", "A completed card read is not a payment approval. Wait for the approved, declined, or error result before handing over goods. Open History for the receipt and any follow-up actions.", Icons.Default.ReceiptLong),
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TapToPayTutorial(onClose: () -> Unit) {
    val pager = rememberPagerState(pageCount = { tutorialPages.size })
    val scope = rememberCoroutineScope()
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            topBar = {
                TopAppBar(title = { Text("Tap to Pay guide") }, actions = {
                    TextButton(onClick = onClose, modifier = Modifier.testTag("tutorial.close")) { Text("Close") }
                })
            },
            bottomBar = {
                Surface {
                    Column(Modifier.navigationBarsPadding().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text("${pager.currentPage + 1} of ${tutorialPages.size}", style = MaterialTheme.typography.labelLarge,
                            modifier = Modifier.align(Alignment.CenterHorizontally).testTag("tutorial.page"))
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            OutlinedButton(onClick = { scope.launch { pager.animateScrollToPage(pager.currentPage - 1) } },
                                enabled = pager.currentPage > 0, modifier = Modifier.weight(1f).testTag("tutorial.back")) { Text("Back") }
                            Button(onClick = {
                                if (pager.currentPage == tutorialPages.lastIndex) onClose()
                                else scope.launch { pager.animateScrollToPage(pager.currentPage + 1) }
                            }, modifier = Modifier.weight(1f).testTag("tutorial.next")) {
                                Text(if (pager.currentPage == tutorialPages.lastIndex) "Done" else "Next")
                            }
                        }
                    }
                }
            },
        ) { padding ->
            HorizontalPager(state = pager, modifier = Modifier.fillMaxSize().padding(padding).testTag("tutorial.pager")) { page ->
                val content = tutorialPages[page]
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(28.dp),
                    verticalArrangement = Arrangement.spacedBy(24.dp)) {
                    Surface(shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.primaryContainer,
                        modifier = Modifier.fillMaxWidth().height(200.dp)) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(content.icon, contentDescription = content.title, tint = MaterialTheme.colorScheme.onPrimaryContainer,
                                modifier = Modifier.size(96.dp))
                        }
                    }
                    Text(content.title, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                    Text(content.description, style = MaterialTheme.typography.bodyLarge)
                    Text("Swipe to continue", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}
