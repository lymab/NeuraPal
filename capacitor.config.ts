import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.mentiumlabs.neurapal',
  appName: 'NeuraPal',
  webDir: 'www',
  appendUserAgent: 'Capacitor NeuraPal',
  server: {
    url: 'https://neurapal.mentiumlabs.com/',
    cleartext: false,
    allowNavigation: [
      'neurapal.mentiumlabs.com',
      'accounts.google.com',
      '*.google.com',
      'appleid.apple.com',
      '*.apple.com'
    ]
  },
  ios: {
    contentInset: 'automatic',
    preferredContentMode: 'mobile',
    scheme: 'NeuraPal',
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
