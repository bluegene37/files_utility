import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/global_db_service.dart';
import '../services/local_db_service.dart';
import '../services/history_service.dart';
import '../main.dart'; // To access MainAppWrapper

class ProfileSelectionScreen extends StatefulWidget {
  const ProfileSelectionScreen({super.key});

  @override
  State<ProfileSelectionScreen> createState() => _ProfileSelectionScreenState();
}

class _ProfileSelectionScreenState extends State<ProfileSelectionScreen> {
  bool _isLoading = false;
  String? _selectedProfileId;
  final _nameController = TextEditingController();
  final _descController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final profiles = GlobalDbService().profiles;
    if (profiles.isNotEmpty) {
      _selectedProfileId = profiles.first.id;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _continueWithProfile(String profileId) async {
    setState(() {
      _isLoading = true;
    });

    // Initialize local DB and History with the selected profile
    await LocalDbService().init(profileId);
    HistoryService().init(profileId);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MainAppWrapper()),
      );
    }
  }

  Future<void> _createNewProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final desc = _descController.text.trim();

    setState(() {
      _isLoading = true;
    });

    final newProfile = await GlobalDbService().createProfile(name, desc);
    
    // Clear inputs
    _nameController.clear();
    _descController.clear();
    
    await _continueWithProfile(newProfile.id);
  }

  @override
  Widget build(BuildContext context) {
    final profiles = GlobalDbService().profiles;

    return Scaffold(
      body: Container(
        decoration: AppDecorations.gradientBackground,
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App icon & Title
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: 0.3),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/images/app_icon.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Select Run Session',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose a profile to keep settings and history isolated.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Profile Selection Card
                  Container(
                    width: 400,
                    padding: const EdgeInsets.all(24),
                    decoration: AppDecorations.glassCard(),
                    child: _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Existing Profiles',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Select Profile',
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _selectedProfileId,
                                    isExpanded: true,
                                    itemHeight: 68,
                                    dropdownColor: AppColors.bgDark2,
                                    items: profiles.map((p) {
                                      return DropdownMenuItem<String>(
                                        value: p.id,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(p.name, style: const TextStyle(color: AppColors.textPrimary)),
                                            if (p.description.isNotEmpty)
                                              Text(
                                                p.description,
                                                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          _selectedProfileId = val;
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _selectedProfileId == null
                                    ? null
                                    : () => _continueWithProfile(_selectedProfileId!),
                                child: const Text('Continue with Selected'),
                              ),
                              const SizedBox(height: 24),
                              const Row(
                                children: [
                                  Expanded(child: Divider(color: AppColors.cardBorder)),
                                  Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 12),
                                    child: Text('OR', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                                  ),
                                  Expanded(child: Divider(color: AppColors.cardBorder)),
                                ],
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'Create New Profile',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _nameController,
                                decoration: const InputDecoration(
                                  labelText: 'Profile Name',
                                  hintText: 'e.g., Nightly Backup, Server A',
                                ),
                                style: const TextStyle(color: AppColors.textPrimary),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _descController,
                                decoration: const InputDecoration(
                                  labelText: 'Description (Optional)',
                                  hintText: 'e.g., Daily copy of photos to external drive',
                                ),
                                style: const TextStyle(color: AppColors.textPrimary),
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: () {
                                  if (_nameController.text.trim().isNotEmpty) {
                                    _createNewProfile();
                                  }
                                },
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Create & Continue'),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
