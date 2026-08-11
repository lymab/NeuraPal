import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.mentiumlabs.sadiky',
  appName: 'Sadiky',
  webDir: 'www',
  appendUserAgent: 'Capacitor Sadiky',
  server: {
    // Remote-first: the app loads sadiky.com directly. errorPath falls back
    // to the local www/index.html offline/retry page when the load fails.
    url: 'https://sadiky.com',
    errorPath: 'index.html',
    cleartext: false,
    allowNavigation: [
      'sadiky.com',
      'accounts.google.com',
      '*.google.com',
      'appleid.apple.com',
      '*.apple.com',
    ]
  },
  ios: {
    contentInset: 'automatic',
    preferredContentMode: 'mobile',
    scheme: 'Sadiky',
    backgroundColor: '#1B2A4A',
    allowsLinkPreview: false,
    scrollEnabled: true
  },
  plugins: {
    SplashScreen: {
      launchShowDuration: 1500,
      launchAutoHide: true,
      backgroundColor: '#1B2A4A',
      showSpinner: false,
      launchFadeOutDuration: 300
    },
    StatusBar: {
      style: 'DARK',
      backgroundColor: '#1B2A4A',
      overlaysWebView: false
    },
    Keyboard: {
      resize: 'body',
      resizeOnFullScreen: true
    }
  }
};

export default config;
