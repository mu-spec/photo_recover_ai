import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../utils/app_theme.dart';
import '../utils/app_constants.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_OnboardingPage> _pages = const [
    _OnboardingPage(
      icon: Icons.shield_outlined,
      title: 'Welcome to Media Rescue',
      description:
          'Find and restore accessible, cached, and recently deleted media (device dependent). '
          'Everything stays local on your phone.',
      illustrationIcons: [
        Icons.photo_library_outlined,
        Icons.videocam_outlined,
        Icons.folder_outlined,
      ],
    ),
    _OnboardingPage(
      icon: Icons.lock_outline,
      title: '100% Private & Secure',
      description:
          'All scanning happens on your device. No data is ever uploaded to any server. '
          'Your files and privacy are our top priority.',
      illustrationIcons: [
        Icons.security,
        Icons.cloud_off,
        Icons.visibility_off,
      ],
    ),
    _OnboardingPage(
      icon: Icons.psychology_outlined,
      title: 'Smart Recovery',
      description:
          'Smart scanning indexes Camera, Gallery, WhatsApp and other accessible folders. '
          'Results are categorized into existing media, cache, and recently deleted traces.',
      illustrationIcons: [
        Icons.auto_awesome,
        Icons.scanner,
        Icons.smart_toy_outlined,
      ],
    ),
    _OnboardingPage(
      icon: Icons.restore_outlined,
      title: 'One Tap Recovery',
      description:
          'Select files and recover them instantly to your device. '
          'Recover files to your device safely with one tap.',
      illustrationIcons: [
        Icons.touch_app,
        Icons.download_done,
        Icons.folder_special,
      ],
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _finishOnboarding() async {
    final settingsProvider =
        Provider.of<AppSettingsProvider>(context, listen: false);
    await settingsProvider.settings.setFirstLaunchDone();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: TextButton(
                  onPressed: _finishOnboarding,
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),

            // PageView
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  return _OnboardingPageContent(
                    page: _pages[index],
                    pageIndex: index,
                  );
                },
              ),
            ),

            // Dots indicator
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (index) {
                  final isActive = index == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: isActive ? 28 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppTheme.primaryColor
                          : AppTheme.dividerColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),

            // Action button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    if (_currentPage < _pages.length - 1) {
                      _goToPage(_currentPage + 1);
                    } else {
                      _finishOnboarding();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _currentPage < _pages.length - 1
                            ? 'Next'
                            : 'Get Started',
                      ),
                      if (_currentPage < _pages.length - 1) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward, size: 20),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Privacy badge
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock,
                      size: 14,
                      color: AppTheme.successColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'No data uploaded \u2022 100% Offline',
                      style: TextStyle(
                        color: AppTheme.successColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage {
  final IconData icon;
  final String title;
  final String description;
  final List<IconData> illustrationIcons;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.description,
    required this.illustrationIcons,
  });
}

class _OnboardingPageContent extends StatefulWidget {
  final _OnboardingPage page;
  final int pageIndex;

  const _OnboardingPageContent({
    required this.page,
    required this.pageIndex,
  });

  @override
  State<_OnboardingPageContent> createState() => _OnboardingPageContentState();
}

class _OnboardingPageContentState extends State<_OnboardingPageContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const SizedBox(height: 20),

              // Main icon in circular gradient container
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: _getGradientForPage(widget.pageIndex),
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _getGradientForPage(widget.pageIndex)[0]
                          .withOpacity(0.3),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(
                  widget.page.icon,
                  color: Colors.white,
                  size: 60,
                ),
              ),

              const SizedBox(height: 40),

              // Title
              Text(
                widget.page.title,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              // Description
              Text(
                widget.page.description,
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 32),

              // Illustration icons row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: widget.page.illustrationIcons.map((icon) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      icon,
                      color: AppTheme.primaryColor,
                      size: 26,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Color> _getGradientForPage(int index) {
    switch (index) {
      case 0:
        return AppColors.gradientPrimary;
      case 1:
        return AppColors.gradientAccent;
      case 2:
        return AppColors.gradientWarm;
      case 3:
        return const [Color(0xFF8B5CF6), Color(0xFF6366F1)];
      default:
        return AppColors.gradientPrimary;
    }
  }
}

