import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Ad Service - Real Google AdMob Integration
class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  // Your real AdMob ad unit IDs
  static const String _bannerAdUnitId = 'ca-app-pub-7540130362404221/4746004376';
  static const String _interstitialAdUnitId = 'ca-app-pub-7540130362404221/4466802771';

  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;
  InterstitialAd? _interstitialAd;
  bool _isInterstitialLoaded = false;
  bool _isInterstitialLoading = false;
  bool _isShowingInterstitial = false;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await MobileAds.instance.initialize();
      _isInitialized = true;
      debugPrint('AdMob initialized successfully');
      // Preload interstitial so first eligible action can show an ad reliably.
      loadInterstitialAd();
    } catch (e) {
      debugPrint('AdMob initialization failed: $e');
    }
  }

  void loadBannerAd({VoidCallback? onLoaded}) {
    if (!_isInitialized) return;

    _bannerAd?.dispose();

    _bannerAd = BannerAd(
      adUnitId: _bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          _isBannerLoaded = true;
          debugPrint('Banner ad loaded successfully');
          onLoaded?.call();
        },
        onAdFailedToLoad: (ad, error) {
          _isBannerLoaded = false;
          debugPrint('Banner ad failed to load: ${error.message}');
          ad.dispose();
        },
      ),
    );

    _bannerAd!.load();
  }

  Widget getBannerAdWidget() {
    if (_bannerAd != null && _isBannerLoaded) {
      return Container(
        color: Colors.transparent,
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      );
    }
    return const SizedBox.shrink();
  }

  Widget buildBannerContainer() {
    return Container(
      color: Colors.transparent,
      height: _isBannerLoaded ? 60.0 : 0.0,
      child: _isBannerLoaded
          ? Center(child: getBannerAdWidget())
          : const SizedBox.shrink(),
    );
  }

  bool get isBannerLoaded => _isBannerLoaded;

  void loadInterstitialAd() {
    if (!_isInitialized || _isInterstitialLoading || _isInterstitialLoaded) return;
    _isInterstitialLoading = true;

    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _isInterstitialLoading = false;
          _interstitialAd = ad;
          _isInterstitialLoaded = true;
          debugPrint('Interstitial ad loaded successfully');

          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              debugPrint('Interstitial ad dismissed');
              _isShowingInterstitial = false;
              ad.dispose();
              _interstitialAd = null;
              _isInterstitialLoaded = false;
              loadInterstitialAd();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              debugPrint('Interstitial ad failed to show: ${error.message}');
              _isShowingInterstitial = false;
              ad.dispose();
              _interstitialAd = null;
              _isInterstitialLoaded = false;
              loadInterstitialAd();
            },
          );
        },
        onAdFailedToLoad: (error) {
          _isInterstitialLoading = false;
          _isInterstitialLoaded = false;
          debugPrint('Interstitial ad failed to load: $error');
        },
      ),
    );
  }

  Future<bool> showInterstitialAd({bool waitForLoad = false, int waitTimeoutMs = 1800}) async {
    if (_isShowingInterstitial) {
      debugPrint('Interstitial is already showing, skipping duplicate request.');
      return false;
    }

    if (_interstitialAd == null || !_isInterstitialLoaded) {
      debugPrint('Interstitial ad not ready, loading...');
      loadInterstitialAd();
      if (!waitForLoad) return false;

      final deadline = DateTime.now().add(Duration(milliseconds: waitTimeoutMs));
      while (DateTime.now().isBefore(deadline)) {
        if (_interstitialAd != null && _isInterstitialLoaded) break;
        await Future.delayed(const Duration(milliseconds: 120));
      }
      if (_interstitialAd == null || !_isInterstitialLoaded) return false;
    }

    try {
      _isShowingInterstitial = true;
      await _interstitialAd!.show();
      _isInterstitialLoaded = false;
      return true;
    } catch (e) {
      debugPrint('Interstitial show error: $e');
      _isInterstitialLoaded = false;
      _interstitialAd?.dispose();
      _interstitialAd = null;
      loadInterstitialAd();
      return false;
    } finally {
      _isShowingInterstitial = false;
    }
  }

  void dispose() {
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    _bannerAd = null;
    _interstitialAd = null;
    _isBannerLoaded = false;
    _isInterstitialLoaded = false;
    _isShowingInterstitial = false;
  }
}
