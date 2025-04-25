// --- File: lib/services/clipboard_service.dart ---

import 'dart:async';
import 'package:flutter/services.dart';
import '../utils/constants.dart'; // Import constants

// Service to manage clipboard clearing for sensitive data
class ClipboardService {
   // Singleton pattern
   static final ClipboardService instance = ClipboardService._internal();
   ClipboardService._internal();

   Timer? _clipboardClearTimer;
   String? _lastCopiedSensitiveText; // Store reference to check if content changed

   // Copy text and schedule it to be cleared after a delay
   void copyAndClearAfterDelay(String textToCopy, {Duration delay = clipboardClearDelay}) {
      _clipboardClearTimer?.cancel(); // Cancel any previous timer
      _lastCopiedSensitiveText = textToCopy;
      Clipboard.setData(ClipboardData(text: textToCopy));
      print("Copied sensitive data to clipboard.");
      _clipboardClearTimer = Timer(delay, _clearClipboardIfNeeded);
      print("Scheduled clipboard clear in ${delay.inSeconds} seconds.");
   }

   // Clear clipboard only if the content matches the last sensitive text copied
   Future<void> _clearClipboardIfNeeded() async {
      print("Clipboard clear timer fired.");
      if (_lastCopiedSensitiveText == null) {
         print("No sensitive text reference found, skipping clear.");
         return;
      }
      try {
         // Check current clipboard content before clearing
         ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
         if (data != null && data.text == _lastCopiedSensitiveText) {
            await Clipboard.setData(const ClipboardData(text: '')); // Clear it
            print("Clipboard cleared successfully.");
         } else {
            print("Clipboard content changed or is null, skipping clear.");
         }
      } catch (e) {
         // Catch potential platform exceptions when accessing clipboard
         print("Error accessing or clearing clipboard: $e");
      } finally {
         // Reset state regardless of whether clear happened
         _lastCopiedSensitiveText = null;
         _clipboardClearTimer = null;
      }
   }

   // Manually cancel the clear timer if needed (e.g., app locks)
   void cancelClearTimer() {
      _clipboardClearTimer?.cancel();
      _clipboardClearTimer = null;
      _lastCopiedSensitiveText = null; // Also clear the reference
      print("Clipboard clear timer cancelled manually.");
   }
}