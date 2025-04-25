// --- MODIFIED: HomePage (Adds Search/Filter, Edit Button in Dialog) ---
import 'package:flutter/material.dart'; // Already listed
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // Already listed
import 'dart:convert'; // Already listed
import 'package:encrypt/encrypt.dart' as encrypt; // Already listed
import 'package:flutter/services.dart'; // Already listed

import '../models/password_entry.dart'; // New relative import
import '../services/encryption_key_service.dart'; // New relative import
import '../services/inactivity_service.dart'; // New relative import
import '../services/clipboard_service.dart'; // New relative import
import '../utils/constants.dart'; // Already listed
import '../utils/helpers.dart'; // Already listed
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

// Enum for Sort Order
enum SortOrder { nameAZ, dateAdded }

class _HomePageState extends State<HomePage> {
  final _storage = const FlutterSecureStorage();
  List<PasswordEntry> _displayEntries = []; // Holds entries with cleared passwords for display
  Map<String, String> _encryptedDataMap = {}; // Holds original encrypted data
  List<PasswordEntry> _filteredDisplayEntries = []; // Holds filtered display entries
  bool _isLoading = true;
  SortOrder _currentSortOrder = SortOrder.nameAZ;

  // --- NEW: Search State ---
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  // ---

  @override
  void initState() {
    super.initState();
    _loadPasswordEntries();
    // --- NEW: Add listener for search controller ---
    _searchController.addListener(_onSearchChanged);
    // ---
  }

  @override
  void dispose() {
    // --- NEW: Dispose search controller ---
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    // ---
    super.dispose();
  }

  // --- NEW: Handle search query changes ---
  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
      _filterEntries(); // Re-filter the list when search query changes
    });
  }
  // ---

  // --- NEW: Filter logic ---
  void _filterEntries() {
    if (_searchQuery.isEmpty) {
      // If search is empty, show all display entries (already sorted)
      _filteredDisplayEntries = List.from(_displayEntries);
    } else {
      final query = _searchQuery.toLowerCase();
      // Filter the display entries based on service or username containing the query
      _filteredDisplayEntries = _displayEntries.where((entry) {
        final serviceMatch = entry.service.toLowerCase().contains(query);
        final usernameMatch = entry.username.toLowerCase().contains(query);
        return serviceMatch || usernameMatch;
      }).toList();
    }
    // No need to call setState here as it's called by _onSearchChanged or after load/sort
  }
  //---

  // Method to sort display entries
  void _sortEntries() {
     if (_currentSortOrder == SortOrder.nameAZ) {
        _displayEntries.sort((a, b) => a.service.toLowerCase().compareTo(b.service.toLowerCase()));
     } else { // dateAdded (Newest First)
        _displayEntries.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
     }
     _filterEntries(); // --- MODIFIED: Re-apply filter after sorting ---
  }


  Future<void> _loadPasswordEntries() async {
    if (!mounted) return;
    setState(() { _isLoading = true; });

    final key = EncryptionKeyService.instance.getKey();
    if (key == null) {
       print("Error: Encryption key not available for loading entries. Locking app.");
       if (mounted) {
         InactivityService.instance._lockApp(forceClearKey: false);
       }
       return;
    }
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));

    try {
      final allStoredData = await _storage.readAll(aOptions: _getAndroidOptions());
      final Map<String, String> allEntries = Map.from(allStoredData)
        ..remove(masterPasswordHashKey)
        ..remove(masterPasswordSaltKey);

      final List<PasswordEntry> loadedDisplayEntries = [];
      final Map<String, String> loadedEncryptedData = {};

      allEntries.forEach((storageKey, storedValue) {
        try {
          final combinedBytes = base64Decode(storedValue);
          if (combinedBytes.length < 12) {
             throw Exception('Stored data too short to contain IV.');
          }
          final iv = encrypt.IV(combinedBytes.sublist(0, 12));
          final ciphertextBytes = combinedBytes.sublist(12);
          final encryptedData = encrypt.Encrypted(ciphertextBytes);

          final decryptedJson = encrypter.decrypt(encryptedData, iv: iv);
          final Map<String, dynamic> json = jsonDecode(decryptedJson);
          final fullEntry = PasswordEntry.fromJson(json);

          final displayEntry = PasswordEntry(
            service: fullEntry.service,
            username: fullEntry.username,
            password: "••••••••", // Placeholder
            dateAdded: fullEntry.dateAdded,
          );
          loadedDisplayEntries.add(displayEntry);
          loadedEncryptedData[fullEntry.service] = storedValue;

        } catch (e) {
          print("Error decoding/decrypting entry for key '$storageKey': $e. Skipping entry.");
        }
      });

      _displayEntries = loadedDisplayEntries;
      _encryptedDataMap = loadedEncryptedData;

      _sortEntries(); // Sort the main display list
      _filterEntries(); // Initialize the filtered list

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print("Error loading password entries: $e");
      if (mounted) {
        setState(() { _isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading passwords: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _deletePasswordEntry(String originalServiceName) async {
    if (!mounted) return;
    final String storageKey = normalizeDomain(originalServiceName);

    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text('Are you sure you want to delete the password for "$originalServiceName"?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              child: const Text('Delete'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmDelete == true && mounted) {
      try {
        await _storage.delete(key: storageKey, aOptions: _getAndroidOptions());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Password for "$originalServiceName" deleted.')),
          );
          _loadPasswordEntries(); // Reload and re-sort/re-filter
        }
      } catch (e) {
        print("Error deleting password entry: $e");
         if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting password: ${e.toString()}')),
          );
         }
      }
    }
  }

  // --- MODIFIED: Decrypts on demand, moved showDialog inside try block ---
  void _showPasswordDetails(PasswordEntry displayEntry) async {
    if (!mounted) return;

    final key = EncryptionKeyService.instance.getKey();
    if (key == null) {
       print("Error: Encryption key not available for showing details. Locking app.");
       InactivityService.instance._lockApp(forceClearKey: false);
       return;
    }
    final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
    final String? storedValue = _encryptedDataMap[displayEntry.service];

    if (storedValue == null) {
        print("Error: Could not find encrypted data for service ${displayEntry.service}");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error retrieving entry data.')),
        );
        return;
    }

    PasswordEntry? fullEntry; // Make it nullable here
    try {
      final combinedBytes = base64Decode(storedValue);
      final iv = encrypt.IV(combinedBytes.sublist(0, 12));
      final ciphertextBytes = combinedBytes.sublist(12);
      final encryptedData = encrypt.Encrypted(ciphertextBytes);
      final decryptedJson = encrypter.decrypt(encryptedData, iv: iv);
      final Map<String, dynamic> json = jsonDecode(decryptedJson);
      fullEntry = PasswordEntry.fromJson(json); // Assign here

      // --- MOVED showDialog INSIDE try block after successful decryption ---
      if (fullEntry == null || !mounted) return; // Check again before showing dialog

      bool isPasswordVisible = false;
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          // Use a local variable for the dialog to ensure non-null access
          final PasswordEntry entryToShow = fullEntry!;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(entryToShow.service),
                content: SingleChildScrollView(
                  child: ListBody(
                    children: <Widget>[
                      _buildDetailRow('Username:', entryToShow.username, true),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              isPasswordVisible ? entryToShow.password : '••••••••',
                              style: const TextStyle(fontSize: 16),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: Icon(isPasswordVisible ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setDialogState(() => isPasswordVisible = !isPasswordVisible),
                            tooltip: isPasswordVisible ? 'Hide password' : 'Show password',
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            onPressed: () {
                              ClipboardService.instance.copyAndClearAfterDelay(entryToShow.password);
                              if (mounted) {
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Password copied to clipboard! (Will clear soon)')),
                                  );
                              }
                            },
                            tooltip: 'Copy password',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // --- MODIFIED: Add Edit Button to Dialog Actions ---
                actions: <Widget>[
                  TextButton(
                    child: const Text('Edit'),
                    onPressed: () {
                      Navigator.pop(context); // Close the dialog first
                      // Pass the original displayEntry which contains the service name needed by _navigateToEditPage
                      _navigateToEditPage(displayEntry);
                    },
                  ),
                  TextButton(
                    child: const Text('Close'),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
                // --- End Modification ---
              );
            },
          );
        },
      );
      // --- End moving showDialog ---

    } catch (e) {
       print("Error decrypting entry for details view: $e");
       if (mounted) { // Check mounted before showing SnackBar
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Error decrypting entry.')),
         );
       }
       return;
    }
  }
  // --- End Modification ---


  // Navigate to Edit Page
  void _navigateToEditPage(PasswordEntry displayEntry) async {
     if (!mounted) return;

     // Decrypt the full entry first
     final key = EncryptionKeyService.instance.getKey();
     if (key == null) {
        print("Error: Encryption key not available for editing. Locking app.");
        InactivityService.instance._lockApp(forceClearKey: false);
        return;
     }
     final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
     final String? storedValue = _encryptedDataMap[displayEntry.service];

     if (storedValue == null) {
         print("Error: Could not find encrypted data for service ${displayEntry.service}");
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Error retrieving entry data for editing.')),
         );
         return;
     }

     PasswordEntry? fullEntry;
     try {
       final combinedBytes = base64Decode(storedValue);
       final iv = encrypt.IV(combinedBytes.sublist(0, 12));
       final ciphertextBytes = combinedBytes.sublist(12);
       final encryptedData = encrypt.Encrypted(ciphertextBytes);
       final decryptedJson = encrypter.decrypt(encryptedData, iv: iv);
       final Map<String, dynamic> json = jsonDecode(decryptedJson);
       fullEntry = PasswordEntry.fromJson(json);
     } catch (e) {
        print("Error decrypting entry for edit view: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error decrypting entry for editing.')),
        );
        return;
     }

     if (fullEntry == null || !mounted) return;

     // Navigate to the Edit page, passing the original service name and the full entry
     final result = await Navigator.pushNamed(
       context,
       '/edit_password',
       arguments: {
         'originalServiceName': fullEntry.service, // Pass original name
         'entry': fullEntry, // Pass fully decrypted entry
       },
     );

     // Refresh list if edit was successful
     if (result == true && mounted) {
       _loadPasswordEntries();
     }
  }


  Widget _buildDetailRow(String label, String value, bool allowCopy) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(flex: 2, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
        Expanded(flex: 3, child: Text(value, textAlign: TextAlign.end, overflow: TextOverflow.ellipsis)),
        if (allowCopy)
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$label copied to clipboard!')),
                );
              }
            },
            tooltip: 'Copy $label',
          ),
        if (!allowCopy) const SizedBox(width: 48),
      ],
    );
  }

  void _navigateToAddPasswordPage() async {
    if (!mounted) return;
    final result = await Navigator.pushNamed(context, '/add_password');
    if (result == true && mounted) {
      _loadPasswordEntries(); // Reload and re-sort
    }
  }

  Widget _buildFallbackAvatar(PasswordEntry entry) {
    String displayInitial = '?';
    String serviceName = entry.service.trim();
    if (serviceName.isNotEmpty) {
        displayInitial = serviceName[0].toUpperCase();
    }

    return CircleAvatar(
      backgroundColor: Colors.primaries[entry.service.hashCode % Colors.primaries.length].shade700,
      foregroundColor: Colors.white,
      child: Text(displayInitial),
    );
  }

  String _cleanDomainForFavicon(String serviceUrl) {
      String domain = serviceUrl.trim();
      Uri? uri = Uri.tryParse(domain.contains('://') ? domain : 'http://$domain');
      if (uri != null && uri.host.isNotEmpty && uri.host.contains('.')) {
          return uri.host;
      }
      return '';
  }

  // Handle Menu Selection
  void _onMenuItemSelected(String value) {
    switch (value) {
      case 'generate_password':
        Navigator.pushNamed(context, '/generate_password');
        break;
      case 'about':
         Navigator.pushNamed(context, '/about');
        break;
      case 'settings':
         Navigator.pushNamed(context, '/settings');
         break;
      case 'lock':
         EncryptionKeyService.instance.clearKey();
         navigatorKey.currentState?.pushNamedAndRemoveUntil(
            '/enter_master', (route) => false);
         break;
    }
  }

  // Toggle Sort Order
  void _toggleSortOrder() {
     setState(() {
        _currentSortOrder = (_currentSortOrder == SortOrder.nameAZ)
            ? SortOrder.dateAdded
            : SortOrder.nameAZ;
        _sortEntries(); // Re-sort the display list and re-filter
     });
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(
         content: Text('Sorted by: ${_currentSortOrder == SortOrder.nameAZ ? "Name (A-Z)" : "Date Added (Newest)"}'),
         duration: const Duration(seconds: 1),
       ),
     );
  }


  @override
  Widget build(BuildContext context) {
    final IconData sortIcon = _currentSortOrder == SortOrder.nameAZ
        ? Icons.sort_by_alpha
        : Icons.history_toggle_off_rounded;

    final String sortTooltip = _currentSortOrder == SortOrder.nameAZ
        ? 'Sorted by Name (A-Z)'
        : 'Sorted by Date Added (Newest First)';

    Widget bodyContent;
    if (_isLoading) {
       bodyContent = const Center(child: CircularProgressIndicator());
    } else if (_displayEntries.isEmpty) {
       bodyContent = Center(
         child: Padding(
           padding: const EdgeInsets.all(16.0),
           child: Text(
             'No passwords saved yet.\nTap the + button to add one!',
             textAlign: TextAlign.center,
             style: Theme.of(context).textTheme.headlineSmall?.copyWith(
               color: Theme.of(context).colorScheme.onSurfaceVariant
             ),
           ),
         ),
       );
    } else if (_filteredDisplayEntries.isEmpty) {
       bodyContent = Center(
         child: Padding(
           padding: const EdgeInsets.all(16.0),
           child: Text(
             'No entries match your search.',
             textAlign: TextAlign.center,
             style: Theme.of(context).textTheme.titleMedium?.copyWith(
               color: Theme.of(context).colorScheme.onSurfaceVariant
             ),
           ),
         ),
       );
    } else {
       bodyContent = ListView.builder(
         padding: const EdgeInsets.only(bottom: 80, top: 0),
         itemCount: _filteredDisplayEntries.length,
         itemBuilder: (context, index) {
           final entry = _filteredDisplayEntries[index];
           final String domainForFavicon = _cleanDomainForFavicon(entry.service);
           final String faviconUrl = domainForFavicon.isNotEmpty
             ? 'https://www.google.com/s2/favicons?domain=$domainForFavicon&sz=64'
             : '';

           return Card(
             margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 5.0),
             elevation: 2,
             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
             child: ListTile(
               leading: SizedBox(
                 width: 40,
                 height: 40,
                 child: faviconUrl.isNotEmpty
                   ? Image.network(
                       faviconUrl,
                       fit: BoxFit.contain,
                       width: 40,
                       height: 40,
                       errorBuilder: (context, error, stackTrace) {
                         print("Error loading favicon for $domainForFavicon: $error");
                         return _buildFallbackAvatar(entry);
                       },
                       loadingBuilder: (context, child, loadingProgress) {
                         if (loadingProgress == null) return child;
                         return Center(
                           child: CircularProgressIndicator(
                             strokeWidth: 2.0,
                             value: loadingProgress.expectedTotalBytes != null
                                 ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                 : null,
                           ),
                         );
                       },
                     )
                   : _buildFallbackAvatar(entry),
               ),
               title: Text(entry.service, style: const TextStyle(fontWeight: FontWeight.w500)),
               subtitle: Text(entry.username),
               trailing: Row(
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   IconButton(
                     icon: Icon(Icons.edit_outlined, color: Theme.of(context).colorScheme.secondary),
                     onPressed: () => _navigateToEditPage(entry),
                     tooltip: 'Edit Entry',
                   ),
                   IconButton(
                     icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                     onPressed: () => _deletePasswordEntry(entry.service),
                     tooltip: 'Delete Entry',
                   ),
                   IconButton(
                     icon: Icon(Icons.visibility_outlined, color: Theme.of(context).colorScheme.secondary),
                     onPressed: () => _showPasswordDetails(entry),
                     tooltip: 'View Details',
                   ),
                 ],
               ),
               onTap: () => _showPasswordDetails(entry),
             ),
           );
         },
       );
    }


    return Scaffold(
        appBar: AppBar(
          title: const Text('Password Manager'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: Icon(sortIcon),
              tooltip: sortTooltip,
              onPressed: _toggleSortOrder,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadPasswordEntries,
              tooltip: 'Refresh List',
            ),
            PopupMenuButton<String>(
              onSelected: _onMenuItemSelected,
              icon: const Icon(Icons.more_vert),
              tooltip: 'More options',
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'generate_password',
                  child: ListTile(
                    leading: Icon(Icons.password_rounded),
                    title: Text('Generate Password'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'settings',
                  child: ListTile(
                    leading: Icon(Icons.settings_outlined),
                    title: Text('Settings'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                 const PopupMenuItem<String>(
                  value: 'about',
                  child: ListTile(
                    leading: Icon(Icons.info_outline_rounded),
                    title: Text('About'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'lock',
                  child: ListTile(
                     leading: Icon(Icons.logout),
                     title: Text('Lock App'),
                     contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Column(
           children: [
             Padding(
               padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 8.0),
               child: TextField(
                 controller: _searchController,
                 decoration: InputDecoration(
                   labelText: 'Search',
                   hintText: 'Search by Service or Username...',
                   prefixIcon: const Icon(Icons.search),
                   suffixIcon: _searchQuery.isNotEmpty
                       ? IconButton(
                           icon: const Icon(Icons.clear),
                           tooltip: 'Clear Search',
                           onPressed: () {
                             _searchController.clear();
                           },
                         )
                       : null,
                   border: OutlineInputBorder(
                     borderRadius: BorderRadius.circular(12.0),
                   ),
                   contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                 ),
               ),
             ),
             Expanded(
               child: bodyContent,
             ),
           ],
         ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _navigateToAddPasswordPage,
          tooltip: 'Add New Password',
          icon: const Icon(Icons.add),
          label: const Text('Add Password'),
        ),
      );
  }
}