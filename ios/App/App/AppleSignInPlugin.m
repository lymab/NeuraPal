#import <Capacitor/Capacitor.h>

CAP_PLUGIN(AppleSignInPlugin, "AppleSignInPlugin",
    CAP_PLUGIN_METHOD(signIn, CAPPluginReturnPromise);
)
