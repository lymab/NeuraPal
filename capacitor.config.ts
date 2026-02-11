import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.mentiumlabs.neurapal',
  appName: 'NeuraPal',
  webDir: 'www',
  server: {
    url: 'https://neurapal.mentiumlabs.com/',
    cleartext: false
  },
  ios: {
    contentInset: 'automatic',
    preferredContentMode: 'mobile',
    scheme: 'NeuraPal',
    backgroundColor: '#1B2A4A'
  },
  plugins: {
    SplashScreen: {
      launchShowDuration: 2000,
      launchAutoHide: true,
      backgroundColor: '#1B2A4A',
      showSpinner: false,
      launchFadeOutDuration: 400
    }
  }
};

export default config;
